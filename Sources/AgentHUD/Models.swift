import Foundation

enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude
    case pi
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude Code"
        case .pi:
            return "Pi"
        case .opencode:
            return "OpenCode"
        }
    }

    var shortName: String {
        switch self {
        case .codex:
            return "CODEX"
        case .claude:
            return "CLAUDE"
        case .pi:
            return "PI"
        case .opencode:
            return "OPENCODE"
        }
    }
}

enum AgentStatus: String, Codable, CaseIterable {
    case starting
    case working
    case waitingUser
    case idle
    case completed
    case failed
    case unknown

    var protocolValue: String {
        self == .waitingUser ? "WaitingUser" : rawValue.capitalized
    }

    var label: String {
        switch self {
        case .starting:
            return "启动中"
        case .working:
            return "工作中"
        case .waitingUser:
            return "等待确认"
        case .idle:
            return "空闲"
        case .completed:
            return "已完成"
        case .failed:
            return "出错"
        case .unknown:
            return "未知"
        }
    }

    var shortLabel: String {
        switch self {
        case .starting:
            return "启动"
        case .working:
            return "工作"
        case .waitingUser:
            return "等待"
        case .idle:
            return "空闲"
        case .completed:
            return "完成"
        case .failed:
            return "错误"
        case .unknown:
            return "未知"
        }
    }

    var sortRank: Int {
        switch self {
        case .working, .starting:
            return 0
        case .waitingUser:
            return 1
        case .completed:
            return 2
        case .failed:
            return 3
        case .idle:
            return 4
        case .unknown:
            return 5
        }
    }

    var isActive: Bool {
        self == .starting || self == .working || self == .waitingUser
    }

    var isRunning: Bool {
        self == .starting || self == .working
    }
}

enum StatusConfidence: String, Codable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high:
            return "高可信"
        case .medium:
            return "推断"
        case .low:
            return "低可信"
        }
    }
}

struct TaskRun: Identifiable, Hashable {
    let id: String
    let objective: String
    let summary: String
    let actions: [String]
    let filesChanged: [String]
    let completedAt: Date
    let status: AgentStatus
}

struct GitContext: Hashable {
    var repoRoot: String
    var branch: String
    var changedFiles: Int
    var insertions: Int
    var deletions: Int
    var isDirty: Bool
}

enum TaskTitleSource: String, Hashable {
    case automatic
    case ai
    case user

    var label: String {
        switch self {
        case .automatic:
            return "本地概括"
        case .ai:
            return "AI 概括"
        case .user:
            return "我的备注"
        }
    }
}

struct ResolvedSessionTitle: Equatable {
    let value: String
    let source: TaskTitleSource
}

enum SessionTitleResolver {
    static func resolve(
        manualTitle: String?,
        aiTitle: String?,
        localTitle: String
    ) -> ResolvedSessionTitle {
        if let manualTitle,
           !TextTools.normalizedWhitespace(manualTitle).isEmpty {
            return ResolvedSessionTitle(value: manualTitle, source: .user)
        }
        if let aiTitle,
           !TextTools.normalizedWhitespace(aiTitle).isEmpty {
            return ResolvedSessionTitle(value: aiTitle, source: .ai)
        }
        return ResolvedSessionTitle(value: localTitle, source: .automatic)
    }
}

enum SessionImageSource: Hashable {
    case localPath(String)
    case dataURL(String)
    case unavailable
}

struct SessionImageAttachment: Identifiable, Hashable {
    let id: String
    let source: SessionImageSource
    let label: String?

    static func displayLabel(for index: Int) -> String {
        "[图片\(max(0, index) + 1)]"
    }
}

struct UserPromptSnapshot: Hashable {
    let text: String
    let sentAt: Date?
    let images: [SessionImageAttachment]
}

enum RunPagination {
    static let pageSize = 5

    static func nextCount(current: Int, total: Int) -> Int {
        min(max(total, 0), max(current, 0) + pageSize)
    }
}

