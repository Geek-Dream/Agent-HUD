import Foundation

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum BoundedProcess {
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 3
    ) -> CommandResult? {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        var output = Data()
        var errorOutput = Data()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            return nil
        }

        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: output, as: UTF8.self),
            stderr: String(decoding: errorOutput, as: UTF8.self)
        )
    }
}

enum ProcessPresence {
    struct Snapshot {
        var codex = false
        var claude = false
    }

    static func detect() -> Snapshot {
        guard let result = BoundedProcess.run(
            executable: "/bin/ps",
            arguments: ["-axo", "comm=,args="],
            timeout: 2
        ), result.status == 0 else {
            return Snapshot()
        }

        var snapshot = Snapshot()
        for line in result.stdout.split(separator: "\n") {
            let value = line.lowercased()
            if value.contains("/codex") || value.hasPrefix("codex ") {
                snapshot.codex = true
            }
            if value.contains("/claude") || value.hasPrefix("claude ") || value.contains("claude-code") {
                snapshot.claude = true
            }
        }
        return snapshot
    }
}
