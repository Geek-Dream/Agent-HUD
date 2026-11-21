import Foundation

@MainActor
final class ClaudeInputAdapter: AgentInputAdapter {
    typealias CommandRunner = @Sendable (
        String,
        [String],
        String,
        TimeInterval,
        [String: String]?
    ) async -> CommandResult?

    let provider: AgentProvider = .claude

    private let executable: String?
    private let runCommand: CommandRunner

    init(
        executable: String? = nil,
        runCommand: CommandRunner? = nil
    ) {
        self.executable = executable
        self.runCommand = runCommand ?? { executable, arguments, directory, timeout, environment in
            await Task.detached(priority: .userInitiated) {
                BoundedProcess.run(
                    executable: executable,
                    arguments: arguments,
                    timeout: timeout,
                    environment: environment,
                    workingDirectory: directory
                )
            }.value
        }
    }

    func canAcceptInput(for session: AgentSession) -> AgentInputCapability {
        guard !session.providerSessionID.isEmpty else {
            return AgentInputCapability(
                enabled: false,
                state: .unavailable,
                reason: "找不到 Claude 会话编号。"
            )
        }
        if session.isLive && (session.status.isRunning || session.status == .idle) {
            return AgentInputCapability(
                enabled: false,
                state: .busy,
                reason: "Claude 正在处理当前轮次，请完成后再发送续聊指令。"
            )
        }
        return AgentInputCapability(
            enabled: true,
            state: .ready,
            reason: "将后台恢复这个 Claude 会话并发送新指令。"
        )
    }

    func deliver(text: String, to session: AgentSession) async -> AgentDeliveryResult {
        guard canAcceptInput(for: session).enabled else {
            return AgentDeliveryResult(success: false, status: .failed, error: .agentBusy)
        }
        guard let executable = executable ?? Self.claudeExecutable() else {
            return AgentDeliveryResult(success: false, status: .failed, error: .inputUnavailable)
        }

        // --bg --resume 会恢复指定会话；活跃会话不用它另开副本冒充原会话。
        let arguments = ["--bg", "--resume", session.providerSessionID, text]
        let result = await runCommand(
            executable,
            arguments,
            session.projectPath,
            20,
            Self.environmentWithClaudePath()
        )
        guard let result else {
            return AgentDeliveryResult(success: false, status: .failed, error: .inputUnavailable)
        }
        let diagnostics = "\(result.stdout)\n\(result.stderr)".lowercased()
        if result.status != 0 || result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let error: AgentDeliveryError = diagnostics.contains("no conversation found")
                || diagnostics.contains("session not found")
                ? .sessionOffline
                : .deliveryFailed
            return AgentDeliveryResult(success: false, status: .failed, error: error)
        }
        if diagnostics.contains("already running") || diagnostics.contains("starts a copy")
            || diagnostics.contains("already exists") || diagnostics.contains("copy of the session")
            || diagnostics.contains("another session") || diagnostics.contains("复制") {
            return AgentDeliveryResult(success: false, status: .failed, error: .agentBusy)
        }
        return AgentDeliveryResult(success: true, status: .delivered, error: nil)
    }

    private static func claudeExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        let entries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for entry in entries {
            let candidate = "\(entry)/claude"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func environmentWithClaudePath() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var entries = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        where !entries.contains(path) {
            entries.append(path)
        }
        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }
}