struct AgentSession: Identifiable, Hashable {
    let id: String
    let provider: AgentProvider
    let providerSessionID: String
    let projectName: String
    let projectPath: String
    let title: String
    let titleSource: TaskTitleSource
    let status: AgentStatus
    let confidence: StatusConfidence
    let currentAction: String
    let currentFiles: [String]
    let startedAt: Date
    let lastActivityAt: Date
    let completedAt: Date?
    let runs: [TaskRun]
    let latestUserPrompt: UserPromptSnapshot?
    let sourcePath: String
    let isLive: Bool
    var git: GitContext?

    var duration: TimeInterval {
        max(0, (completedAt ?? lastActivityAt).timeIntervalSince(startedAt))
    }

    var lastRun: TaskRun? {
        runs.max(by: { $0.completedAt < $1.completedAt })
    }
}

enum SessionListLimit: Int, CaseIterable, Identifiable {
    case all = 0
    case recent3 = 3
    case recent5 = 5
    case recent10 = 10
    case recent15 = 15
    case recent20 = 20

    static let `default` = Self.recent10

    var id: Int { rawValue }

    var count: Int? {
        self == .all ? nil : rawValue
    }

    var label: String {
        self == .all ? "全部" : "最近 \(rawValue)"
    }
}

enum SessionImportanceOrder {
    static func ranks(_ ids: [String]) -> [String: Int] {
        Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
}

enum SessionListPolicy {
    static func visible(
        _ sessions: [AgentSession],
        limit: SessionListLimit,
        importantSessionIDs: Set<String>,
        importantSessionOrder: [String] = []
    ) -> [AgentSession] {
        let recentFirst = sessions.sorted {
            if $0.lastActivityAt != $1.lastActivityAt {
                return $0.lastActivityAt > $1.lastActivityAt
            }
            return $0.id < $1.id
        }
        guard let count = limit.count else {
            return recentFirst
        }
        let ranks = SessionImportanceOrder.ranks(importantSessionOrder)
        let starred = recentFirst.filter { importantSessionIDs.contains($0.id) }
            .enumerated()
            .sorted { lhs, rhs in
                let lhsRank = ranks[lhs.element.id] ?? Int.max
                let rhsRank = ranks[rhs.element.id] ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhsRank == Int.max, lhs.element.startedAt != rhs.element.startedAt {
                    return lhs.element.startedAt < rhs.element.startedAt
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        let ordinary = recentFirst.filter { !importantSessionIDs.contains($0.id) }
        return starred + ordinary.prefix(count)
    }
}

enum SessionOrdering {
    static func sorted(
        _ sessions: [AgentSession],
        importantSessionIDs: Set<String>,
        importantSessionOrder: [String],
        stableSessionOrder: [String] = []
    ) -> [AgentSession] {
        let ranks = SessionImportanceOrder.ranks(importantSessionOrder)
        let stableRanks = SessionImportanceOrder.ranks(stableSessionOrder)
        // Timestamp changes must not reshuffle equal-status rows. The explicit
        // ordinal also preserves starred fallback order across data-source enumeration.
        let indexed = sessions.enumerated().sorted { lhs, rhs in
            let lhsIsImportant = importantSessionIDs.contains(lhs.element.id)
            let rhsIsImportant = importantSessionIDs.contains(rhs.element.id)
            if lhsIsImportant != rhsIsImportant {
                return lhsIsImportant
            }
            if lhsIsImportant, rhsIsImportant {
                let lhsRank = ranks[lhs.element.id] ?? Int.max
                let rhsRank = ranks[rhs.element.id] ?? Int.max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return (ranks[lhs.element.id] ?? Int.max, lhs.offset)
                    < (ranks[rhs.element.id] ?? Int.max, rhs.offset)
            }
            if lhs.element.status.sortRank != rhs.element.status.sortRank {
                return lhs.element.status.sortRank < rhs.element.status.sortRank
            }
            return (stableRanks[lhs.element.id] ?? Int.max, lhs.offset)
                < (stableRanks[rhs.element.id] ?? Int.max, rhs.offset)
        }
        return indexed.map(\.element)
    }
}

enum SessionTransitionDetector {
    static func runningCompletionIDs(
        previousSessions: [AgentSession],
        currentSessions: [AgentSession]
    ) -> Set<String> {
        let currentStatuses = Dictionary(
            currentSessions.map { ($0.id, $0.status) },
            uniquingKeysWith: { _, latest in latest }
        )

        return Set(previousSessions.compactMap { session in
            guard session.status.isRunning,
                  currentStatuses[session.id] == .completed else {
                return nil
            }
            return session.id
        })
    }
}

enum SessionCompletionAnimation {
    static let exitDuration: TimeInterval = 0.42
    static let exitLifetime: TimeInterval = 0.46
    static let enterDelay: TimeInterval = 0.07
    static let enterDuration: TimeInterval = 0.34
    static let arrivalIdentityDuration: TimeInterval = 0.52
}

struct SessionRowPresentation: Identifiable {
    enum Phase: Hashable {
        case standard
        case departing
        case arriving
    }

    let session: AgentSession
    let phase: Phase
    let arrivalVisible: Bool

    var id: String {
        phase == .arriving ? "arriving:\(session.id)" : session.id
    }

    var isDeparting: Bool {
        phase == .departing
    }

    var isArriving: Bool {
        phase == .arriving
    }
}

enum SessionOutlinePolicy {
    static func shouldShow(status: AgentStatus, isImportant: Bool) -> Bool {
        guard isImportant else {
            return false
        }
        switch status {
        case .starting, .working, .waitingUser, .completed, .failed:
            return true
        case .idle, .unknown:
            return false
        }
    }
}

enum SessionRowSurfacePolicy {
    /// 每一行都按状态着色，让「工作中 / 等待 / 完成 / 出错」一眼可分。
    /// 空闲与未知没有明确状态语义，保持中性底色，避免整屏都在发光。
    static func isStatusTinted(_ status: AgentStatus) -> Bool {
        switch status {
        case .starting, .working, .waitingUser, .completed, .failed:
            return true
        case .idle, .unknown:
            return false
        }
    }

    /// 只有被标记为「重要」的行才持续脉冲，且复用既有「高级动画」开关，
    /// 避免每行一个常驻动画把主线程占满。
    static func shouldPulse(status: AgentStatus, isImportant: Bool, advancedAnimations: Bool) -> Bool {
        isImportant && advancedAnimations && isStatusTinted(status)
    }
}

enum SessionCompletionAttention: Equatable {
    case none
    case working
    case unreadStarred
    case readStarred
    case unreadOrdinary
    case readOrdinary

    var pulsesBackground: Bool {
        self == .unreadStarred
    }

    var hasUnreadCompletion: Bool {
        self == .unreadStarred || self == .unreadOrdinary
    }

    var pulsesBorder: Bool {
        switch self {
        case .unreadStarred, .readStarred, .unreadOrdinary:
            return true
        case .none, .working, .readOrdinary:
            return false
        }
    }

    var hasMarquee: Bool {
        self == .working
    }
}

enum SessionCompletionAttentionPolicy {
    static func state(
        status: AgentStatus,
        isImportant: Bool,
        hasUnreadCompletion: Bool
    ) -> SessionCompletionAttention {
        if status.isRunning {
            return isImportant ? .working : .none
        }
        guard status == .completed, isImportant || hasUnreadCompletion else {
            return .none
        }
        switch (isImportant, hasUnreadCompletion) {
        case (true, true):
            return .unreadStarred
        case (true, false):
            return .readStarred
        case (false, true):
            return .unreadOrdinary
        case (false, false):
            return .readOrdinary
        }
    }

    static func shouldHighlightProvider(
        isImportant: Bool,
        hasUnreadCompletion: Bool,
        isSelected: Bool
    ) -> Bool {
        isImportant && hasUnreadCompletion && !isSelected
    }
}

enum ExpandedPanelSize {
    static let defaultWidth = 520.0
    static let defaultHeight = 820.0
    static let minimumWidth = 360.0
    static let minimumHeight = 480.0
    static let maximumWidth = 720.0
    static let maximumHeight = 1000.0

    static func clampedWidth(_ value: Double) -> Double {
        clamp(value, minimum: minimumWidth, maximum: maximumWidth, fallback: defaultWidth)
    }

    static func clampedHeight(_ value: Double) -> Double {
        clamp(value, minimum: minimumHeight, maximum: maximumHeight, fallback: defaultHeight)
    }

    private static func clamp(
        _ value: Double,
        minimum: Double,
        maximum: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else {
            return fallback
        }
        return min(max(value, minimum), maximum)
    }
}

enum HUDVisualTheme: String, CaseIterable, Identifiable {
    case classic
    case starlight
    case morningMist
    case celadon
    case neon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic:
            return "原生"
        case .starlight:
            return "星光"
        case .morningMist:
            return "晨雾"
        case .celadon:
            return "青瓷"
        case .neon:
            return "霓虹"
        }
    }

