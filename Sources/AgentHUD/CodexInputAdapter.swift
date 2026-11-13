import Foundation

@MainActor
final class CodexInputAdapter: AgentInputAdapter {
    let provider: AgentProvider = .codex

    private static let codexPathEntries = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "\(NSHomeDirectory())/.codex/bin",
        "/usr/bin",
        "/bin"
    ]

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

        guard let executable = Self.codexExecutable() else {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .inputUnavailable
            )
        }

        // `codex queue` reports success even for a thread whose TUI is gone, so
        // verify that a process still holds the rollout file before queueing.
        guard await Self.isSessionAttached(session) else {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .sessionOffline
            )
        }

        let arguments = [
            "queue",
            "--thread", session.providerSessionID,
            "--message", text
        ]
        let environment = Self.environmentWithCodexPath()
        let result = await Task.detached(priority: .userInitiated) {
            BoundedProcess.run(
                executable: executable,
                arguments: arguments,
                timeout: 15,
                environment: environment
            )
        }.value

        guard let result else {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .deliveryFailed
            )
        }
        guard result.status == 0 else {
            let stderr = result.stderr.lowercased()
            let error: AgentDeliveryError = stderr.contains("no rollout found")
                ? .sessionOffline
                : .deliveryFailed
            return AgentDeliveryResult(success: false, status: .failed, error: error)
        }
        return AgentDeliveryResult(success: true, status: .delivered, error: nil)
    }

    private static func codexExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.codex/bin/codex"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        let entries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for entry in entries {
            let candidate = "\(entry)/codex"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func environmentWithCodexPath() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var entries = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
        for path in codexPathEntries where !entries.contains(path) {
            entries.append(path)
        }
        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }

    private static func isSessionAttached(_ session: AgentSession) async -> Bool {
        let path = session.sourcePath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return session.isLive
        }
        let result = await Task.detached(priority: .userInitiated) {
            BoundedProcess.run(
                executable: "/usr/sbin/lsof",
                arguments: ["-t", "--", path],
                timeout: 5
            )
        }.value
        guard let result, result.status == 0 else {
            return false
        }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
