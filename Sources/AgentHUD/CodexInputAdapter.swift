import Foundation

@MainActor
final class CodexInputAdapter: AgentInputAdapter {
    let provider: AgentProvider = .codex

    func canAcceptInput(for session: AgentSession) -> AgentInputCapability {
        guard session.isLive else {
            return AgentInputCapability(
                enabled: false,
                state: .offline,
                reason: "会话或进程已经离线。"
            )
        }
        guard session.status == .working
                || session.status == .waitingUser
                || session.status == .idle
                || session.status == .starting else {
            return AgentInputCapability(
                enabled: false,
                state: .busy,
                reason: "当前状态不接受新输入。"
            )
        }
        if session.status == .waitingUser {
            return AgentInputCapability(
                enabled: true,
                state: .waitingUser,
                reason: "Agent 正在等待确认，发送内容将作为当前问题的回复。"
            )
        }
        return AgentInputCapability(enabled: true, state: .ready, reason: nil)
    }

    func deliver(text: String, to session: AgentSession) async -> AgentDeliveryResult {
        let capability = canAcceptInput(for: session)
        guard capability.enabled else {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: capability.state == .offline ? .sessionOffline : .agentBusy
            )
        }

        let terminalTitle = terminalTitle(for: session)
        guard !terminalTitle.isEmpty else {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .inputUnavailable
            )
        }

        let _ = appleScriptEscape(text)
        let script = """
        tell application "System Events"
            tell process "Terminal"
                set frontmost to true
                keystroke "v" using command down
                delay 0.05
                keystroke return
            end tell
        end tell
        """

        do {
            let output = try await runAppleScript(script)
            if output.contains("error") || output.contains("Error") {
                return AgentDeliveryResult(
                    success: false,
                    status: .failed,
                    error: .deliveryFailed
                )
            }
            return AgentDeliveryResult(
                success: true,
                status: .delivered,
                error: nil
            )
        } catch {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .deliveryFailed
            )
        }
    }

    private func terminalTitle(for session: AgentSession) -> String {
        let project = session.projectName
        let objective = session.title
        if project.isEmpty { return objective }
        return "\(project) — \(objective)"
    }

    private func appleScriptEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func runAppleScript(_ source: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", source]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
