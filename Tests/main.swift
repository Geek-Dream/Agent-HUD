import Foundation

enum SmokeFailure: Error {
    case failed(String)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SmokeFailure.failed(message)
    }
}

func json(_ source: String) -> [String: Any] {
    let data = Data(source.utf8)
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

func testCodex() throws {
    guard let now = DateParser.parse("2026-11-10T10:10:00.000Z") else {
        throw SmokeFailure.failed("Could not parse test date")
    }

    let records = [
        json("""
        {"timestamp":"2026-11-10T10:00:00.000Z","type":"session_meta","payload":{"id":"codex-session","cwd":"/tmp/agent-hud","timestamp":"2026-11-10T10:00:00.000Z"}}
        """),
        json("""
        {"timestamp":"2026-11-10T10:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"完善浮窗列表"}]}}
        """),
        json("""
        {"timestamp":"2026-11-10T10:00:02.000Z","type":"event_msg","payload":{"type":"task_started","started_at":"2026-11-10T10:00:02.000Z"}}
        """),
        json("""
        {"timestamp":"2026-11-10T10:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"apply_patch","arguments":"{\\"file_path\\":\\"/tmp/agent-hud/HUD.swift\\"}"}}
        """),
        json("""
        {"timestamp":"2026-11-10T10:05:00.000Z","type":"event_msg","payload":{"type":"task_complete","completed_at":"2026-11-10T10:05:00.000Z","last_agent_message":"列表、详情和收起模式已经完成。"}}
        """),
        json("""
        {"timestamp":"2026-11-10T10:06:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"继续"}]}}
        """),
        json("""
        {"timestamp":"2026-11-10T10:06:01.000Z","type":"event_msg","payload":{"type":"task_started","started_at":"2026-11-10T10:06:01.000Z"}}
        """),
        json("""
        {"timestamp":"2026-11-10T10:09:00.000Z","type":"event_msg","payload":{"type":"task_complete","completed_at":"2026-11-10T10:09:00.000Z","last_agent_message":"剩余的交互检查也已完成。"}}
        """)
    ]

    let session = CodexAdapter.parse(
        records: records,
        fileURL: URL(fileURLWithPath: "/tmp/rollout.jsonl"),
        modifiedAt: now,
        providerIsRunning: true,
        now: now
    )

    try expect(session?.title == "完善浮窗列表", "Codex title extraction failed")
    try expect(session?.status == .completed, "Codex status extraction failed")
    try expect(session?.runs.count == 2, "Codex run count failed")
    try expect(session?.runs.first?.summary == "列表、详情和收起模式已经完成。", "Codex summary failed")
    try expect(session?.runs.first?.filesChanged == ["/tmp/agent-hud/HUD.swift"], "Codex files failed")
    try expect(session?.runs.last?.objective == "完善浮窗列表", "Codex continuation overwrote the objective")
    try expect(
        session?.latestUserPrompt?.text == "继续",
        "Codex latest user input should track the most recent message independently from the task title"
    )
}

func testClaude() throws {
    guard let now = DateParser.parse("2026-11-10T10:10:00.000Z") else {
        throw SmokeFailure.failed("Could not parse test date")
    }

    let records = [
        json("""
        {"type":"user","sessionId":"claude-session","cwd":"/tmp/agent-hud","gitBranch":"main","timestamp":"2026-11-10T10:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"设计本地会话列表"}]}}
        """),
        json("""
        {"type":"assistant","sessionId":"claude-session","cwd":"/tmp/agent-hud","gitBranch":"main","timestamp":"2026-11-10T10:01:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/agent-hud/List.swift"}},{"type":"text","text":"会话列表已经完成。"}]}}
        """),
        json("""
        {"type":"user","sessionId":"claude-session","cwd":"/tmp/agent-hud","gitBranch":"main","timestamp":"2026-11-10T10:02:00.000Z","message":{"role":"user","content":[{"type":"text","text":"继续"}]}}
        """),
        json("""
        {"type":"assistant","sessionId":"claude-session","cwd":"/tmp/agent-hud","gitBranch":"main","timestamp":"2026-11-10T10:03:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"继续检查也已完成。"}]}}
        """)
    ]

    let session = ClaudeAdapter.parse(
        records: records,
        fileURL: URL(fileURLWithPath: "/tmp/claude.jsonl"),
        modifiedAt: now,
        providerIsRunning: true,
        now: now
    )

    try expect(session?.title == "设计本地会话列表", "Claude title extraction failed")
    try expect(session?.status == .completed, "Claude status extraction failed")
    try expect(session?.runs.count == 2, "Claude run count failed")
    try expect(session?.runs.first?.summary == "会话列表已经完成。", "Claude summary failed")
    try expect(session?.runs.first?.filesChanged == ["/tmp/agent-hud/List.swift"], "Claude files failed")
    try expect(session?.runs.last?.objective == "设计本地会话列表", "Claude continuation overwrote the objective")
    try expect(
        session?.latestUserPrompt?.text == "继续",
        "Claude latest user input should track the most recent message independently from the task title"
    )
}

func testCodexImageOnlyPrompt() throws {
    guard let now = DateParser.parse("2026-11-11T10:01:00.000Z") else {
        throw SmokeFailure.failed("Could not parse Codex image test date")
    }

    let records = [
        json("""
        {"timestamp":"2026-11-11T10:00:00.000Z","type":"session_meta","payload":{"id":"codex-image","cwd":"/tmp/codex-image"}}
        """),
        json("""
        {"timestamp":"2026-11-11T10:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_image","image_url":"data:image/png;base64,iVBORw0KGgo="}]}}
        """)
    ]

    let session = CodexAdapter.parse(
        records: records,
        fileURL: URL(fileURLWithPath: "/tmp/rollout-codex-image.jsonl"),
        modifiedAt: now,
        providerIsRunning: true,
        now: now
    )

    try expect(session?.latestUserPrompt != nil, "Codex image-only input must still be recorded")
    try expect(session?.latestUserPrompt?.text.isEmpty == true, "Codex image-only input should have empty text")
    try expect(session?.latestUserPrompt?.images.count == 1, "Codex data URL image should be extracted")
    if case .dataURL(let value)? = session?.latestUserPrompt?.images.first?.source {
        try expect(value.hasPrefix("data:image/png;base64,"), "Codex image data URL should be preserved")
    } else {
        throw SmokeFailure.failed("Codex image should use a data URL source")
    }
}

func testClaudeImageOnlyPrompt() throws {
    guard let now = DateParser.parse("2026-11-11T10:01:00.000Z") else {
        throw SmokeFailure.failed("Could not parse Claude image test date")
    }

    let records = [
        json("""
        {"type":"user","sessionId":"claude-image","cwd":"/tmp/claude-image","timestamp":"2026-11-11T10:00:00.000Z","message":{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"/9j/4AAQSkZJRg=="}}]}}
        """)
    ]

    let session = ClaudeAdapter.parse(
        records: records,
        fileURL: URL(fileURLWithPath: "/tmp/claude-image.jsonl"),
        modifiedAt: now,
        providerIsRunning: true,
        now: now
    )

    try expect(session?.latestUserPrompt != nil, "Claude image-only input must still be recorded")
    try expect(session?.latestUserPrompt?.text.isEmpty == true, "Claude image-only input should have empty text")
    try expect(session?.latestUserPrompt?.images.count == 1, "Claude base64 image should be extracted")
    if case .dataURL(let value)? = session?.latestUserPrompt?.images.first?.source {
        try expect(
            value.hasPrefix("data:image/jpeg;base64,"),
            "Claude base64 image should become a displayable data URL"
        )
    } else {
        throw SmokeFailure.failed("Claude image should use a data URL source")
    }
}

func testAutomaticTaskTitles() throws {
    let logTitle = TextTools.automaticTaskTitle(
        rawPrompt: "你帮我查询一下刚刚的日志为啥会报错",
        projectName: "dcm"
    )
    try expect(
        logTitle == "查询一下dcm项目日志报错详情",
        "Prompt titles should summarize the action, project and problem"
    )

    let rawPrompt = """
    这是一个空项目，现在，你读取这文档 /Users/wl/Desktop/准备开发/AGENTHUD_REQUIREMENTS.md 读取先理解
    """
    let requirementsTitle = TextTools.automaticTaskTitle(
        rawPrompt: rawPrompt,
        projectName: "Agent-HUD"
    )
    try expect(
        requirementsTitle == "梳理Agent-HUD项目需求",
        "Long document prompts should become a short task title"
    )

    let suggestedTitle = TextTools.automaticTaskTitle(
        rawPrompt: rawPrompt,
        projectName: "Agent-HUD",
        suggestedTitle: "HUD 需求梳理"
    )
    try expect(
        suggestedTitle == "梳理Agent-HUD项目需求",
        "The current user prompt should outrank a provider-generated title"
    )

    let fallbackTitle = TextTools.automaticTaskTitle(
        rawPrompt: "继续",
        projectName: "Agent-HUD"
    )
    try expect(
        fallbackTitle == "处理Agent-HUD项目任务",
        "Continuation prompts should use a natural project fallback"
    )

    let ossTitle = TextTools.automaticTaskTitle(
        rawPrompt: "oss写一个sh脚本，上传成功了，是否可以删除上传的文件",
        projectName: "deploy"
    )
    try expect(
        ossTitle == "脚本是否可以操作oss删除",
        "OSS script deletion prompts should use the dedicated title"
    )

    let realPromptCases: [(prompt: String, expected: String)] = [
        (
            "先确保这个可以折叠，并且丝滑折叠，太影响我的视野了",
            "优化Agent-HUD项目折叠动画"
        ),
        (
            "为啥不可拖动，让他可以拖动可以固定不拖动",
            "修复Agent-HUD项目拖动与固定"
        ),
        (
            "我才发现你的工作是会操控我的鼠标，并且在前台工作，你需要在后台不影响我的情况下搞",
            "修复Agent-HUD项目后台运行方式"
        ),
        (
            "搞个启动的东西，我点击可以启动",
            "添加Agent-HUD项目启动器"
        ),
        (
            "优化一下这个页面首先搞一融合的\n\n上面不是：工作中，等待，完成，错误\n\n然后下面的可以配置成 codex、claude、pi",
            "优化Agent-HUD项目Agent筛选"
        ),
        (
            "我放大和缩小的时候，动画太丑了，一看，就不能做一个过渡么",
            "优化Agent-HUD项目缩放动画"
        ),
        (
            "蓝色太淡，稍微深一点，蓝色是工作，等待黄色，完成绿色，错误红色，用霓虹半透明透光样式",
            "优化Agent-HUD项目状态配色"
        ),
        (
            "优化，现在数据对不上，我现在，orca里面目前看见的，我跑的claude是 4个，生成的codex 是6个，所以我这显示全部22个",
            "修复Agent-HUD项目会话数量统计"
        ),
        (
            """
            你看我发现了一个问题，你的标题使用的都是我在orca里面的标题

            标题：这是一个空项目，现在，你读取这文档 /Users/wl/Desktop/准备开发/AGENTHUD_REQUIREMENTS.md 读取先理解

            标题要支持用户自定义和AI自动总结
            """,
            "修复Agent-HUD项目自动标题"
        )
    ]

    for testCase in realPromptCases {
        let actual = TextTools.automaticTaskTitle(
            rawPrompt: testCase.prompt,
            projectName: "Agent-HUD"
        )
        try expect(
            actual == testCase.expected,
            "Real prompt should produce '\(testCase.expected)', got '\(actual)'"
        )
    }

    let imagePrompt = """
    <image name=[Image #1] path="/tmp/screenshot.png">
    </image>
    我要的拖动不只是点击拖动，而是点击表格头也能拖动，并且配色不好，我看不清楚
    """
    let imageTitle = TextTools.automaticTaskTitle(
        rawPrompt: imagePrompt,
        projectName: "Agent-HUD"
    )
    try expect(
        imageTitle == "优化Agent-HUD项目拖动与配色",
        "Image placeholders must not become automatic title content"
    )

    let hookPrompt = """
    <hook_prompt hook_run_id="stop:1">[AgentRelay 交付审计] 逻辑修改缺少 RED。</hook_prompt>
    """
    let hookTitle = TextTools.automaticTaskTitle(
        rawPrompt: hookPrompt,
        projectName: "Agent-HUD"
    )
    try expect(
        hookTitle == "处理Agent-HUD项目任务",
        "Injected hook prompts must not become task titles"
    )
}

func testSessionTitleStore() throws {
    let suiteName = "AgentHUD.SessionTitleStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw SmokeFailure.failed("Could not create isolated title store defaults")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = SessionTitleStore(defaults: defaults)
    try expect(store.title(for: "claude:session") == nil, "Custom titles should start empty")

    let saved = store.setCustomTitle("  日志查询  ", for: "claude:session")
    try expect(saved == "日志查询", "Custom title whitespace should be normalized")
    try expect(
        SessionTitleStore(defaults: defaults).title(for: "claude:session") == "日志查询",
        "Custom titles should persist across store instances"
    )

    store.removeCustomTitle(for: "claude:session")
    try expect(store.title(for: "claude:session") == nil, "Clearing a custom title should remove it")
}

func testSessionImportanceStore() throws {
    let suiteName = "AgentHUD.SessionImportanceStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw SmokeFailure.failed("Could not create isolated importance store defaults")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = SessionImportanceStore(defaults: defaults)
    try expect(!store.isImportant("codex:session"), "Sessions should start unimportant")
    try expect(store.toggle("codex:session"), "Toggling an unimportant session should mark it important")
    try expect(
        SessionImportanceStore(defaults: defaults).isImportant("codex:session"),
        "Important sessions should persist across store instances"
    )
    try expect(!store.toggle("codex:session"), "Toggling an important session should clear it")
}

func testImportantSessionOrdering() throws {
    let now = Date()
    let working = makeTestSession(
        id: "codex:working",
        status: .working,
        lastActivityAt: now.addingTimeInterval(30)
    )
    let completed = makeTestSession(
        id: "claude:completed",
        status: .completed,
        lastActivityAt: now.addingTimeInterval(20)
    )
    let importantCompleted = makeTestSession(
        id: "pi:important",
        status: .completed,
        lastActivityAt: now.addingTimeInterval(10)
    )

    let ordered = SessionOrdering.sorted(
        [working, completed, importantCompleted],
        importantSessionIDs: [importantCompleted.id]
    )
    try expect(
        ordered.map(\.id) == [importantCompleted.id, working.id, completed.id],
        "Important sessions must be pinned ahead of active sessions"
    )
}

func testRunningFirstOrderingAndCompletionTransition() throws {
    let now = Date()
    let working = makeTestSession(
        id: "codex:working",
        status: .working,
        lastActivityAt: now.addingTimeInterval(30)
    )
    let starting = makeTestSession(
        id: "claude:starting",
        status: .starting,
        lastActivityAt: now.addingTimeInterval(25)
    )
    let waiting = makeTestSession(
        id: "pi:waiting",
        status: .waitingUser,
        lastActivityAt: now.addingTimeInterval(40)
    )
    let completed = makeTestSession(
        id: "codex:completed",
        status: .completed,
        lastActivityAt: now.addingTimeInterval(35)
    )
    let importantCompleted = makeTestSession(
        id: "claude:important",
        status: .completed,
        lastActivityAt: now.addingTimeInterval(10)
    )

    let ordered = SessionOrdering.sorted(
        [waiting, completed, starting, working, importantCompleted],
        importantSessionIDs: [importantCompleted.id],
        runningFirst: true
    )
    try expect(
        ordered.map(\.id) == [
            importantCompleted.id,
            working.id,
            starting.id,
            waiting.id,
            completed.id
        ],
        "All sessions should keep important rows first, then running rows, then the existing status order"
    )

    let currentSessions = [
        makeTestSession(
            id: working.id,
            status: .completed,
            lastActivityAt: now.addingTimeInterval(31)
        ),
        makeTestSession(
            id: starting.id,
            status: .working,
            lastActivityAt: now.addingTimeInterval(26)
        ),
        completed,
        waiting
    ]
    let completionIDs = SessionTransitionDetector.runningCompletionIDs(
        previousSessions: [working, starting, completed, waiting],
        currentSessions: currentSessions
    )
    try expect(
        completionIDs == [working.id],
        "Only running-to-completed transitions should trigger the completion animation"
    )
    try expect(
        SessionTransitionDetector.runningCompletionIDs(
            previousSessions: currentSessions,
            currentSessions: currentSessions
        ).isEmpty,
        "Already completed sessions must not retrigger the completion animation"
    )
    try expect(
        ImportantCompletionNoticePolicy.shouldPresent(
            previousStatus: .working,
            currentStatus: .completed,
            isImportant: true,
            isVisible: false
        ),
        "Hidden important sessions should surface a completion notice"
    )
    try expect(
        !ImportantCompletionNoticePolicy.shouldPresent(
            previousStatus: .working,
            currentStatus: .completed,
            isImportant: true,
            isVisible: true
        ),
        "Visible important completions should not duplicate the row animation with a notice"
    )
}

func testSessionOutlinePolicy() throws {
    for status in [AgentStatus.starting, .working, .waitingUser, .completed, .failed] {
        try expect(
            SessionOutlinePolicy.shouldShow(status: status, isImportant: true),
            "Important \(status) sessions must show their status outline"
        )
        try expect(
            !SessionOutlinePolicy.shouldShow(status: status, isImportant: false),
            "Unstarred \(status) sessions must not show an outline"
        )
    }
    for status in [AgentStatus.idle, .unknown] {
        try expect(
            !SessionOutlinePolicy.shouldShow(status: status, isImportant: true),
            "\(status) sessions must not show a status outline"
        )
    }
}

func testExpandedPanelSizePolicy() throws {
    try expect(ExpandedPanelSize.clampedWidth(500) == 500, "Valid custom width should be preserved")
    try expect(ExpandedPanelSize.clampedHeight(700) == 700, "Valid custom height should be preserved")
    try expect(
        ExpandedPanelSize.clampedWidth(10_000) == ExpandedPanelSize.maximumWidth,
        "Width must not exceed its upper limit"
    )
    try expect(
        ExpandedPanelSize.clampedHeight(10_000) == ExpandedPanelSize.maximumHeight,
        "Height must not exceed its upper limit"
    )
    try expect(
        ExpandedPanelSize.clampedWidth(1) == ExpandedPanelSize.minimumWidth,
        "Width must not be smaller than its lower limit"
    )
    try expect(
        ExpandedPanelSize.clampedHeight(.nan) == ExpandedPanelSize.defaultHeight,
        "Invalid height should restore the default"
    )
}

func testOpenCode() throws {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let user = OpenCodeEvent(
        id: "msg-user",
        date: base,
        data: ["role": "user"]
    )
    let assistant = OpenCodeEvent(
        id: "msg-assistant",
        date: base.addingTimeInterval(1),
        data: ["role": "assistant", "time": ["completed": (base.addingTimeInterval(4).timeIntervalSince1970 * 1_000)]]
    )
    let userText = OpenCodeEvent(
        id: "part-user-text",
        date: base,
        data: ["messageID": "msg-user", "type": "text", "text": "增加 OpenCode 支持"]
    )
    let question = OpenCodeEvent(
        id: "part-question",
        date: base.addingTimeInterval(2),
        data: [
            "messageID": "msg-assistant",
            "type": "tool",
            "tool": "question",
            "state": ["status": "running", "input": ["filePath": "/tmp/Agent-HUD/Models.swift"]]
        ]
    )
    let summary = OpenCodeEvent(
        id: "part-summary",
        date: base.addingTimeInterval(4),
        data: ["messageID": "msg-assistant", "type": "text", "text": "OpenCode 已接入。"]
    )
    let record = OpenCodeSessionRecord(
        id: "ses_test",
        directory: "/tmp/Agent-HUD",
        title: "OpenCode 会话",
        createdAt: base,
        updatedAt: base.addingTimeInterval(4),
        messages: [assistant, user],
        parts: [summary, question, userText]
    )
    let waiting = OpenCodeAdapter.parse(
        record: record,
        fileURL: URL(fileURLWithPath: "/tmp/opencode.db"),
        providerIsRunning: true,
        now: base.addingTimeInterval(100)
    )
    try expect(waiting?.provider == .opencode, "OpenCode provider must be preserved")
    try expect(waiting?.status == .waitingUser, "OpenCode question must map to waiting")
    try expect(
        waiting?.title.contains("OpenCode") == true && waiting?.title != "OpenCode 会话",
        "OpenCode title should use the substantive prompt, actual: \(waiting?.title ?? "nil")"
    )
    try expect(waiting?.currentFiles == ["/tmp/Agent-HUD/Models.swift"], "OpenCode tool files should be extracted")

    let completed = OpenCodeAdapter.parse(
        record: OpenCodeSessionRecord(
            id: "ses_test",
            directory: "/tmp/Agent-HUD",
            title: "OpenCode 会话",
            createdAt: base,
            updatedAt: base.addingTimeInterval(4),
            messages: [assistant, user],
            parts: [summary, userText]
        ),
        fileURL: URL(fileURLWithPath: "/tmp/opencode.db"),
        providerIsRunning: false,
        now: base.addingTimeInterval(100)
    )
    try expect(completed?.status == .completed, "OpenCode final text must map to completed")
    try expect(completed?.runs.count == 1, "OpenCode completion should produce a run")

    let failed = OpenCodeAdapter.parse(
        record: OpenCodeSessionRecord(
            id: "ses_test",
            directory: "/tmp/Agent-HUD",
            title: "OpenCode 会话",
            createdAt: base,
            updatedAt: base.addingTimeInterval(4),
            messages: [assistant, user],
            parts: [
                userText,
                OpenCodeEvent(
                    id: "part-error",
                    date: base.addingTimeInterval(3),
                    data: [
                        "messageID": "msg-assistant",
                        "type": "tool",
                        "tool": "bash",
                        "state": ["status": "error"]
                    ]
                )
            ]
        ),
        fileURL: URL(fileURLWithPath: "/tmp/opencode.db"),
        providerIsRunning: true,
        now: base.addingTimeInterval(100)
    )
    try expect(failed?.status == .failed, "OpenCode tool error must map to failed")
}

func testOpenCodeCurrentDatabase() throws {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/opencode/opencode.db")
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }
    let sessions = OpenCodeSessionSource.scan(
        databaseURL: url,
        providerIsRunning: true,
        now: Date()
    )
    try expect(!sessions.isEmpty, "The current OpenCode database should produce sessions")
    try expect(
        sessions.allSatisfy { $0.provider == .opencode && $0.id.hasPrefix("opencode:") },
        "Database rows must use the OpenCode provider identity"
    )
    try expect(
        sessions.contains { $0.latestUserPrompt != nil },
        "The current OpenCode database must include readable user prompts"
    )
}

