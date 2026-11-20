import Foundation

@MainActor
final class CodexInputAdapter: AgentInputAdapter {
    typealias CommandRunner = @Sendable (
        String,
        [String],
        TimeInterval,
        [String: String]?
    ) async -> CommandResult?

    let provider: AgentProvider = .codex

    private static let codexPathEntries = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "\(NSHomeDirectory())/.codex/bin",
        "/usr/bin",
        "/bin"
    ]

    private let executable: String?
    private let runCommand: CommandRunner

    init(
        executable: String? = nil,
        runCommand: CommandRunner? = nil
    ) {
        self.executable = executable
        self.runCommand = runCommand ?? { executable, arguments, timeout, environment in
            await Task.detached(priority: .userInitiated) {
                BoundedProcess.run(
                    executable: executable,
                    arguments: arguments,
                    timeout: timeout,
                    environment: environment
                )
            }.value
        }
    }

    func canAcceptInput(for session: AgentSession) -> AgentInputCapability {
        if session.status == .waitingUser {
            return AgentInputCapability(
                enabled: true,
                state: .waitingUser,
                reason: "Agent 正在等待确认，发送内容将作为当前问题的回复。"
            )
        }
        return AgentInputCapability(
            enabled: true,
            state: .ready,
            reason: session.isLive
                ? nil
                : "将通过 Codex 队列续发；若线程无法恢复，会明确显示失败。"
        )
    }

    func deliver(text: String, to session: AgentSession) async -> AgentDeliveryResult {
        guard let executable = executable ?? Self.codexExecutable() else {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .inputUnavailable
            )
        }

        // queue 负责运行中的排队，--resume 负责完成后的续发。不要用 rollout
        // 文件句柄猜线程状态：Orca/CLI 的 daemon 可能不直接持有该文件。
        let arguments = [
            "queue",
            "--thread", session.providerSessionID,
            "--message", text,
            "--resume"
        ]
        let result = await runCommand(
            executable,
            arguments,
            20,
            Self.environmentWithCodexPath()
        )

        guard let result else {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .inputUnavailable
            )
        }
        guard result.status == 0 else {
            let stderr = result.stderr.lowercased()
            let error: AgentDeliveryError
            if stderr.contains("no rollout found")
                || stderr.contains("thread not found")
                || stderr.contains("session not found") {
                error = .sessionOffline
            } else if stderr.contains("--resume") || stderr.contains("unexpected argument") {
                error = .inputUnavailable
            } else {
                error = .deliveryFailed
            }
            return AgentDeliveryResult(success: false, status: .failed, error: error)
        }

        // Codex 的恢复失败只产生 warning，进程退出码仍为 0。检查两端输出，
        // 防止手机显示「已投递」而 Agent 实际没有收到新任务。
        let diagnostics = "\(result.stdout)\n\(result.stderr)".lowercased()
        if diagnostics.contains("resume failed")
            || diagnostics.contains("failed to resume")
            || diagnostics.contains("failed to determine working directory for resume")
            || diagnostics.contains("failed to rebuild configuration for resume") {
            return AgentDeliveryResult(
                success: false,
                status: .failed,
                error: .deliveryFailed
            )
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
}
