import AppKit
import Foundation

@MainActor
final class HUDViewModel: ObservableObject, LinkSnapshotProviding {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastScannedAt: Date?
    @Published var isExpanded: Bool {
        didSet {
            UserDefaults.standard.set(isExpanded, forKey: "hud.isExpanded")
        }
    }
    @Published var selectedSessionID: String?
    @Published var privacyMode: Bool {
        didSet {
            UserDefaults.standard.set(privacyMode, forKey: "hud.privacyMode")
        }
    }
    @Published var positionLocked: Bool {
        didSet {
            UserDefaults.standard.set(positionLocked, forKey: "hud.positionLocked")
        }
    }
    @Published var expandedWidth: Double {
        didSet {
            let clamped = ExpandedPanelSize.clampedWidth(expandedWidth)
            if expandedWidth != clamped {
                expandedWidth = clamped
            } else {
                UserDefaults.standard.set(clamped, forKey: "hud.expandedWidth")
            }
        }
    }
    @Published var expandedHeight: Double {
        didSet {
            let clamped = ExpandedPanelSize.clampedHeight(expandedHeight)
            if expandedHeight != clamped {
                expandedHeight = clamped
            } else {
                UserDefaults.standard.set(clamped, forKey: "hud.expandedHeight")
            }
        }
    }
    @Published var panelOpacity: Double {
        didSet {
            let clamped = HUDPanelAppearance.clampedOpacity(panelOpacity)
            if panelOpacity != clamped {
                panelOpacity = clamped
            } else {
                UserDefaults.standard.set(clamped, forKey: "hud.panelOpacity")
            }
        }
    }
    @Published var panelContrast: Double {
        didSet {
            let clamped = HUDPanelAppearance.clampedContrast(panelContrast)
            if panelContrast != clamped {
                panelContrast = clamped
            } else {
                UserDefaults.standard.set(clamped, forKey: "hud.panelContrast")
            }
        }
    }
    @Published var visualTheme: HUDVisualTheme {
        didSet {
            UserDefaults.standard.set(visualTheme.rawValue, forKey: "hud.visualTheme")
        }
    }
    @Published var advancedAnimations: Bool {
        didSet {
            UserDefaults.standard.set(advancedAnimations, forKey: "hud.advancedAnimations")
        }
    }
    @Published var statusFilter: StatusFilter = .all {
        didSet {
            UserDefaults.standard.set(statusFilter.rawValue, forKey: "hud.statusFilter")
            if statusFilter != .all {
                resetCompletionTransitions()
            }
            dismissImportantCompletionNoticeIfNowVisible()
        }
    }
    @Published var providerFilter: ProviderFilter = .all {
        didSet {
            UserDefaults.standard.set(providerFilter.rawValue, forKey: "hud.providerFilter")
            dismissImportantCompletionNoticeIfNowVisible()
        }
    }
    @Published var sessionListLimit: SessionListLimit = .default {
        didSet {
            UserDefaults.standard.set(sessionListLimit.rawValue, forKey: "hud.sessionListLimit")
            dismissImportantCompletionNoticeIfNowVisible()
        }
    }
    @Published private(set) var titleOverrides: [String: String] = [:]
    @Published private(set) var aiTitles: [String: String] = [:]
    @Published private(set) var importantSessionIDs: Set<String> = []
    @Published private(set) var importantSessionOrder: [String] = []
    @Published private(set) var unreadCompletionIDs: Set<String> = []
    @Published private(set) var completionAttentionSessions: [String: AgentSession] = [:]
    @Published private(set) var importantNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(importantNotificationsEnabled, forKey: "hud.notifications.important")
        }
    }
    @Published private(set) var ordinaryNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(ordinaryNotificationsEnabled, forKey: "hud.notifications.ordinary")
        }
    }
    /// 当前扫描结果里仍处于「已删除」状态的会话。
    ///
    /// 只存已经算好的结果，不在每次渲染时逐条查 store：`records` 里的活动时间
    /// 比较要在刷新时统一做一次，否则同一个会话可能在列表和计数里得到不同结论。
    @Published private(set) var dismissedSessionIDs: Set<String> = []
    @Published var editingTitleSessionID: String?
    @Published var titleDraft = ""
    @Published private(set) var hoveredSessionID: String?
    @Published private(set) var draggedImportantSessionID: String?
    @Published private(set) var dragTargetSessionID: String?
    @Published private(set) var expandedUserPromptSessionID: String?
    @Published private(set) var suppressedRowOpenSessionID: String?
    @Published private(set) var departingCompletionSessionIDs: Set<String> = []
    @Published private(set) var arrivingCompletionSessionIDs: Set<String> = []
    @Published private(set) var revealedArrivalSessionIDs: Set<String> = []
    @Published private(set) var importantCompletionNotice: ImportantCompletionNotice?

    var onHide: (() -> Void)?
    var onOpenAISettings: (() -> Void)?
    var onSessionCompleted: ((AgentSession, Bool) -> Void)?
    var onNotificationAuthorizationRequested: (() -> Void)?

    private let scanner = SessionScanner()
    private let titleStore = SessionTitleStore()
    private let importanceStore = SessionImportanceStore()
    private let dismissalStore = SessionDismissalStore()
    private let secretStore = KeychainAISecretStore()
    private let aiTitleService = AITitleService()
    private let inputDispatcher = AgentInputDispatcher(
        registry: AgentRuntimeRegistry(),
        deliveryStore: DeliveryStore(),
        adapters: [CodexInputAdapter(), ClaudeInputAdapter()]
    )
    private var refreshLoop: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pendingEventRefresh = false
    private var activityWatcher: SessionActivityWatcher?
    private var aiRefreshTask: Task<Void, Never>?
    private var aiTitleKeys: [String: String] = [:]
    private var isRefreshing = false
    private var monitoringRevision = 0
    private var stableSessionOrder: [String] = [] {
        didSet {
            guard stableSessionOrder != oldValue else { return }
            // Retain only known identities, not constantly changing timestamps.
            UserDefaults.standard.set(Array(stableSessionOrder.suffix(500)), forKey: "hud.stableSessionOrder.v1")
        }
    }
    private var departingSessions: [String: AgentSession] = [:]
    private var completionTransitionTasks: [String: Task<Void, Never>] = [:]

    init() {
        isExpanded = UserDefaults.standard.object(forKey: "hud.isExpanded") as? Bool ?? false
        privacyMode = UserDefaults.standard.bool(forKey: "hud.privacyMode")
        positionLocked = UserDefaults.standard.object(forKey: "hud.positionLocked") as? Bool ?? false
        let storedWidth = UserDefaults.standard.object(forKey: "hud.expandedWidth") as? Double
        let storedHeight = UserDefaults.standard.object(forKey: "hud.expandedHeight") as? Double
        let usesLegacyDefaultSize = UserDefaults.standard.object(forKey: "hud.appearanceRevision") == nil
            && (storedWidth == nil || storedWidth == 424)
            && (storedHeight == nil || storedHeight == 620)
        expandedWidth = ExpandedPanelSize.clampedWidth(
            usesLegacyDefaultSize
                ? ExpandedPanelSize.defaultWidth
                : (storedWidth ?? ExpandedPanelSize.defaultWidth)
        )
        expandedHeight = ExpandedPanelSize.clampedHeight(
            usesLegacyDefaultSize
                ? ExpandedPanelSize.defaultHeight
                : (storedHeight ?? ExpandedPanelSize.defaultHeight)
        )
        if usesLegacyDefaultSize {
            UserDefaults.standard.set(ExpandedPanelSize.defaultWidth, forKey: "hud.expandedWidth")
            UserDefaults.standard.set(ExpandedPanelSize.defaultHeight, forKey: "hud.expandedHeight")
        }
        UserDefaults.standard.set(2, forKey: "hud.appearanceRevision")
        panelOpacity = HUDPanelAppearance.clampedOpacity(
            UserDefaults.standard.object(forKey: "hud.panelOpacity") as? Double
                ?? HUDPanelAppearance.defaultOpacity
        )
        panelContrast = HUDPanelAppearance.clampedContrast(
            UserDefaults.standard.object(forKey: "hud.panelContrast") as? Double
                ?? HUDPanelAppearance.defaultContrast
        )
        visualTheme = HUDVisualTheme(
            rawValue: UserDefaults.standard.string(forKey: "hud.visualTheme") ?? ""
        ) ?? .classic
        advancedAnimations = UserDefaults.standard.bool(forKey: "hud.advancedAnimations")
        statusFilter = StatusFilter(
            rawValue: UserDefaults.standard.string(forKey: "hud.statusFilter") ?? ""
        ) ?? .all
        providerFilter = ProviderFilter(
            rawValue: UserDefaults.standard.string(forKey: "hud.providerFilter") ?? ""
        ) ?? .all
        sessionListLimit = SessionListLimit(
            rawValue: UserDefaults.standard.object(forKey: "hud.sessionListLimit") as? Int
                ?? SessionListLimit.default.rawValue
        ) ?? .default
        titleOverrides = titleStore.titles
        importantSessionIDs = importanceStore.sessionIDs
        importantSessionOrder = importanceStore.orderedSessionIDs
        stableSessionOrder = UserDefaults.standard.stringArray(forKey: "hud.stableSessionOrder.v1") ?? []
        importantNotificationsEnabled = UserDefaults.standard.bool(forKey: "hud.notifications.important")
        ordinaryNotificationsEnabled = UserDefaults.standard.bool(forKey: "hud.notifications.ordinary")
    }

    deinit {
        refreshLoop?.cancel()
        aiRefreshTask?.cancel()
        completionTransitionTasks.values.forEach { $0.cancel() }
    }

    var selectedSession: AgentSession? {
        guard let selectedSessionID else {
            return nil
        }
        return sessions.first { $0.id == selectedSessionID }
    }

    var visibleSessions: [AgentSession] {
        SessionListPolicy.visible(
            filteredSessions,
            limit: sessionListLimit,
            importantSessionIDs: importantSessionIDs,
            importantSessionOrder: importantSessionOrder
        )
    }

    var filteredSessions: [AgentSession] {
        displayableSessions.filter {
            statusFilter.matches($0.status) && providerFilter.matches($0.provider)
        }
    }

    var visibleSessionSummary: String {
        let visible = visibleSessions.count
        let matching = filteredSessions.count
        return visible == matching
            ? "显示 \(visible) 个会话"
            : "显示 \(visible) / \(matching) 个会话"
    }

    /// 从列表、计数和折叠态文案里统一使用的会话集合。
    ///
    /// 被删除且尚未出现新活动的会话只影响「显示」，`sessions` 本身保留完整扫描结果：
    /// 删除不会改动任何本地日志，恢复时也不需要重新扫描。
    var displayableSessions: [AgentSession] {
        guard !dismissedSessionIDs.isEmpty else {
            return sessions
        }
        return sessions.filter { !dismissedSessionIDs.contains($0.id) }
    }

    var visibleSessionRows: [SessionRowPresentation] {
        let currentRows = visibleSessions.filter {
            !departingCompletionSessionIDs.contains($0.id)
        }
        let visibleIDs = Set(visibleSessions.map(\.id))
        let departingRows = departingSessions.values.filter {
            visibleIDs.contains($0.id)
        }
        let ordered = SessionOrdering.sorted(
            currentRows + departingRows,
            importantSessionIDs: importantSessionIDs,
            importantSessionOrder: importantSessionOrder,
            stableSessionOrder: stableSessionOrder
        )

        return ordered.map { session in
            let phase: SessionRowPresentation.Phase
            if departingCompletionSessionIDs.contains(session.id) {
                phase = .departing
            } else if arrivingCompletionSessionIDs.contains(session.id) {
                phase = .arriving
            } else {
                phase = .standard
            }
            return SessionRowPresentation(
                session: session,
                phase: phase,
                arrivalVisible: revealedArrivalSessionIDs.contains(session.id)
            )
        }
    }

    var shouldShowImportantCompletionNotice: Bool {
        guard let importantCompletionNotice else {
            return false
        }
        return !statusFilter.matches(.completed)
            || !providerFilter.matches(importantCompletionNotice.provider)
    }

    func statusCount(_ filter: StatusFilter) -> Int {
        displayableSessions.filter {
            providerFilter.matches($0.provider) && filter.matches($0.status)
        }.count
    }

    func providerCount(_ filter: ProviderFilter) -> Int {
        displayableSessions.filter {
            statusFilter.matches($0.status) && filter.matches($0.provider)
        }.count
    }

    var workingCount: Int {
        displayableSessions.filter { $0.status == .working || $0.status == .starting }.count
    }

    var waitingCount: Int {
        displayableSessions.filter { $0.status == .waitingUser }.count
    }

    var completedCount: Int {
        displayableSessions.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        displayableSessions.filter { $0.status == .failed }.count
    }

    var activeCount: Int {
        displayableSessions.filter { $0.status.isActive }.count
    }

    /// 已被用户删除、当前扫描结果里仍然存在的会话。用于底部的恢复入口。
    var dismissedSessions: [AgentSession] {
        guard !dismissedSessionIDs.isEmpty else {
            return []
        }
        return sessions
            .filter { dismissedSessionIDs.contains($0.id) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var compactStatusText: String {
        if displayableSessions.isEmpty {
            if !dismissedSessionIDs.isEmpty {
                return "已删除 \(dismissedSessionIDs.count) 条，等待新动态"
            }
            return isLoading ? "正在读取本地会话" : "等待本地 Agent"
        }
        if let active = displayableSessions.first(where: { $0.status.isActive }) {
            return displayTitle(for: active)
        }
        if let recent = displayableSessions.first {
            return recent.lastRun?.objective ?? displayTitle(for: recent)
        }
        return "暂无会话"
    }

    func displayTitle(for session: AgentSession) -> String {
        resolvedTitle(for: session).value
    }

    func refreshMonitoringSnapshot() async {
        await refresh(waitForCurrent: true)
    }

    func monitoringSnapshot() async -> LinkMonitoringSnapshot {
        let privacy = privacyMode
        let current = sessions.map { session in
            let git = privacy ? nil : session.git
            let runs = privacy ? [] : session.runs.map { run in
                LinkTaskRun(
                    id: run.id,
                    objective: run.objective,
                    summary: run.summary,
                    actions: run.actions,
                    filesChanged: run.filesChanged,
                    completedAt: run.completedAt,
                    status: run.status.protocolValue
                )
            }
            let prompt: LinkPromptSnapshot?
            if privacy {
                prompt = nil
            } else if let latest = session.latestUserPrompt {
                let images = latest.images.enumerated().prefix(12).map { index, image in
                    let label = image.label?.isEmpty == false
                        ? image.label!
                        : SessionImageAttachment.displayLabel(for: index)
                    return LinkPromptImage(index: index, label: label)
                }
                prompt = LinkPromptSnapshot(
                    text: String(latest.text.prefix(8_000)),
                    sentAt: latest.sentAt,
                    images: images
                )
            } else {
                prompt = nil
            }
            let capability = privacy
                ? LinkConversationCapability(enabled: false, state: AgentInputState.offline.rawValue, reason: "隐私模式已开启")
                : Self.capabilitySnapshot(inputDispatcher.capability(for: session))
            return LinkMonitoringSession(
                id: session.id,
                provider: session.provider.rawValue.capitalized,
                status: session.status.protocolValue,
                confidence: session.confidence.rawValue.capitalized,
                title: privacy ? "隐私模式已开启" : displayTitle(for: session),
                projectName: privacy ? "已隐藏" : session.projectName,
                currentAction: privacy ? "隐私模式已开启" : session.currentAction,
                currentFiles: privacy ? [] : session.currentFiles,
                startedAt: session.startedAt,
                lastActivityAt: session.lastActivityAt,
                completedAt: session.completedAt,
                isLive: session.isLive,
                gitBranch: git?.branch,
                gitChangedFiles: git?.changedFiles,
                gitInsertions: git?.insertions,
                gitDeletions: git?.deletions,
                summary: privacy ? nil : session.lastRun?.summary,
                isImportant: isImportant(session),
                titleSource: Self.protocolTitleSource(titleSource(for: session)),
                hasCustomTitle: hasCustomTitle(for: session),
                latestPrompt: prompt,
                runs: runs,
                conversation: capability
            )
        }
        return LinkMonitoringSnapshot(
            revision: monitoringRevision,
            scannedAt: lastScannedAt,
            privacyMode: privacy,
            sessions: current
        )
    }

    func setSessionTitle(sessionID: String, title: String?) async -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return false
        }
        let normalized = title?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            clearCustomTitle(for: session)
        } else {
            setCustomTitle(normalized, for: session)
        }
        monitoringRevision += 1
        return true
    }

    func setSessionImportant(sessionID: String, important: Bool) async -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return false
        }
        if isImportant(session) != important {
            toggleImportance(for: session)
        } else {
            importantSessionOrder = importanceStore.orderedSessionIDs
        }
        monitoringRevision += 1
        return true
    }

    func sendMessage(sessionID: String, clientMessageId: String, text: String) async -> (deliveryId: String, status: AgentDeliveryStatus, error: AgentDeliveryError?) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return ("", .failed, .sessionOffline)
        }
        return inputDispatcher.dispatch(
            clientMessageId: clientMessageId,
            text: text,
            to: session,
            publicSessionId: sessionID
        )
    }

    func deliveryStatus(deliveryId: String) -> (status: AgentDeliveryStatus, error: AgentDeliveryError?)? {
        inputDispatcher.status(deliveryId: deliveryId)
    }

    func promptImage(sessionID: String, index: Int) async -> LinkPromptImagePayload? {
        guard !privacyMode,
              let session = sessions.first(where: { $0.id == sessionID }),
              let prompt = session.latestUserPrompt,
              prompt.images.indices.contains(index) else {
            return nil
        }
        let image = prompt.images[index]
        switch image.source {
        case .unavailable:
            return nil
        case .localPath(let path):
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  data.count <= 12_000_000 else {
                return nil
            }
            return LinkPromptImagePayload(
                data: data,
                contentType: Self.imageContentType(for: path)
            )
        case .dataURL(let value):
            guard let comma = value.firstIndex(of: ",") else { return nil }
            let header = String(value[..<comma])
            let encoded = String(value[value.index(after: comma)...])
            guard let data = Data(base64Encoded: encoded),
                  data.count <= 12_000_000 else {
                return nil
            }
            let contentType = header
                .replacingOccurrences(of: "data:", with: "")
                .split(separator: ";")
                .first
                .map(String.init) ?? "image/png"
            return LinkPromptImagePayload(data: data, contentType: contentType)
        }
    }

    private static func capabilitySnapshot(_ capability: AgentInputCapability) -> LinkConversationCapability {
        LinkConversationCapability(
            enabled: capability.enabled,
            state: capability.state.rawValue,
            reason: capability.reason
        )
    }

    private static func protocolTitleSource(_ source: TaskTitleSource) -> String {
        switch source {
        case .automatic:
            return "Automatic"
        case .ai:
            return "AI"
        case .user:
            return "User"
        }
    }

    private static func imageContentType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        default:
            return "application/octet-stream"
        }
    }

    func titleSource(for session: AgentSession) -> TaskTitleSource {
        resolvedTitle(for: session).source
    }

    func hasCustomTitle(for session: AgentSession) -> Bool {
        titleOverrides[session.id] != nil
    }

    func beginTitleEditing(for session: AgentSession) {
        titleDraft = displayTitle(for: session)
        editingTitleSessionID = session.id
    }

    func saveTitleEditing(for session: AgentSession) {
        setCustomTitle(titleDraft, for: session)
        editingTitleSessionID = nil
        titleDraft = ""
    }

    func cancelTitleEditing() {
        editingTitleSessionID = nil
        titleDraft = ""
    }

    func setCustomTitle(_ value: String, for session: AgentSession) {
        titleStore.setCustomTitle(value, for: session.id)
        titleOverrides = titleStore.titles
    }

    func clearCustomTitle(for session: AgentSession) {
        titleStore.removeCustomTitle(for: session.id)
        titleOverrides = titleStore.titles
    }

    func isImportant(_ session: AgentSession) -> Bool {
        importantSessionIDs.contains(session.id)
    }

    /// 从列表删除一条会话。
    ///
    /// 删除记的是「当前最后活动时间」而不是删除时刻：会话之后只要产生任何新活动，
    /// 下一次刷新就会自动回到列表，用户不需要手动恢复。
    func dismiss(_ session: AgentSession) {
        dismissalStore.dismiss(sessionID: session.id, lastActivityAt: session.lastActivityAt)
        dismissedSessionIDs = Self.dismissedIDs(from: dismissalStore, in: sessions)
        if selectedSessionID == session.id {
            cancelTitleEditing()
            selectedSessionID = nil
        }
        if editingTitleSessionID == session.id {
            cancelTitleEditing()
        }
        departingSessions.removeValue(forKey: session.id)
        departingCompletionSessionIDs.remove(session.id)
        arrivingCompletionSessionIDs.remove(session.id)
        revealedArrivalSessionIDs.remove(session.id)
    }

    func restoreAllDismissed() {
        dismissalStore.restoreAll()
        dismissedSessionIDs = []
    }

    private static func dismissedIDs(
        from store: SessionDismissalStore,
        in sessions: [AgentSession]
    ) -> Set<String> {
        store.dismissedIDs(in: sessions)
    }

    func toggleImportance(for session: AgentSession) {
        let isImportant = importanceStore.toggle(session.id)
        importantSessionIDs = importanceStore.sessionIDs
        importantSessionOrder = importanceStore.orderedSessionIDs
        if isImportant, unreadCompletionIDs.contains(session.id),
           let current = sessions.first(where: { $0.id == session.id }) {
            completionAttentionSessions[session.id] = current
        } else if !isImportant {
            completionAttentionSessions.removeValue(forKey: session.id)
        }
        monitoringRevision += 1
    }

    func moveImportantSession(_ sessionID: String, before targetID: String) {
        guard importanceStore.move(sessionID: sessionID, before: targetID) else {
            return
        }
        importantSessionIDs = importanceStore.sessionIDs
        importantSessionOrder = importanceStore.orderedSessionIDs
        monitoringRevision += 1
    }

    func suppressNextRowOpenByID(_ sessionID: String) {
        suppressedRowOpenSessionID = sessionID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard self?.suppressedRowOpenSessionID == sessionID else { return }
            self?.suppressedRowOpenSessionID = nil
        }
    }

    func beginImportantDrag(_ sessionID: String) {
        guard importantSessionIDs.contains(sessionID) else { return }
        draggedImportantSessionID = sessionID
        dragTargetSessionID = nil
    }

    func updateImportantDrag(targetID: String) {
        guard let draggedImportantSessionID, importantSessionIDs.contains(targetID) else { return }
        dragTargetSessionID = targetID
        moveImportantSession(draggedImportantSessionID, before: targetID)
    }

    func endImportantDrag() {
        draggedImportantSessionID = nil
        dragTargetSessionID = nil
    }

    func hasUnreadCompletion(_ session: AgentSession) -> Bool {
        unreadCompletionIDs.contains(session.id)
    }

    func completionAttention(for session: AgentSession) -> SessionCompletionAttention {
        SessionCompletionAttentionPolicy.state(
            status: session.status,
            isImportant: isImportant(session),
            hasUnreadCompletion: hasUnreadCompletion(session)
        )
    }

    func providerAttention(_ filter: ProviderFilter) -> AgentSession? {
        guard let provider = filter.provider, providerFilter != filter, selectedSessionID == nil else {
            return nil
        }
        return completionAttentionSessions.values
            .filter {
                $0.provider == provider
                    && SessionCompletionAttentionPolicy.shouldHighlightProvider(
                        isImportant: importantSessionIDs.contains($0.id),
                        hasUnreadCompletion: unreadCompletionIDs.contains($0.id),
                        isSelected: false
                    )
            }
            .max { ($0.completedAt ?? $0.lastActivityAt) < ($1.completedAt ?? $1.lastActivityAt) }
    }

    func selectProviderFilter(_ filter: ProviderFilter) {
        providerFilter = filter
    }

    func completionSummary(for session: AgentSession) -> String {
        if let summary = session.lastRun?.summary, !summary.isEmpty {
            return TextTools.sentence(summary, limit: 180)
        }
        return session.currentAction.isEmpty ? "任务已完成，点击查看详情。" : TextTools.sentence(session.currentAction, limit: 180)
    }

    func setImportantNotificationsEnabled(_ enabled: Bool) {
        importantNotificationsEnabled = enabled
        if enabled { onNotificationAuthorizationRequested?() }
    }

    func setOrdinaryNotificationsEnabled(_ enabled: Bool) {
        ordinaryNotificationsEnabled = enabled
        if enabled { onNotificationAuthorizationRequested?() }
    }

    func resetAppearanceToDefaults() {
        expandedWidth = ExpandedPanelSize.defaultWidth
        expandedHeight = ExpandedPanelSize.defaultHeight
        panelOpacity = HUDPanelAppearance.defaultOpacity
        panelContrast = HUDPanelAppearance.defaultContrast
        visualTheme = .classic
        advancedAnimations = false
        sessionListLimit = .default
    }

    func start() {
        guard refreshLoop == nil else {
            return
        }
        let watcher = SessionActivityWatcher()
        watcher.onChange = { [weak self] in
            self?.handleActivityEvent()
        }
        watcher.start()
        activityWatcher = watcher

        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func handleActivityEvent() {
        guard refreshTask == nil, !isRefreshing else {
            pendingEventRefresh = true
            return
        }
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
        refreshTask?.cancel()
        refreshTask = nil
        activityWatcher?.stop()
        activityWatcher = nil
    }

    func refresh(waitForCurrent: Bool = false) async {
        if let refreshTask {
            if waitForCurrent {
                await refreshTask.value
            }
            return
        }
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        await task.value
    }

    private func performRefresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        if sessions.isEmpty {
            isLoading = true
        }

        let scanner = self.scanner
        if draggedImportantSessionID == nil {
            importanceStore.reload()
            importantSessionIDs = importanceStore.sessionIDs
            importantSessionOrder = importanceStore.orderedSessionIDs
        }
        let snapshot = await Task.detached(priority: .utility) {
            scanner.scan()
        }.value

        let previousSessions = sessions
        let stableOrder = Self.stableOrder(
            previous: previousSessions,
            current: snapshot.sessions,
            existing: stableSessionOrder
        )
        stableSessionOrder = stableOrder
        let stablyOrderedSnapshot = SessionOrdering.sorted(
            snapshot.sessions,
            importantSessionIDs: importantSessionIDs,
            importantSessionOrder: importantSessionOrder,
            stableSessionOrder: stableSessionOrder
        )
        let runningCompletionIDs = SessionTransitionDetector.runningCompletionIDs(
            previousSessions: previousSessions,
            currentSessions: snapshot.sessions
        )
        let currentByID = Dictionary(
            snapshot.sessions.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        unreadCompletionIDs.formIntersection(currentByID.keys)
        for session in snapshot.sessions {
            if session.status.isRunning {
                unreadCompletionIDs.remove(session.id)
                completionAttentionSessions.removeValue(forKey: session.id)
            }
        }
        for sessionID in runningCompletionIDs {
            guard let session = currentByID[sessionID] else { continue }
            unreadCompletionIDs.insert(sessionID)
            if importantSessionIDs.contains(sessionID) {
                completionAttentionSessions[sessionID] = session
            }
        }
        let newCompletionSessions = runningCompletionIDs.compactMap { currentByID[$0] }
        // 先结算删除状态，再决定动画和提醒：被删除且还没新活动的会话不该
        // 触发行滑出动画，也不该弹出「重要会话已完成」的提示。
        dismissalStore.clearAwakened(in: snapshot.sessions)
        let nextDismissedIDs = Self.dismissedIDs(from: dismissalStore, in: snapshot.sessions)
        for session in newCompletionSessions where !nextDismissedIDs.contains(session.id) {
            let important = importantSessionIDs.contains(session.id)
            let setting = SessionNotificationSettings(
                importantEnabled: importantNotificationsEnabled,
                ordinaryEnabled: ordinaryNotificationsEnabled
            )
            if setting.shouldNotify(isImportant: important) {
                onSessionCompleted?(session, important)
            }
        }
        // Keep first-seen identity order across refreshes. Timestamp changes still
        // update every field and timestamp, but never move equal-status rows.
        let animatedCompletionIDs = statusFilter == .all
            ? Set(runningCompletionIDs.filter { sessionID in
                guard let session = currentByID[sessionID],
                      !nextDismissedIDs.contains(sessionID) else {
                    return false
                }
                return providerFilter.matches(session.provider)
            })
            : []
        if !animatedCompletionIDs.isEmpty {
            beginCompletionTransitions(
                for: animatedCompletionIDs,
                previousSessions: previousSessions
            )
        }

        sessions = stablyOrderedSnapshot
        dismissedSessionIDs = nextDismissedIDs
        monitoringRevision += 1
        presentImportantCompletionNoticeIfNeeded(
            completionIDs: runningCompletionIDs,
            previousSessions: previousSessions,
            currentSessions: snapshot.sessions
        )
        lastScannedAt = snapshot.scannedAt
        isLoading = false
        isRefreshing = false

        if let selectedSessionID,
           !sessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = nil
        }
        if let editingTitleSessionID,
           !sessions.contains(where: { $0.id == editingTitleSessionID }) {
            cancelTitleEditing()
        }

        startAITitleEnrichment(for: displayableSessions)
        if pendingEventRefresh {
            pendingEventRefresh = false
            Task { [weak self] in
                await self?.refresh()
            }
        }
    }

    static func stableOrder(
        previous: [AgentSession],
        current: [AgentSession],
        existing: [String]
    ) -> [String] {
        let currentIDs = Set(current.map(\.id))
        let previousIDs = Set(previous.map(\.id))
        var seen = Set<String>()
        let result = (existing + previous.map(\.id)).filter {
            currentIDs.contains($0) && previousIDs.contains($0) && seen.insert($0).inserted
        }
        return result + current.filter { seen.insert($0.id).inserted }.map(\.id)
    }

    func select(_ session: AgentSession) {
        markCompletionSeen(session)
        cancelTitleEditing()
        expandedUserPromptSessionID = nil
        selectedSessionID = session.id
    }

    func showList() {
        cancelTitleEditing()
        expandedUserPromptSessionID = nil
        selectedSessionID = nil
    }

    private func markCompletionSeen(_ session: AgentSession) {
        unreadCompletionIDs.remove(session.id)
        completionAttentionSessions.removeValue(forKey: session.id)
        if importantCompletionNotice?.sessionID == session.id {
            importantCompletionNotice = nil
        }
    }

    func revealImportantCompletionNotice() {
        guard let importantCompletionNotice else {
            return
        }

        self.importantCompletionNotice = nil
        statusFilter = .all
        providerFilter = .all

        if let session = sessions.first(where: { $0.id == importantCompletionNotice.sessionID }) {
            select(session)
        }
    }

    func dismissImportantCompletionNotice() {
        importantCompletionNotice = nil
    }

    func collapse() {
        cancelTitleEditing()
        expandedUserPromptSessionID = nil
        selectedSessionID = nil
        isExpanded = false
    }

    func expand() {
        isExpanded = true
    }

    func hide() {
        onHide?()
    }

    func openAISettings() {
        onOpenAISettings?()
    }

    func reloadAIConfiguration() {
        aiRefreshTask?.cancel()
        aiRefreshTask = nil
        aiTitles = [:]
        aiTitleKeys = [:]
        Task {
            await aiTitleService.clearCache()
            startAITitleEnrichment(for: displayableSessions)
        }
    }

    func togglePrivacy() {
        privacyMode.toggle()
    }

    func togglePositionLock() {
        positionLocked.toggle()
    }

    func setHoveredSession(_ sessionID: String, hovered: Bool) {
        if hovered {
            hoveredSessionID = sessionID
        } else if hoveredSessionID == sessionID {
            hoveredSessionID = nil
        }
    }

    func toggleUserPromptExpansion(for session: AgentSession) {
        expandedUserPromptSessionID = expandedUserPromptSessionID == session.id
            ? nil
            : session.id
    }

    func isUserPromptExpanded(for session: AgentSession) -> Bool {
        expandedUserPromptSessionID == session.id
    }

    func suppressNextRowOpen(for session: AgentSession) {
        suppressedRowOpenSessionID = session.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard self?.suppressedRowOpenSessionID == session.id else {
                return
            }
            self?.suppressedRowOpenSessionID = nil
        }
    }

    func consumeRowOpenSuppression(for session: AgentSession) -> Bool {
        guard suppressedRowOpenSessionID == session.id else {
            return false
        }
        suppressedRowOpenSessionID = nil
        return true
    }

    func openProject(_ session: AgentSession) {
        let url = URL(fileURLWithPath: session.projectPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func presentImportantCompletionNoticeIfNeeded(
        completionIDs: Set<String>,
        previousSessions: [AgentSession],
        currentSessions: [AgentSession]
    ) {
        guard !completionIDs.isEmpty else {
            return
        }

        let previousByID = Dictionary(
            previousSessions.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let candidates = currentSessions
            .filter { completionIDs.contains($0.id) && !dismissedSessionIDs.contains($0.id) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }

        for session in candidates {
            guard let previous = previousByID[session.id] else {
                continue
            }

            let isVisible = statusFilter.matches(session.status)
                && providerFilter.matches(session.provider)
            guard ImportantCompletionNoticePolicy.shouldPresent(
                previousStatus: previous.status,
                currentStatus: session.status,
                isImportant: importantSessionIDs.contains(session.id),
                isVisible: isVisible
            ) else {
                continue
            }

            importantCompletionNotice = ImportantCompletionNotice(
                sessionID: session.id,
                provider: session.provider,
                title: displayTitle(for: session),
                projectName: session.projectName
            )
            return
        }
    }

    private func dismissImportantCompletionNoticeIfNowVisible() {
        guard let importantCompletionNotice,
              statusFilter.matches(.completed),
              providerFilter.matches(importantCompletionNotice.provider) else {
            return
        }
        self.importantCompletionNotice = nil
    }

    private func resolvedTitle(for session: AgentSession) -> ResolvedSessionTitle {
        SessionTitleResolver.resolve(
            manualTitle: titleOverrides[session.id],
            aiTitle: aiTitles[session.id],
            localTitle: session.title
        )
    }

    private func beginCompletionTransitions(
        for sessionIDs: Set<String>,
        previousSessions: [AgentSession]
    ) {
        let previousByID = Dictionary(
            previousSessions.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for sessionID in sessionIDs {
            guard let session = previousByID[sessionID] else {
                continue
            }

            completionTransitionTasks[sessionID]?.cancel()
            arrivingCompletionSessionIDs.remove(sessionID)
            revealedArrivalSessionIDs.remove(sessionID)
            departingSessions[sessionID] = session
            departingCompletionSessionIDs.insert(sessionID)

            completionTransitionTasks[sessionID] = Task { [weak self] in
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(SessionCompletionAnimation.exitLifetime * 1_000_000_000)
                    )
                } catch {
                    return
                }

                guard let self,
                      self.departingCompletionSessionIDs.contains(sessionID) else {
                    return
                }
                guard self.sessions.first(where: { $0.id == sessionID })?.status == .completed else {
                    self.departingSessions.removeValue(forKey: sessionID)
                    self.departingCompletionSessionIDs.remove(sessionID)
                    self.completionTransitionTasks[sessionID] = nil
                    return
                }

                self.departingSessions.removeValue(forKey: sessionID)
                self.departingCompletionSessionIDs.remove(sessionID)
                self.arrivingCompletionSessionIDs.insert(sessionID)

                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(SessionCompletionAnimation.enterDelay * 1_000_000_000)
                    )
                } catch {
                    return
                }

                self.revealedArrivalSessionIDs.insert(sessionID)

                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(
                            (
                                SessionCompletionAnimation.arrivalIdentityDuration
                                    - SessionCompletionAnimation.enterDelay
                            ) * 1_000_000_000
                        )
                    )
                } catch {
                    return
                }

                self.revealedArrivalSessionIDs.remove(sessionID)
                self.arrivingCompletionSessionIDs.remove(sessionID)
                self.completionTransitionTasks[sessionID] = nil
            }
        }
    }

    private static func previousObjective(for session: AgentSession) -> String {
        for run in session.runs.reversed() {
            let objective = TextTools.normalizedWhitespace(run.objective)
            guard !objective.isEmpty,
                  !TextTools.isContinuationPrompt(objective) else {
                continue
            }
            return String(objective.prefix(2_000))
        }
        return ""
    }

    private func resetCompletionTransitions() {
        completionTransitionTasks.values.forEach { $0.cancel() }
        completionTransitionTasks.removeAll()
        departingSessions.removeAll()
        departingCompletionSessionIDs.removeAll()
        arrivingCompletionSessionIDs.removeAll()
        revealedArrivalSessionIDs.removeAll()
    }

    private func startAITitleEnrichment(for sessions: [AgentSession]) {
        guard aiRefreshTask == nil else {
            return
        }

        let configuration = AIConfiguration.load()
        guard configuration.isUsable,
              let apiKey = secretStore.apiKey(),
              !apiKey.isEmpty else {
            aiTitles = [:]
            aiTitleKeys = [:]
            return
        }

        let requests = sessions.compactMap { session -> AITitleRequest? in
            guard titleOverrides[session.id] == nil,
                  let prompt = session.latestUserPrompt else {
                return nil
            }

            let meaningfulText = TextTools.meaningfulPrompt(prompt.text)
            let hasImages = !prompt.images.isEmpty
            guard meaningfulText != nil || hasImages else {
                return nil
            }

            // 首轮只用本次输入；本轮是“确认/继续”但取不到上一轮目标时跳过，避免臆造标题。
            guard let previousPrompt = AITitleEligibility.previousPrompt(
                currentPrompt: meaningfulText,
                hasImages: hasImages,
                latestObjective: Self.previousObjective(for: session)
            ) else {
                return nil
            }
            return AITitleRequest(
                sessionID: session.id,
                prompt: meaningfulText ?? "",
                projectName: session.projectName,
                images: prompt.images,
                previousPrompt: previousPrompt,
                supportsVision: configuration.supportsVision
            )
        }

        guard !requests.isEmpty else {
            return
        }

        aiRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            for request in requests {
                if Task.isCancelled {
                    break
                }

                if self.aiTitleKeys[request.sessionID] != request.rawFingerprint {
                    self.aiTitles.removeValue(forKey: request.sessionID)
                }

                do {
                    let title = try await self.aiTitleService.title(
                        for: request,
                        configuration: configuration,
                        apiKey: apiKey
                    )
                    guard !Task.isCancelled else {
                        break
                    }
                    self.aiTitles[request.sessionID] = title
                    self.aiTitleKeys[request.sessionID] = request.rawFingerprint
                } catch {
                    self.aiTitles[request.sessionID] = TextTools.automaticTaskTitle(
                        rawPrompt: request.prompt.isEmpty ? nil : request.prompt,
                        projectName: request.projectName
                    )
                    self.aiTitleKeys[request.sessionID] = request.rawFingerprint
                }
            }
            self.aiRefreshTask = nil
        }
    }
}
