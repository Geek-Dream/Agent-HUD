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
    @Published private(set) var titleOverrides: [String: String] = [:]
    @Published private(set) var aiTitles: [String: String] = [:]
    @Published private(set) var importantSessionIDs: Set<String> = []
    @Published var editingTitleSessionID: String?
    @Published var titleDraft = ""
    @Published private(set) var hoveredSessionID: String?
    @Published private(set) var expandedUserPromptSessionID: String?
    @Published private(set) var suppressedRowOpenSessionID: String?
    @Published private(set) var departingCompletionSessionIDs: Set<String> = []
    @Published private(set) var arrivingCompletionSessionIDs: Set<String> = []
    @Published private(set) var revealedArrivalSessionIDs: Set<String> = []
    @Published private(set) var importantCompletionNotice: ImportantCompletionNotice?

    var onHide: (() -> Void)?
    var onOpenAISettings: (() -> Void)?

    private let scanner = SessionScanner()
    private let titleStore = SessionTitleStore()
    private let importanceStore = SessionImportanceStore()
    private let secretStore = KeychainAISecretStore()
    private let aiTitleService = AITitleService()
    private var refreshLoop: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var aiRefreshTask: Task<Void, Never>?
    private var aiTitleKeys: [String: String] = [:]
    private var isRefreshing = false
    private var monitoringRevision = 0
    private var departingSessions: [String: AgentSession] = [:]
    private var completionTransitionTasks: [String: Task<Void, Never>] = [:]

    init() {
        isExpanded = UserDefaults.standard.object(forKey: "hud.isExpanded") as? Bool ?? false
        privacyMode = UserDefaults.standard.bool(forKey: "hud.privacyMode")
        positionLocked = UserDefaults.standard.object(forKey: "hud.positionLocked") as? Bool ?? false
        expandedWidth = ExpandedPanelSize.clampedWidth(
            UserDefaults.standard.object(forKey: "hud.expandedWidth") as? Double
                ?? ExpandedPanelSize.defaultWidth
        )
        expandedHeight = ExpandedPanelSize.clampedHeight(
            UserDefaults.standard.object(forKey: "hud.expandedHeight") as? Double
                ?? ExpandedPanelSize.defaultHeight
        )
        statusFilter = StatusFilter(
            rawValue: UserDefaults.standard.string(forKey: "hud.statusFilter") ?? ""
        ) ?? .all
        providerFilter = ProviderFilter(
            rawValue: UserDefaults.standard.string(forKey: "hud.providerFilter") ?? ""
        ) ?? .all
        titleOverrides = titleStore.titles
        importantSessionIDs = importanceStore.sessionIDs
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
        let filtered = sessions.filter {
            statusFilter.matches($0.status) && providerFilter.matches($0.provider)
        }
        return SessionOrdering.sorted(
            filtered,
            importantSessionIDs: importantSessionIDs,
            runningFirst: statusFilter == .all
        )
    }

    var visibleSessionRows: [SessionRowPresentation] {
        let currentRows = visibleSessions.filter {
            !departingCompletionSessionIDs.contains($0.id)
        }
        let departingRows = departingSessions.values.filter {
            statusFilter.matches($0.status) && providerFilter.matches($0.provider)
        }
        let ordered = SessionOrdering.sorted(
            currentRows + departingRows,
            importantSessionIDs: importantSessionIDs,
            runningFirst: statusFilter == .all
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
        sessions.filter {
            providerFilter.matches($0.provider) && filter.matches($0.status)
        }.count
    }

    func providerCount(_ filter: ProviderFilter) -> Int {
        sessions.filter {
            statusFilter.matches($0.status) && filter.matches($0.provider)
        }.count
    }

    var workingCount: Int {
        sessions.filter { $0.status == .working || $0.status == .starting }.count
    }

    var waitingCount: Int {
        sessions.filter { $0.status == .waitingUser }.count
    }

    var completedCount: Int {
        sessions.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        sessions.filter { $0.status == .failed }.count
    }

    var activeCount: Int {
        sessions.filter { $0.status.isActive }.count
    }

    var compactStatusText: String {
        if sessions.isEmpty {
            return isLoading ? "正在读取本地会话" : "等待本地 Agent"
        }
        if let active = sessions.first(where: { $0.status.isActive }) {
            return displayTitle(for: active)
        }
        if let recent = sessions.first {
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
                latestPrompt: prompt
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
        }
        monitoringRevision += 1
        return true
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

    func toggleImportance(for session: AgentSession) {
        importanceStore.toggle(session.id)
        importantSessionIDs = importanceStore.sessionIDs
    }

    func start() {
        guard refreshLoop == nil else {
            return
        }

        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
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
        let snapshot = await Task.detached(priority: .utility) {
            scanner.scan()
        }.value

        let previousSessions = sessions
        let runningCompletionIDs = SessionTransitionDetector.runningCompletionIDs(
            previousSessions: previousSessions,
            currentSessions: snapshot.sessions
        )
        let currentByID = Dictionary(
            snapshot.sessions.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let animatedCompletionIDs = statusFilter == .all
            ? Set(runningCompletionIDs.filter { sessionID in
                guard let session = currentByID[sessionID] else {
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

        sessions = snapshot.sessions
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

        startAITitleEnrichment(for: sessions)
    }

    func select(_ session: AgentSession) {
        cancelTitleEditing()
        expandedUserPromptSessionID = nil
        selectedSessionID = session.id
    }

    func showList() {
        cancelTitleEditing()
        expandedUserPromptSessionID = nil
        selectedSessionID = nil
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
            startAITitleEnrichment(for: sessions)
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
            .filter { completionIDs.contains($0.id) }
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
            if let meaningfulText,
               TextTools.isContinuationPrompt(meaningfulText),
               !hasImages {
                return nil
            }
            return AITitleRequest(
                sessionID: session.id,
                prompt: meaningfulText ?? "",
                projectName: session.projectName,
                images: prompt.images
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
                    self.aiTitleKeys[request.sessionID] = request.rawFingerprint
                }
            }
            self.aiRefreshTask = nil
        }
    }
}