func makeTestSession(
    id: String,
    status: AgentStatus,
    lastActivityAt: Date
) -> AgentSession {
    AgentSession(
        id: id,
        provider: .codex,
        providerSessionID: id,
        projectName: "Agent-HUD",
        projectPath: "/tmp/Agent-HUD",
        title: "测试会话",
        titleSource: .automatic,
        status: status,
        confidence: .high,
        currentAction: "测试",
        currentFiles: [],
        startedAt: lastActivityAt.addingTimeInterval(-60),
        lastActivityAt: lastActivityAt,
        completedAt: status == .completed ? lastActivityAt : nil,
        runs: [],
        latestUserPrompt: nil,
        sourcePath: "/tmp/Agent-HUD/session.jsonl",
        isLive: false,
        git: nil
    )
}

func testLogReaderFindsRecentPromptBeyondTail() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentHUD-large-transcript-\(UUID().uuidString).jsonl")
    defer {
        try? FileManager.default.removeItem(at: url)
    }

    var lines = [
        """
        {"timestamp":"2026-11-11T08:00:00.000Z","type":"session_meta","payload":{"id":"large-session","cwd":"/tmp/Agent-HUD"}}
        """,
        """
        {"timestamp":"2026-11-11T08:01:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"查询最近日志报错"}]}}
        """
    ]
    let filler = String(repeating: "x", count: 12_000)
    for index in 0..<100 {
        lines.append(
            """
            {"timestamp":"2026-11-11T08:02:00.000Z","type":"event_msg","payload":{"type":"item_completed","index":\(index),"output":"\(filler)"}}
            """
        )
    }
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)

    let initialRecords = try LogFileReader.readJSONLines(from: url)
    let initialPrompt = initialRecords.first { record in
        let payload = record["payload"] as? [String: Any]
        return record["type"] as? String == "response_item"
            && payload?["role"] as? String == "user"
    }
    try expect(
        JSONTools.collectText((initialPrompt?["payload"] as? [String: Any])?["content"])
            .joined() == "查询最近日志报错",
        "Reader must recover recent prompts outside the bounded tail window"
    )

    let appended = """
    {"timestamp":"2026-11-11T08:03:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"继续"}]}}
    """
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((appended + "\n").utf8))
    try handle.close()

    let updatedRecords = try LogFileReader.readJSONLines(from: url)
    let promptTexts = updatedRecords.compactMap { record -> String? in
        guard record["type"] as? String == "response_item",
              let payload = record["payload"] as? [String: Any],
              payload["role"] as? String == "user" else {
            return nil
        }
        return JSONTools.collectText(payload["content"]).joined()
    }
    try expect(
        promptTexts.contains("继续"),
        "Prompt index must incrementally pick up newly appended user input"
    )
}

