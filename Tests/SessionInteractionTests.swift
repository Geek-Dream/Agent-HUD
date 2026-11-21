import Foundation

private final class InputTestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    private var directory = ""

    var arguments: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    var workingDirectory: String {
        lock.lock()
        defer { lock.unlock() }
        return directory
    }

    func record(arguments: [String], directory: String = "") {
        lock.lock()
        values = arguments
        self.directory = directory
        lock.unlock()
    }
}

func testSessionListLimitKeepsStarredSessions() throws {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let sessions = (0..<25).map { index in
        makeTestSession(
            id: "codex:session-\(index)",
            status: index % 2 == 0 ? .completed : .working,
            lastActivityAt: base.addingTimeInterval(TimeInterval(index))
        )
    }
    let starred = Set(["codex:session-0", "codex:session-5"])

    let recent = SessionListPolicy.visible(
        sessions,
        limit: .recent10,
        importantSessionIDs: starred
    )
    try expect(recent.count == 12, "Default ten ordinary sessions plus two starred rows expected")
    try expect(starred.isSubset(of: Set(recent.map(\.id))), "Old starred sessions must stay visible")
    try expect(recent.prefix(2).map(\.id) == ["codex:session-0", "codex:session-5"], "Starred rows stay first in explicit order")
    try expect(
        !recent.contains(where: { $0.id == "codex:session-10" }),
        "Ordinary sessions beyond the recent ten should be hidden"
    )

    for (limit, count) in [(SessionListLimit.recent3, 3), (.recent5, 5), (.recent15, 15), (.recent20, 20)] {
        let visible = SessionListPolicy.visible(sessions, limit: limit, importantSessionIDs: [])
        try expect(visible.count == count, "\(limit) should show \(count) sessions")
        try expect(visible.first?.id == "codex:session-24", "Recent limit must use latest activity")
    }
    try expect(
        SessionListPolicy.visible(sessions, limit: .all, importantSessionIDs: starred).count == sessions.count,
        "All must not discard sessions"
    )
    try expect(SessionListLimit.default == .recent10, "Default list limit must be ten")
    try expect(SessionListLimit(rawValue: 0) == .all, "Stored zero must restore all")
    try expect(SessionListLimit(rawValue: 20) == .recent20, "Stored twenty must restore recent20")
    try expect(SessionListLimit(rawValue: 99) == nil, "Unknown stored limits must be rejected")
    try expect(
        SessionListPolicy.visible([], limit: .recent10, importantSessionIDs: []).isEmpty,
        "Empty input must remain empty"
    )
}

@MainActor
func testCompletedCodexCanAcceptInput() async throws {
    let adapter = CodexInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, _, _, _ in
            CommandResult(status: 0, stdout: "Queued message\n", stderr: "")
        }
    )
    let completed = makeTestSession(
        id: "codex:completed-input",
        status: .completed,
        lastActivityAt: Date().addingTimeInterval(-86_400)
    )
    try expect(adapter.canAcceptInput(for: completed).enabled, "Completed Codex sessions must allow resuming")
    let result = await adapter.deliver(text: "继续", to: completed)
    try expect(result.success && result.status == .delivered, "Queue and resume success should be delivered")

    let resumedFailed = CodexInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, _, _, _ in
            CommandResult(status: 0, stdout: "Queued message\n", stderr: "Resume failed (offline)")
        }
    )
    let failed = await resumedFailed.deliver(text: "继续", to: completed)
    try expect(!failed.success && failed.error == .deliveryFailed, "Resume failure must not be reported as delivered")
}

