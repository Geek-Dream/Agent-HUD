import Foundation

enum GitReader {
    static func read(projectPath: String) -> GitContext? {
        // 先单独取仓库根：这是唯一必须成功的一步。
        // 注意不能与 --abbrev-ref HEAD 合并成一次调用：空仓库（还没有任何 commit）
        // 时 HEAD 无法解析，合并后整条命令 exit 128，会把本来有效的仓库判定为失败。
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

        // 分支名从 status --branch 的 "# branch.head" 行读取，省掉单独的
        // branch --show-current 调用；空仓库时该行缺失，回退为 detached。
        let statusResult = BoundedProcess.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoRoot, "status", "--porcelain=v2", "--branch"],
            timeout: 2
        )
        let statusLines = statusResult?.stdout.split(separator: "\n") ?? []

        var branch = "detached"
        var changedFiles = 0
        for line in statusLines {
            if line.hasPrefix("# branch.head ") {
                let name = line.dropFirst("# branch.head ".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != "(detached)" {
                    branch = name
                }
            } else if !line.hasPrefix("#") && !line.isEmpty {
                changedFiles += 1
            }
        }

        var insertions = 0
        var deletions = 0
        // diff HEAD 等价于原先的 diff + diff --cached 两次调用之和。
        // 空仓库时 HEAD 不存在，命令失败，增删数保持 0。
        if let diffResult = BoundedProcess.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoRoot, "diff", "HEAD", "--numstat"],
            timeout: 2
        ), diffResult.status == 0 {
            for line in diffResult.stdout.split(separator: "\n") {
                let fields = line.split(separator: "\t")
                guard fields.count >= 2 else { continue }
                insertions += Int(fields[0]) ?? 0
                deletions += Int(fields[1]) ?? 0
            }
        }

        return GitContext(
            repoRoot: repoRoot,
            branch: branch,
            changedFiles: changedFiles,
            insertions: insertions,
            deletions: deletions,
            isDirty: changedFiles > 0
        )
    }
}