func testOrcaCurrentTabs() throws {
    guard let now = DateParser.parse("2026-11-11T10:00:00.000Z") else {
        throw SmokeFailure.failed("Could not parse Orca test date")
    }

    let workspace = json("""
    {
      "tabsByWorktree": {
        "repo::/tmp/current": [
          {
            "id": "codex-tab",
            "title": "Codex terminal",
            "customTitle": "Codex 自定义",
            "createdAt": 1794380000000,
            "aiVaultTitle": {
              "agent": "codex",
              "sessionId": "codex-current",
              "title": "实现当前标签统计"
            }
          },
          {
            "id": "claude-tab",
            "title": "Claude terminal",
            "createdAt": 1794380001000,
            "aiVaultTitle": {
              "agent": "claude",
              "sessionId": "claude-current",
              "title": "检查会话列表"
            }
          },
          {
            "id": "terminal-tab",
            "title": "Terminal 1",
            "createdAt": 1794380002000
          }
        ]
      },
      "unifiedTabs": {
        "repo::/tmp/current": [
          {
            "id": "codex-tab",
            "customLabel": "当前标签"
          }
        ]
      },
      "sleepingAgentSessionsByPaneKey": {}
    }
    """)

    let statuses = [
        json("""
        {
          "tabId":"codex-tab",
          "paneKey":"codex-tab:pane",
          "providerSession":{"id":"codex-current"},
          "payload":{"state":"working","mainAgent":{"state":"working"}},
          "receivedAt":1794380100000
        }
        """),
        json("""
        {
          "tabId":"codex-tab",
          "paneKey":"codex-tab:pane",
          "providerSession":{"id":"codex-current"},
          "payload":{
            "state":"working",
            "prompt":"完成 Orca 标签统计",
            "lastAssistantMessage":"当前标签统计已经完成。",
            "mainAgent":{"state":"done","stateStartedAt":1794380200000}
          },
          "receivedAt":1794380200000
        }
        """),
        json("""
        {
          "tabId":"historical-tab",
          "paneKey":"historical-tab:pane",
          "providerSession":{"id":"historical-session"},
          "payload":{"state":"working","mainAgent":{"state":"working"}},
          "receivedAt":1794380300000
        }
        """)
    ]

    let sessions = OrcaSessionSource.makeSessions(
        workspacePayload: workspace,
        statusEntries: statuses,
        now: now
    )

    try expect(sessions?.count == 2, "Current Orca tabs must define membership")
    let codex = sessions?.first { $0.providerSessionID == "codex-current" }
    let claude = sessions?.first { $0.providerSessionID == "claude-current" }
    try expect(
        codex?.title == "完成 Orca 标签统计",
        "Orca prompt should produce an automatic title instead of using the tab label"
    )
    try expect(
        codex?.titleSource == .automatic,
        "Orca tab labels must not be treated as AgentHUD user titles"
    )
    try expect(codex?.status == .completed, "Newest mainAgent state should override top-level state")
    try expect(codex?.runs.first?.summary == "当前标签统计已经完成。", "Status summary should create a completed run")
    try expect(claude != nil, "A current tab without status must still be included")
    try expect(claude?.status == .unknown, "Missing status should fall back to unknown")
    try expect(
        sessions?.contains(where: { $0.providerSessionID == "historical-session" }) == false,
        "Historical status rows outside current tabs must be excluded"
    )

    let failedWorkspace = json("""
    {
      "tabsByWorktree": {
        "repo::/tmp/failure": [
          {
            "id":"failed-tab",
            "createdAt":1794380000000,
            "aiVaultTitle":{"agent":"claude","sessionId":"failed-current","title":"失败任务"}
          }
        ]
      }
    }
    """)
    let failedStatus = json("""
    {
      "tabId":"failed-tab",
      "providerSession":{"id":"failed-current"},
      "payload":{
        "state":"done",
        "mainAgent":{"state":"done","outcome":"interruption","stateStartedAt":1794380200000}
      },
      "receivedAt":1794380200000
    }
    """)
    let failed = OrcaSessionSource.makeSessions(
        workspacePayload: failedWorkspace,
        statusEntries: [failedStatus],
        now: now
    )?.first
    try expect(failed?.status == .failed, "Failure outcomes must map done sessions to failed")

    let customTitleWorkspace = json("""
    {
      "tabsByWorktree": {
        "repo::/tmp/custom": [
          {
            "id":"custom-tab",
            "createdAt":1794380000000,
            "customTitle":"日志查询",
            "aiVaultTitle":{
              "agent":"claude",
              "sessionId":"custom-current",
              "title":"你帮我查询一下刚刚的日志为啥会报错"
            }
          }
        ]
      }
    }
    """)
    let customTitle = OrcaSessionSource.makeSessions(
        workspacePayload: customTitleWorkspace,
        statusEntries: [],
        now: now
    )?.first
    try expect(
        customTitle?.title == "处理custom项目任务",
        "Orca custom titles must not leak into AgentHUD automatic titles"
    )
    try expect(
        customTitle?.titleSource == .automatic,
        "AgentHUD title overrides are the only source of user titles"
    )

    let transcriptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentHUD-title-source-\(UUID().uuidString).jsonl")
    defer {
        try? FileManager.default.removeItem(at: transcriptURL)
    }
    let transcript = [
        """
        {"timestamp":"2026-11-11T08:00:00.000Z","type":"session_meta","payload":{"id":"transcript-title","cwd":"/tmp/title-sample"}}
        """,
        """
        {"timestamp":"2026-11-11T08:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"你看我发现了一个问题，标题要支持自动总结"}]}}
        """,
        """
        {"timestamp":"2026-11-11T08:01:00.000Z","type":"event_msg","payload":{"type":"task_complete","completed_at":"2026-11-11T08:01:00.000Z","last_agent_message":"标题功能已经完成。"}}
        """
    ].joined(separator: "\n") + "\n"
    try Data(transcript.utf8).write(to: transcriptURL)

    let transcriptWorkspace = json("""
    {
      "tabsByWorktree": {
        "repo::/tmp/title-sample": [
          {
            "id":"transcript-tab",
            "createdAt":1794380000000,
            "aiVaultTitle":{
              "agent":"codex",
              "sessionId":"transcript-title",
              "title":"Orca 里的旧标题"
            }
          }
        ]
      }
    }
    """)
    let transcriptStatus = json("""
    {
      "tabId":"transcript-tab",
      "providerSession":{
        "id":"transcript-title",
        "cwd":"/tmp/title-sample",
        "transcriptPath":"\(transcriptURL.path)"
      },
      "payload":{
        "state":"done",
        "prompt":"Orca 旧状态输入",
        "mainAgent":{"state":"done","stateStartedAt":1794380100000}
      },
      "receivedAt":1794380100000
    }
    """)
    let transcriptTitle = OrcaSessionSource.makeSessions(
        workspacePayload: transcriptWorkspace,
        statusEntries: [transcriptStatus],
        now: now
    )?.first
    try expect(
        transcriptTitle?.title == "修复title-sample项目自动标题",
        "The transcript's latest user input must outrank an older Orca status prompt"
    )

    let unavailable = OrcaSessionSource.makeSessions(
        workspacePayload: [:],
        statusEntries: [],
        now: now
    )
    try expect(unavailable == nil, "Missing Orca workspace data should signal transcript fallback")

    let visibilityWorkspace = json("""
    {
      "tabsByWorktree": {
        "visible-repo::/tmp/visible": [
          {
            "id":"visible-tab",
            "createdAt":1794380000000,
            "aiVaultTitle":{"agent":"codex","sessionId":"visible-current","title":"可见任务"}
          }
        ],
        "hidden-repo::/tmp/hidden": [
          {
            "id":"hidden-tab",
            "createdAt":1794380000000,
            "aiVaultTitle":{"agent":"claude","sessionId":"hidden-current","title":"折叠任务"}
          }
        ]
      }
    }
    """)
    let visibilityUI = json("""
    {"collapsedGroups":["project:git:hidden/repo"]}
    """)
    let visibilityMeta = json("""
    {
      "visible-repo::/tmp/visible":{"projectId":"git:visible/repo"},
      "hidden-repo::/tmp/hidden":{"projectId":"git:hidden/repo"}
    }
    """)
    let visibleSessions = OrcaSessionSource.makeSessions(
        workspacePayload: visibilityWorkspace,
        statusEntries: [],
        uiPayload: visibilityUI,
        worktreeMeta: visibilityMeta,
        now: now
    )
    try expect(visibleSessions?.count == 1, "Collapsed Orca project groups should be excluded")
    try expect(
        visibleSessions?.first?.providerSessionID == "visible-current",
        "Only the expanded project's Agent should remain"
    )
}

