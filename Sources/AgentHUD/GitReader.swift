import Foundation

enum GitReader {
    static func read(projectPath: String) -> GitContext? {
        let rootResult = BoundedProcess.run(
            executable: "/usr/bin/git",
            arguments: ["-C", projectPath, "rev-parse", "--show-toplevel"],
            timeout: 1.5
        )
        guard let rootResult, rootResult.status == 0 else {
            return nil
        }

        let repoRoot = rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoRoot.isEmpty else {
            return nil
        }

        let branchResult = BoundedProcess.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoRoot, "branch", "--show-current"],
            timeout: 1.5
        )
        var branch = branchResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if branch.isEmpty {
            let headResult = BoundedProcess.run(
                executable: "/usr/bin/git",
                arguments: ["-C", repoRoot, "rev-parse", "--abbrev-ref", "HEAD"],
                timeout: 1.5
            )
            branch = headResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "detached"
        }

        let statusResult = BoundedProcess.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoRoot, "status", "--porcelain=v2", "--branch"],
            timeout: 2
        )
        let changedLines = statusResult?.stdout
            .split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty } ?? []

        var insertions = 0
        var deletions = 0
        for arguments in [
            ["-C", repoRoot, "diff", "--numstat"],
            ["-C", repoRoot, "diff", "--cached", "--numstat"]
        ] {
            guard let result = BoundedProcess.run(
                executable: "/usr/bin/git",
                arguments: arguments,
                timeout: 2
            ) else {
                continue
            }
            for line in result.stdout.split(separator: "\n") {
                let fields = line.split(separator: "\t")
                guard fields.count >= 2 else { continue }
                insertions += Int(fields[0]) ?? 0
                deletions += Int(fields[1]) ?? 0
            }
        }

        return GitContext(
            repoRoot: repoRoot,
            branch: branch.isEmpty ? "detached" : branch,
            changedFiles: changedLines.count,
            insertions: insertions,
            deletions: deletions,
            isDirty: !changedLines.isEmpty
        )
    }
}
