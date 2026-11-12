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
        case .waitingUser:
            return 0
        case .failed:
            return 1
        case .working:
            return 2
        case .starting:
            return 3
        case .completed:
            return 4
        case .idle:
            return 5
        case .unknown:
            return 6
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

enum SessionOrdering {
    static func sorted(
        _ sessions: [AgentSession],
        importantSessionIDs: Set<String>,
        runningFirst: Bool = false
    ) -> [AgentSession] {
        sessions.sorted { lhs, rhs in
            let lhsIsImportant = importantSessionIDs.contains(lhs.id)
            let rhsIsImportant = importantSessionIDs.contains(rhs.id)
            if lhsIsImportant != rhsIsImportant {
                return lhsIsImportant
            }
            if runningFirst, lhs.status.isRunning != rhs.status.isRunning {
                return lhs.status.isRunning
            }
            if lhs.status.sortRank != rhs.status.sortRank {
                return lhs.status.sortRank < rhs.status.sortRank
            }
            if lhs.lastActivityAt != rhs.lastActivityAt {
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
            return lhs.id < rhs.id
        }
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

enum ExpandedPanelSize {
    static let defaultWidth = 424.0
    static let defaultHeight = 620.0
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