func testSessionTitleResolution() throws {
    let local = SessionTitleResolver.resolve(
        manualTitle: nil,
        aiTitle: nil,
        localTitle: "本地标题"
    )
    try expect(local.value == "本地标题", "Local title should be the fallback")
    try expect(local.source == .automatic, "Fallback title should be marked automatic")

    let ai = SessionTitleResolver.resolve(
        manualTitle: nil,
        aiTitle: "查询日志报错详情",
        localTitle: "本地标题"
    )
    try expect(ai.value == "查询日志报错详情", "AI title should outrank the local title")
    try expect(ai.source == .ai, "AI title should retain its source")

    let manual = SessionTitleResolver.resolve(
        manualTitle: "  日志查询  ",
        aiTitle: "查询日志报错详情",
        localTitle: "本地标题"
    )
    try expect(manual.value == "  日志查询  ", "Manual title should outrank AI and local titles")
    try expect(manual.source == .user, "Manual title should retain its source")
}

func testAITitleOutputSanitizer() throws {
    let cleaned = AITitleOutputSanitizer.sanitize(
        "  **标题：查询日志报错详情**。",
        originalPrompt: "你帮我查询一下刚刚的日志为啥会报错",
        projectName: "dcm"
    )
    try expect(cleaned == "查询日志报错详情", "AI title markdown and prefixes should be removed")

    try expect(
        AITitleOutputSanitizer.sanitize(
            "处理Agent-HUD项目任务",
            originalPrompt: "继续",
            projectName: "Agent-HUD"
        ) == nil,
        "Generic task templates should be rejected"
    )
    try expect(
        AITitleOutputSanitizer.sanitize(
            "Agent-HUD任务详情",
            originalPrompt: "查看详情",
            projectName: "Agent-HUD"
        ) == nil,
        "Titles repeating the project name should be rejected"
    )
    try expect(
        AITitleOutputSanitizer.sanitize(
            "查询日志报错详情",
            originalPrompt: "查询日志报错详情",
            projectName: "dcm"
        ) == nil,
        "Titles that copy the original prompt should be rejected"
    )
    try expect(
        AITitleOutputSanitizer.sanitize(
            "日志.swift报错详情",
            originalPrompt: "查看日志",
            projectName: "dcm"
        ) == nil,
        "Technical file noise should be rejected"
    )
}