@MainActor
func testCodexQueueArgumentsAndErrors() async throws {
    let recorder = InputTestRecorder()
    let adapter = CodexInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, received, _, _ in
            recorder.record(arguments: received)
            return CommandResult(status: 0, stdout: "Queued message\n", stderr: "")
        }
    )
    let session = makeTestSession(id: "codex:arguments", status: .working, lastActivityAt: Date())
    _ = await adapter.deliver(text: "请继续，不要改标题", to: session)
    try expect(
        recorder.arguments == ["queue", "--thread", "codex:arguments", "--message", "请继续，不要改标题", "--resume"],
        "Both running and completed sessions should use queue --resume"
    )

    let missing = CodexInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, _, _, _ in nil }
    )
    let timeout = await missing.deliver(text: "继续", to: session)
    try expect(!timeout.success && timeout.error == .inputUnavailable, "Missing CLI or timeout should be visible")

    let oldCli = CodexInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, _, _, _ in
            CommandResult(status: 2, stdout: "", stderr: "error: unexpected argument '--resume' found")
        }
    )
    let unsupported = await oldCli.deliver(text: "继续", to: session)
    try expect(unsupported.error == .inputUnavailable, "Old Codex CLI must report unsupported resume")

    let gone = CodexInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, _, _, _ in
            CommandResult(status: 1, stdout: "", stderr: "no rollout found")
        }
    )
    let offline = await gone.deliver(text: "继续", to: session)
    try expect(offline.error == .sessionOffline, "Unknown thread should remain an offline error")

    let claude = AgentSession(
        id: "claude:unsupported",
        provider: .claude,
        providerSessionID: "claude",
        projectName: "Agent-HUD",
        projectPath: "/tmp",
        title: "Claude",
        titleSource: .automatic,
        status: .completed,
        confidence: .high,
        currentAction: "",
        currentFiles: [],
        startedAt: Date(),
        lastActivityAt: Date(),
        completedAt: Date(),
        runs: [],
        latestUserPrompt: nil,
        sourcePath: "",
        isLive: false,
        git: nil
    )
    let dispatcher = AgentInputDispatcher(
        registry: AgentRuntimeRegistry(),
        deliveryStore: DeliveryStore(),
        adapters: [adapter]
    )
    try expect(!dispatcher.capability(for: claude).enabled, "Other providers must remain unsupported")
    try expect(dispatcher.capability(for: session).enabled, "Dispatcher must not reject completed-capable Codex adapters")
}

@MainActor
func testClaudeResumeInput() async throws {
    let recorder = InputTestRecorder()
    let adapter = ClaudeInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, arguments, directory, _, _ in
            recorder.record(arguments: arguments, directory: directory)
            return CommandResult(status: 0, stdout: "backgrounded · test-id\n", stderr: "")
        }
    )
    let completed = AgentSession(
        id: "claude:resume-input",
        provider: .claude,
        providerSessionID: "7b8ac574-bb30-4ff7-850d-0668fdc258d9",
        projectName: "Agent-HUD",
        projectPath: "/tmp/Agent-HUD",
        title: "Claude",
        titleSource: .automatic,
        status: .completed,
        confidence: .high,
        currentAction: "",
        currentFiles: [],
        startedAt: Date().addingTimeInterval(-120),
        lastActivityAt: Date().addingTimeInterval(-60),
        completedAt: Date().addingTimeInterval(-60),
        runs: [],
        latestUserPrompt: nil,
        sourcePath: "",
        isLive: true,
        git: nil
    )
    try expect(adapter.canAcceptInput(for: completed).enabled, "Finished Claude turns must support background resume")
    let result = await adapter.deliver(text: "继续修复同步", to: completed)
    try expect(result.success && result.status == .delivered, "Accepted Claude background resume should be delivered")
    try expect(
        recorder.arguments == ["--bg", "--resume", completed.providerSessionID, "继续修复同步"],
        "Claude must resume the selected session with the exact text"
    )
    try expect(recorder.workingDirectory == completed.projectPath, "Claude must resume from the session's project directory")

    let busy = ClaudeInputAdapter(executable: "/bin/echo")
    let running = AgentSession(
        id: completed.id,
        provider: .claude,
        providerSessionID: completed.providerSessionID,
        projectName: completed.projectName,
        projectPath: completed.projectPath,
        title: completed.title,
        titleSource: .automatic,
        status: .working,
        confidence: .high,
        currentAction: "",
        currentFiles: [],
        startedAt: completed.startedAt,
        lastActivityAt: Date(),
        completedAt: nil,
        runs: [],
        latestUserPrompt: nil,
        sourcePath: "",
        isLive: true,
        git: nil
    )
    try expect(!busy.canAcceptInput(for: running).enabled, "Running Claude must not spawn a duplicate conversation")
    let rejected = await busy.deliver(text: "不要另开会话", to: running)
    try expect(!rejected.success && rejected.error == .agentBusy, "Busy Claude delivery must report agentBusy")

    let missing = ClaudeInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, _, _, _, _ in
            CommandResult(status: 1, stdout: "", stderr: "No conversation found")
        }
    )
    let offline = await missing.deliver(text: "继续", to: completed)
    try expect(!offline.success && offline.error == .sessionOffline, "Unknown Claude sessions must remain offline errors")
}
