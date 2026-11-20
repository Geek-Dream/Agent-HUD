import Foundation

/// 一条被用户从列表里「删除」的会话记录。
///
/// AgentHUD 从不删除 Agent 的日志，所以「删除」只能是显示层的一次静音：
/// 记住删除那一刻这条会话的最后活动时间，之后只要没有新的活动，它就不出现。
struct SessionDismissal: Equatable {
    /// 删除时该会话的 `lastActivityAt`。会话必须超过这个时间点才算「状态更新了」。
    let activityBaseline: Date
    /// 删除发生的墙上时间，仅用于过期清理。
    let dismissedAt: Date
}

/// 被删除会话的持久化记录，键是 `AgentSession.id`。
///
/// 语义：删除之后，等到这条会话又有新活动（新的消息、动作或状态变化都会推进
/// `lastActivityAt`）才重新出现在列表里。比较的是活动时间而不是删除时刻，
/// 所以即使 HUD 在删除期间没有运行，重新打开后也能正确判断它是否已经动过。
final class SessionDismissalStore {
    private static let storageKey = "hud.dismissedSessions.v1"
    /// 记录本身会一直留着，只有超过这个时长才清理，避免 UserDefaults 无限增长。
    private static let retention: TimeInterval = 30 * 86_400

    private let defaults: UserDefaults
    private(set) var records: [String: SessionDismissal]

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        records = Self.load(from: defaults)
        pruneExpired(now: now)
    }

    func dismissal(for sessionID: String) -> SessionDismissal? {
        records[sessionID]
    }

    /// 会话是否仍处于「已删除」状态。
    ///
    /// 只有活动时间没有超过删除时的基线才算删除中；一旦有新活动就立刻解除，
    /// 不需要额外刷新或用户操作。
    func isDismissed(sessionID: String, lastActivityAt: Date) -> Bool {
        guard let record = records[sessionID] else {
            return false
        }
        return lastActivityAt <= record.activityBaseline
    }

    /// 当前扫描结果里仍处于「已删除」状态的会话 ID。
    ///
    /// 视图层用这个集合做显示过滤，而不是逐条调用 `isDismissed`：一次刷新只算一遍，
    /// 列表、计数和折叠态文案才不会对同一条会话给出不同结论。
    func dismissedIDs(in sessions: [AgentSession]) -> Set<String> {
        guard !records.isEmpty else {
            return []
        }
        return Set(sessions.compactMap { session in
            isDismissed(sessionID: session.id, lastActivityAt: session.lastActivityAt)
                ? session.id
                : nil
        })
    }

    @discardableResult
    func dismiss(sessionID: String, lastActivityAt: Date, now: Date = .now) -> Bool {
        guard !sessionID.isEmpty else {
            return false
        }
        records[sessionID] = SessionDismissal(
            activityBaseline: lastActivityAt,
            dismissedAt: now
        )
        persist()
        return true
    }

    @discardableResult
    func restore(sessionID: String) -> Bool {
        guard records.removeValue(forKey: sessionID) != nil else {
            return false
        }
        persist()
        return true
    }

    /// 清空全部删除记录。
    ///
    /// 不能只遍历当前扫描结果里的会话：记录可能属于已经被 24 条上限挤出、
    /// 这一轮根本没扫到的会话，只按扫描结果恢复会留下残留记录，
    /// 那条会话下次被扫到时又会莫名其妙地消失。
    func restoreAll() {
        guard !records.isEmpty else {
            return
        }
        records.removeAll()
        persist()
    }

    /// 会话已经有新活动时清掉记录，避免旧记录无限累积。
    ///
    /// 不能按「不在本次扫描结果里」来清理：`SessionScanner` 只返回最近 24 条，
    /// 被挤出去的会话并不等于已经结束，按扫描结果清理会让它们下次扫描又冒出来。
    func clearAwakened(in sessions: [AgentSession], now: Date = .now) {
        var changed = false
        for session in sessions where records[session.id] != nil {
            if !isDismissed(sessionID: session.id, lastActivityAt: session.lastActivityAt) {
                records.removeValue(forKey: session.id)
                changed = true
            }
        }
        if pruneExpired(now: now) {
            changed = true
        }
        if changed {
            persist()
        }
    }

    @discardableResult
    private func pruneExpired(now: Date) -> Bool {
        let expired = records.filter { now.timeIntervalSince($0.value.dismissedAt) > Self.retention }
        guard !expired.isEmpty else {
            return false
        }
        for key in expired.keys {
            records.removeValue(forKey: key)
        }
        persist()
        return true
    }

    private func persist() {
        // 必须存整数毫秒：`UserDefaults` 会把 Double 写成只有 6 位小数的字符串，
        // 读回来比原值略小，已删除的会话就会被误判成「有新活动」而立刻弹回列表。
        // 基线向上取整，保证记录的删除时刻不会早于会话真实的最后活动时间。
        let encoded = records.mapValues { record in
            [
                "activity": Self.milliseconds(record.activityBaseline),
                "dismissedAt": Self.milliseconds(record.dismissedAt)
            ]
        }
        defaults.set(encoded, forKey: Self.storageKey)
    }

    private static func milliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded(.up))
    }

    private static func load(from defaults: UserDefaults) -> [String: SessionDismissal] {
        guard let raw = defaults.dictionary(forKey: storageKey) as? [String: [String: Any]] else {
            return [:]
        }
        var decoded: [String: SessionDismissal] = [:]
        for (sessionID, value) in raw {
            guard let activity = Self.milliseconds(value["activity"]),
                  let dismissedAt = Self.milliseconds(value["dismissedAt"]) else {
                continue
            }
            decoded[sessionID] = SessionDismissal(
                activityBaseline: Date(timeIntervalSince1970: TimeInterval(activity) / 1000),
                dismissedAt: Date(timeIntervalSince1970: TimeInterval(dismissedAt) / 1000)
            )
        }
        return decoded
    }

    private static func milliseconds(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        default:
            return nil
        }
    }
}