func testAIRequestConstruction() throws {
    let imageURL = "data:image/png;base64,iVBORw0KGgo="
    let prepared = try AITitleRequestFactory.prepare(
        AITitleRequest(
            sessionID: "request-test",
            prompt: "你帮我查询一下日志为啥会报错",
            projectName: "dcm",
            images: [
                SessionImageAttachment(
                    id: "image-1",
                    source: .dataURL(imageURL),
                    label: "[图片1]"
                )
            ]
        )
    )
    let configuration = AIConfiguration(
        enabled: true,
        endpoint: "https://example.com/v1/",
        model: "test-model"
    )
    let request = try AITitleRequestFactory.makeURLRequest(
        prepared: prepared,
        configuration: configuration,
        apiKey: "test-key"
    )

    try expect(
        request.url?.absoluteString == "https://example.com/v1/chat/completions",
        "Endpoint should resolve to chat completions"
    )
    try expect(request.httpMethod == "POST", "AI request should use POST")
    try expect(
        request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key",
        "AI request should send the bearer token"
    )
    try expect(
        request.value(forHTTPHeaderField: "Content-Type") == "application/json",
        "AI request should send JSON"
    )

    let bodyData = request.httpBody ?? Data()
    let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]
    try expect(body["model"] as? String == "test-model", "AI request should include the model")
    try expect(body["max_tokens"] as? Int == 512, "AI request should leave room for reasoning models")
    try expect(
        body["temperature"] == nil,
        "AI request should not force a model-specific temperature"
    )
    let messages = body["messages"] as? [[String: Any]] ?? []
    let userMessage = messages.first { $0["role"] as? String == "user" }
    let content = userMessage?["content"] as? [[String: Any]] ?? []
    let text = content.first?["text"] as? String ?? ""
    try expect(
        text.contains("你帮我查询一下日志为啥会报错"),
        "AI request should include the latest user prompt"
    )
    try expect(
        content.contains { item in
            item["type"] as? String == "image_url"
                && (item["image_url"] as? [String: Any])?["url"] as? String == imageURL
        },
        "AI request should include multimodal image content"
    )
}

