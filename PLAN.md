# 提交并推送当前改动

## 状态

待审批（2026-11-12）。

## 提交范围

- 已修改：`Sources/AgentHUD/LinkPairingManager.swift`、`scripts/test.sh`。
- 未跟踪：`PLAN.md`、`Package.resolved`、`mobile/pubspec.lock`。
- 明确排除本机 Flutter 生成目录/文件：`mobile/.dart_tool/`、`mobile/.flutter-plugins-dependencies`；不修改 `.gitignore`，不提交它们。

## 拟执行命令（待批准）

1. `git diff --check` — 检查已跟踪改动中的空白错误；只读。
2. `git diff -- Sources/AgentHUD/LinkPairingManager.swift scripts/test.sh` — 审查源码与脚本实际改动；只读。
3. `git add -- Sources/AgentHUD/LinkPairingManager.swift scripts/test.sh PLAN.md Package.resolved mobile/pubspec.lock` — 仅暂存上述文件，不包含 Flutter 本机构建产物；写入 Git 索引。
4. `git diff --cached --check` — 检查全部待提交内容的空白错误；只读。
5. `git diff --cached --stat` — 核对提交文件及规模；只读。
6. `git commit -m "fix: stabilize LAN tests and builds"` — 创建本地提交，附会话要求的署名；不自动提交排除项。
7. `git push origin main` — 推送提交到远程主分支；远程写入，不强制推送。
8. `git status --short --branch` — 验证推送结果及保留的未跟踪构建产物；只读。

## 验证与边界

- 提交和推送命令必须退出码为 0；失败则报告真实输出，不声称完成。
- 不提交 `.dart_tool`、`.flutter-plugins-dependencies`，不 reset、不 clean、不修改业务代码。
- 本次运行 Git 自带 diff 检查，不重复运行此前未完成的构建和测试；交付时明确列为未验证项。

---

# 合并全部远程分支并推送 main

## 状态

已完成（2026-11-12）。

## 执行记录

- `git status --short --branch`：退出码 0；位于 `main`，既有工作区改动保留。
- `git fetch origin --prune`：退出码 0，无输出。
- 实际远程分支清单：`origin/feat/lan-monitoring`、`origin/main`、`origin/ui-optimization-test`。
- `git merge --no-edit origin/feat/lan-monitoring`：退出码 0，`Already up to date.`。
- `git merge --no-edit origin/ui-optimization-test`：退出码 0，`Already up to date.`。
- `git branch -r --no-merged main`：退出码 0，无输出；全部远程分支均已并入本地 `main`。
- `git push origin main`：退出码 0，`Everything up-to-date`；无需新推送。
- 最终状态为 `main...origin/main`，无 ahead/behind；原有已修改及未跟踪文件列表不变。
- 未运行构建或测试，未提交工作区改动。

---

# 拉取并合并远程 main 到本地

## 状态

## 拟执行命令（待批准）

1. `git status --short --branch` — 确认当前分支和现有工作区改动；只读。
2. `git fetch origin --prune` — 拉取全部远程分支并移除已失效的远程跟踪引用；涉及网络和本地 `.git` 更新。
3. `git for-each-ref --format='%(refname:short)' refs/remotes/origin` — 列出实际远程分支，确定合并清单；只读。
4. 对第 3 步列出的每个分支（排除 `origin/HEAD`、`origin/main`）逐一执行 `git merge --no-edit origin/<分支名>` — 合并到当前本地 `main`；可能修改工作区并创建本地合并提交，遇错即停。
5. `git branch -r --no-merged main` — 检查是否仍有未并入本地 `main` 的远程分支；只读，必须无遗漏才继续。
6. `git push origin main` — 将全部合并结果推送到远程主分支；涉及远程写入，不强制推送。
7. `git status --short --branch` — 验证推送后的分支同步状态与本地改动；只读。

## 边界与验证

- 不 rebase、不 reset、不 clean、不强制推送、不删除任何分支。
- 不运行项目构建或测试；本任务的验证目标是远程分支全部成为本地 `main` 的祖先，且推送后本地与 `origin/main` 同步。
- 若第 5 步仍有未合并分支，不执行推送。

---

# 拉取并合并远程 main 到本地

## 状态

已完成（2026-11-12）。

## 执行记录

