import Foundation

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
    try expect(recent.prefix(2).map(\.id) == ["codex:session-5", "codex:session-0"], "Starred rows stay first, newest activity first")
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
    var arguments: [String] = []
    let adapter = CodexInputAdapter(
        executable: "/bin/echo",
        runCommand: { _, received, _, _ in
            arguments = received
            return CommandResult(status: 0, stdout: "Queued message\n", stderr: "")
        }
    )
    let session = makeTestSession(id: "codex:arguments", status: .working, lastActivityAt: Date())
    _ = await adapter.deliver(text: "请继续，不要改标题", to: session)
    try expect(
        arguments == ["queue", "--thread", "codex:arguments", "--message", "请继续，不要改标题", "--resume"],
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