func testAIImagePreparation() throws {
    let localImageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentHUD-ai-image-\(UUID().uuidString).png")
    defer {
        try? FileManager.default.removeItem(at: localImageURL)
    }
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: localImageURL)

    let directDataURL = "data:image/jpeg;base64,/9j/4AAQSkZJRg=="
    let prepared = try AITitleRequestFactory.prepare(
        AITitleRequest(
            sessionID: "image-test",
            prompt: "",
            projectName: "Agent-HUD",
            images: [
                SessionImageAttachment(
                    id: "local-image",
                    source: .localPath(localImageURL.path),
                    label: "[图片1]"
                ),
                SessionImageAttachment(
                    id: "direct-image",
                    source: .dataURL(directDataURL),
                    label: "[图片2]"
                )
            ]
        )
    )

    try expect(prepared.imageDataURLs.count == 2, "Readable local and data URL images should be prepared")
    try expect(
        prepared.imageDataURLs.first?.hasPrefix("data:image/png;base64,") == true,
        "Local PNG images should be converted to data URLs"
    )
    try expect(
        prepared.imageDataURLs.last == directDataURL,
        "Existing data URLs should be preserved"
    )
    try expect(!prepared.imageFingerprint.isEmpty, "Prepared images should have a content fingerprint")

    let request = try AITitleRequestFactory.makeURLRequest(
        prepared: prepared,
        configuration: AIConfiguration(
            enabled: true,
            endpoint: "https://example.com/v1",
            model: "test-model"
        ),
        apiKey: "test-key"
    )
    let bodyData = request.httpBody ?? Data()
    let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]
    let messages = body["messages"] as? [[String: Any]] ?? []
    let content = messages.first { $0["role"] as? String == "user" }?["content"]
        as? [[String: Any]] ?? []
    let text = content.first?["text"] as? String ?? ""
    try expect(
        text.contains("用户只发送了图片"),
        "Image-only prompts should use the image-specific instruction"
    )

    do {
        _ = try AITitleRequestFactory.prepare(
            AITitleRequest(
                sessionID: "missing-image-test",
                prompt: "",
                projectName: "Agent-HUD",
                images: [
                    SessionImageAttachment(
                        id: "missing-image",
                        source: .localPath(
                            FileManager.default.temporaryDirectory
                                .appendingPathComponent("missing-\(UUID().uuidString).png")
                                .path
                        ),
                        label: "[图片1]"
                    )
                ]
            )
        )
        throw SmokeFailure.failed("Unreadable image-only prompts should not call the AI")
    } catch AITitleServiceError.emptyPrompt {
        // Expected: the view model keeps the local title when no image can be read.
    }
}