- `git status --short --branch`：退出码 0；当前为 `main...origin/main`，存在既有已修改及未跟踪文件。
- `git fetch origin`：退出码 0，无输出。
- `git merge --no-edit origin/main`：退出码 0，输出 `Already up to date.`。
- 合并后 `git status --short --branch`：退出码 0；仍为 `main...origin/main`，未显示 ahead/behind，原有工作区改动列表保持不变。
- 未执行构建或测试；本次仅同步 Git 引用与分支。

---

# 合并后验证与测试入口修复

## 状态

## 目标与范围

1. 使用 GitHub CLI 获取远程更新，将 `origin/main` 合并到当前本地 `main`，保留现有未提交改动。
2. 若 Git 因工作区改动可能覆盖而拒绝合并，停止并报告，不自动 stash、提交或丢弃改动。
3. 若有冲突，保留冲突现场并报告，不擅自选择业务代码版本。
4. 合并后检查分支同步状态和工作区，确认本地未提交改动仍在。

## 拟执行命令（待批准）

1. `git status --short --branch` — 合并前确认当前分支、远程跟踪关系和未提交改动；只读。
2. `git fetch origin` — 从 `origin` 拉取远程引用；涉及网络和本地 `.git` 更新，不改业务文件。
3. `git merge --no-edit origin/main` — 将远程 `main` 合并到当前本地 `main`；可能写入工作区及创建本地合并提交，不推送远程。
4. `git status --short --branch` — 检查合并后的同步状态和未提交改动；只读。

## 边界与回滚

- 不 rebase、不强制合并、不重置、不清理未跟踪文件、不推送。
- 若产生不希望的合并提交，可在用户另行确认后用 `git merge --abort`（仅冲突中）或 `git reset --keep <合并前提交>` 回退；本任务不预先执行。
- 本任务仅同步代码，不运行项目构建或测试。

## 验证条件

- `git merge` 退出码为 0，或明确报告冲突/本地改动阻断；已是最新时以状态检查确认同步。
- `git status --short --branch` 显示本地与 `origin/main` 的实际关系，原有未提交文件未被丢弃。

---

# 合并后验证与测试入口修复

## 状态

执行中（2026-11-12）。

## 已确认前提

- `origin/feat/lan-monitoring` 与 `origin/ui-optimization-test` 均是当前 `main` 的祖先，两个分支已完整合并，无需重复创建合并提交。
- `./scripts/test.sh` 编译失败：`Tests/main.swift` 调用了 `testLinkPairing()`，但测试入口未编译其定义和相关 LAN 类型。
- 首次 `swift build -c debug` 在下载 `swift-nio` 时因 GitHub HTTPS 连接失败而中止。
- 本机可用 Swift、Flutter；无 `dotnet`、无 `gh` CLI。

## 执行范围

1. 修改 `scripts/test.sh`，仅加入 LAN 测试所需的 `LinkModels.swift`、`LinkDeviceStore.swift`、`LinkPairingManager.swift`、`Tests/LinkTests.swift`。
   - 验证：`./scripts/test.sh` 退出码为 0。
2. 补全 LAN 测试后暴露出 `LinkPairingManager` 跨 actor 调用缺少 `await` 的既有编译错误。
   - 最小修复：将 `completeQr`、`completeCode` 标为 `async`，并对 `devices.issueToken` 使用 `await`，与服务端现有 `try await` 调用保持一致。
3. 运行 `swift build -c debug` 与 `swift build -c release`。
   - 如直连下载仍失败，仅为相关命令临时使用仓库已有 remote 所采用的 `https://ghproxy.net/https://github.com/` 代理，不修改全局 Git 配置。
   - 验证：两个构建退出码均为 0。
3. 在 `mobile/` 运行 `flutter pub get` 与 `flutter test`。
   - 影响：下载 Flutter/Dart 依赖；若生成或更新锁文件，保留并检查变更。
   - 验证：测试退出码为 0。
4. 检查最终 Git diff，记录验证结果和未验证项。

## 边界

- 不改业务逻辑，不处理与本任务无关的问题。
- 不提交、不推送、不删除远端分支。
- 不在 macOS 上声称 WinUI 构建或 Windows 运行验证通过。

## 执行记录

- 2026-11-12：完成分支祖先校验，开始按用户批准的范围执行。