    var appearance: String? {
        switch self {
        case .classic:
            return nil
        case .starlight, .neon:
            return "dark"
        case .morningMist, .celadon:
            return "light"
        }
    }
}

enum HUDPanelAppearance {
    static let defaultOpacity = 0.88
    static let minimumOpacity = 0.55
    static let maximumOpacity = 1.0

    static let defaultContrast = 1.0
    static let minimumContrast = 0.85
    static let maximumContrast = 1.35

    static func clampedOpacity(_ value: Double) -> Double {
        clamp(value, minimum: minimumOpacity, maximum: maximumOpacity, fallback: defaultOpacity)
    }

    static func clampedContrast(_ value: Double) -> Double {
        clamp(value, minimum: minimumContrast, maximum: maximumContrast, fallback: defaultContrast)
    }

    private static func clamp(
        _ value: Double,
        minimum: Double,
        maximum: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else {
            return fallback
        }
        return min(max(value, minimum), maximum)
    }
}

struct ImportantCompletionNotice: Identifiable {
    let sessionID: String
    let provider: AgentProvider
    let title: String
    let projectName: String

    var id: String {
        sessionID
    }
}

enum ImportantCompletionNoticePolicy {
    static func shouldPresent(
        previousStatus: AgentStatus,
        currentStatus: AgentStatus,
        isImportant: Bool,
        isVisible: Bool
    ) -> Bool {
        isImportant
            && previousStatus.isRunning
            && currentStatus == .completed
            && !isVisible
    }
}

struct DashboardSnapshot {
    let sessions: [AgentSession]
    let scannedAt: Date

    static let empty = DashboardSnapshot(sessions: [], scannedAt: .now)
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all
    case working
    case waiting
    case completed
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .working:
            return "工作"
        case .waiting:
            return "等待"
        case .completed:
            return "完成"
        case .failed:
            return "错误"
        }
    }

    func matches(_ status: AgentStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .working:
            return status == .working || status == .starting
        case .waiting:
            return status == .waitingUser
        case .completed:
            return status == .completed
        case .failed:
            return status == .failed
        }
    }
}

enum ProviderFilter: String, CaseIterable, Identifiable {
    case all
    case codex
    case claude
    case pi
    case opencode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .pi:
            return "Pi"
        case .opencode:
            return "OpenCode"
        }
    }

    var provider: AgentProvider? {
        switch self {
        case .all:
            return nil
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .pi:
            return .pi
        case .opencode:
            return .opencode
        }
    }

    func matches(_ provider: AgentProvider) -> Bool {
        self.provider == nil || self.provider == provider
    }
}