private enum MockAITransportError: Error {
    case missingResponse
}

private actor MockAITitleTransport: AITitleTransport {
    private var responses: [AITitleHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [AITitleHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> AITitleHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw MockAITransportError.missingResponse
        }
        return responses.removeFirst()
    }

    func recordedRequestCount() -> Int {
        requests.count
    }
}

func testAICacheAndFailureBackoff() async throws {
    let responseData = try JSONSerialization.data(withJSONObject: [
        "choices": [
            [
                "message": [
                    "content": "查询日志报错详情"
                ]
            ]
        ]
    ])
    let successTransport = MockAITitleTransport(
        responses: [
            AITitleHTTPResponse(data: responseData, statusCode: 200),
            AITitleHTTPResponse(data: responseData, statusCode: 200)
        ]
    )
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    let successService = AITitleService(
        transport: successTransport,
        now: { fixedNow },
        failureBackoff: 300
    )
    let request = AITitleRequest(
        sessionID: "cache-test",
        prompt: "你帮我查询一下刚刚的日志为啥会报错",
        projectName: "dcm",
        images: []
    )
    let configuration = AIConfiguration(
        enabled: true,
        endpoint: "https://example.com/v1",
        model: "test-model"
    )

    let firstTitle = try await successService.title(
        for: request,
        configuration: configuration,
        apiKey: "test-key"
    )
    let secondTitle = try await successService.title(
        for: request,
        configuration: configuration,
        apiKey: "test-key"
    )
    try expect(firstTitle == "查询日志报错详情", "Cached AI title should be returned")
    try expect(secondTitle == firstTitle, "Duplicate AI requests should return the cached title")
    let successRequestCount = await successTransport.recordedRequestCount()
    try expect(successRequestCount == 1, "Duplicate AI requests should not reach the transport twice")

    let failureTransport = MockAITitleTransport(
        responses: [AITitleHTTPResponse(data: Data(), statusCode: 500)]
    )
    let failureService = AITitleService(
        transport: failureTransport,
        now: { fixedNow },
        failureBackoff: 300
    )
    do {
        _ = try await failureService.title(
            for: request,
            configuration: configuration,
            apiKey: "test-key"
        )
        throw SmokeFailure.failed("Expected the first AI request to fail")
    } catch AITitleServiceError.httpStatus(let status) {
        try expect(status == 500, "Unexpected AI HTTP failure status")
    } catch {
        throw error
    }

    do {
        _ = try await failureService.title(
            for: request,
            configuration: configuration,
            apiKey: "test-key"
        )
        throw SmokeFailure.failed("Expected the failed AI request to be in backoff")
    } catch AITitleServiceError.backoff {
        // Expected.
    } catch {
        throw error
    }
    let failureRequestCount = await failureTransport.recordedRequestCount()
    try expect(failureRequestCount == 1, "Failure backoff should prevent duplicate transport requests")
}

func testAIConfiguration() throws {
    let suiteName = "AgentHUD.AIConfigurationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        throw SmokeFailure.failed("Could not create isolated AI configuration defaults")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let configuration = AIConfiguration(
        enabled: true,
        endpoint: "https://example.com/v1/",
        model: "test-model"
    )
    configuration.save(defaults: defaults)
    let loaded = AIConfiguration.load(defaults: defaults)
    try expect(loaded == configuration, "AI configuration should round-trip through UserDefaults")
    try expect(loaded.isUsable, "Enabled valid AI configuration should be usable")
    try expect(
        loaded.chatCompletionsURL?.absoluteString == "https://example.com/v1/chat/completions",
        "AI configuration should derive the chat completions endpoint"
    )
}

func testAISecretEnvironmentFallback() throws {
    let store = KeychainAISecretStore(
        service: "com.agenthud.tests.\(UUID().uuidString)",
        account: "test-account",
        environment: [
            KeychainAISecretStore.environmentKey: "  test-key  "
        ]
    )
    try expect(
        store.apiKey() == "test-key",
        "Environment API key fallback should be normalized"
    )
}

do {
    try expect(TextTools.isContinuationPrompt("确认。"), "Standalone confirmation should be generic")
    try expect(!TextTools.isContinuationPrompt("确认窗口布局"), "Substantive confirmation request should remain a title")
    try expect(StatusFilter.working.matches(.starting), "Starting status should be included in working filter")
    try expect(!StatusFilter.completed.matches(.working), "Completed filter must not include working sessions")
    try expect(ProviderFilter.pi.matches(.pi), "Pi provider filter should match Pi sessions")
    try expect(ProviderFilter.opencode.matches(.opencode), "OpenCode provider filter should match OpenCode sessions")
    try expect(!ProviderFilter.opencode.matches(.codex), "OpenCode provider filter must not include Codex sessions")
    try expect(!ProviderFilter.codex.matches(.claude), "Codex provider filter must not include Claude sessions")
    try expect(
        SessionImageAttachment.displayLabel(for: 0) == "[图片1]",
        "The first image should use a clickable numbered label"
    )
    try expect(
        RunPagination.nextCount(current: 5, total: 12) == 10,
        "The first completion-record expansion should load five more rows"
    )
    try expect(
        RunPagination.nextCount(current: 10, total: 12) == 12,
        "Completion-record expansion should stop at the total count"
    )
    try testAutomaticTaskTitles()
    try testSessionTitleStore()
    try testSessionImportanceStore()
    try testImportantSessionOrdering()
    try testRunningFirstOrderingAndCompletionTransition()
    try testSessionOutlinePolicy()
    try testExpandedPanelSizePolicy()
    try testOpenCode()
    try testOpenCodeCurrentDatabase()
    try testLogReaderFindsRecentPromptBeyondTail()
    try testCodex()
    try testClaude()
    try testCodexImageOnlyPrompt()
    try testClaudeImageOnlyPrompt()
    try testOrcaCurrentTabs()
    try testSessionTitleResolution()
    try testAITitleOutputSanitizer()
    try testAIRequestConstruction()
    try testAIImagePreparation()
    try await testAICacheAndFailureBackoff()
    try testAIConfiguration()
    try testAISecretEnvironmentFallback()
    try testLinkCertificateFingerprintAndStatusProtocol()
    try await testLinkPairing()
    print("23 tests passed (adapter, OpenCode, AI title, session presentation and LAN protocol smoke tests)")
} catch {
    fputs("Adapter smoke tests failed: \(error)\n", stderr)
    exit(1)
}
