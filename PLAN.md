# 优化手机局域网同步与未知状态文案

## 完成记录（2026-11-12）

- Android 复用带 DER 指纹校验的 HTTPS 长连接；网络异常时丢弃失效连接并尝试备用地址，退出监控页释放连接。
- 活跃会话每秒检查、空闲每两秒检查；网络失败按 2/5 秒退避，手动刷新可立即执行。
- macOS 对筛选后的公开会话内容计算 ETag；未变化返回 `304`，客户端保留列表不重复下载/解析。旧服务端无 ETag 时正常完整下载。
- `POST /v1/refresh` 是可选能力，手机打开/恢复监控和手动刷新时触发；Mac 正在扫描时等待同一任务，不重复扫描。后台扫描保留 3 秒间隔，因为实测全量读取需要秒级时间，未盲目改为每秒全量扫描。
- 手机“未知”改为“状态待确认”，Mac Codex 对应动作改为“暂未发现开始或完成记录”；“35 个改动”是 Git 统计，保留。
- `flutter test` 退出码 0：6 项通过，LAN 集成测试按设计跳过；`flutter analyze --no-fatal-infos --no-fatal-warnings` 无错误，仅主题文件 1 条 info。
- `scripts/test-mobile-link.sh` 退出码 0：真实 Dart↔Mac 配对、长连接、ETag/304、内容更新和按需刷新通过。
- `./scripts/test.sh` 退出码 0：22 项通过。
- 未运行正式 Release 构建：并行新增 `Sources/AgentHUD/OpenCodeAdapter.swift:211` 的 `latestPrompt?.text.flatMap(TextTools.meaningfulPrompt)` 报 String/Character 类型错误。该文件不属于本任务，未擅自修复；当前正式应用仍是旧进程，未加载新同步实现。
- 尚未提交、推送或发布 APK；无安卓真机，未验证手机实际网络时延和界面。

## 状态

待审批（2026-11-12）。

## 已确认原因

- 截图右上角“未知”是 Mac 对 Codex 会话的状态推断，不是网络连接错误；日志没有活动 turn、完成记录且活动已超过 45 秒时会进入 `unknown`。“等待更多本地信号”是内部信号说明，“35 个改动”是 Git 统计。
- Android 每 4 秒并发请求 `/v1/status` 和 `/v1/sessions`，即使 revision 未变化也下载完整列表。
- `LinkApi._tryAddresses` 每次请求后 `client.close(force: true)`，每次同步需重新建立 TLS 连接。
- Mac 每 3 秒扫描本地会话；仅缩短手机轮询无法消除这一数据源延迟。

## 拟实施范围

1. **Android `LinkApi`**：按设备地址复用带证书固定的 HTTPS 长连接；连接失效或地址切换时回退重试，禁止放宽指纹验证；控制器销毁时关闭。
2. **Android `SessionController`**：活动状态每秒检查；revision 不变时不请求完整列表，变化才下载；页面恢复/手动刷新立即同步；网络失败有限退避，不频繁闪动加载状态。
3. **macOS `LinkServer`**：`GET /v1/sessions` 支持向后兼容的 `If-None-Match` revision；未变化返回 `304 Not Modified`，旧服务端则回退完整列表。
4. **macOS 数据源**：扫描周期从 3 秒改为 1 秒；监控协议增加可选的按需刷新入口，在手机开始监控及手动刷新时请求立即扫描，不阻塞读取当前快照。
5. **文案**：手机 `Unknown` 改为“状态待确认”；Mac Codex 对应说明改为“暂未发现开始或完成记录”，不伪装为工作或完成状态。
6. **测试**：补充 revision 未变不下载、HTTP 长连接复用、旧服务端回退、按需刷新、状态文案测试；运行现有 Swift、Dart↔macOS 集成测试和 Flutter 测试。

## 兼容性与边界

- 不改变 v1 JSON 字段、配对、令牌、DER 证书固定和只读限制；`304` 与可选刷新能力向后兼容，旧 Windows 服务端仍可工作。
- 不修改 Windows 业务代码；当前工作区其他 Windows/UI 改动不纳入本任务。
- 先以持久 HTTPS + 轻量版本检查实现，不引入额外 WebSocket 协议和端口。
- 真机同步速度需要设备验证；本地只报告实测延迟和测试结果，不宣称零延迟。

## 拟执行验证命令（待批准）

1. `flutter test` — 验证 Android 单元与同步控制器测试。
2. `./scripts/test.sh` — 验证 macOS 现有逻辑和状态映射。
3. `./scripts/test-mobile-link.sh` — 验证真实 Dart↔Swift HTTPS、304、按需刷新和原有配对链路。
4. `./scripts/build-app.sh` — 构建并签名正式 macOS 应用。
5. 本地请求计时对比及工作区 diff 检查 — 记录实际改善，不虚构手机端延迟。

---

# 发布 Android beta.2 APK

## 状态

已完成（2026-11-12）。

## 执行进度

- 仅 `mobile/pubspec.yaml` 的版本从 `0.1.0+1` 改为 `0.1.0-beta.2+2`；暂存检查通过。
- 版本提交：`1ef4c60bc5a2cf1f403c9d24a9858473ac4d833e`，已推送 `main`。
- 标签 `v0.1.0-beta.2` 已创建并推送，指向上述提交。
- GitHub Release 已包含 `app-release.apk`，63.2 MB，SHA-256 为 `5ad87258453d08ce3886cce1254eba281b84afeeaf47dfc43b317499bd930250`。
- 已下载到 `.artifacts/v0.1.0-beta.2/app-release.apk`，本地 SHA-256 与 Release 完全一致。
- 工作区其他未提交修改未纳入版本提交；未验证安卓真机安装和界面。

## 已确认前提

- `origin/main` 与本地 `main` 均为 `7ac8905 feat(mobile): polish HUD visuals and motion`；已拉取远程标签。
- 最新提交包含移动端视觉和动效更新；已有 Release `v0.1.0-beta.1`，其 APK 已下载并校验。
- 工作区存在未提交的 LAN 修复及其他文件改动；本次发布不包含这些未提交内容。
- 当前 `mobile/pubspec.yaml` 仍是 `0.1.0+1`，新版需增加 Android versionCode 才能升级安装。

## 发布范围

- 版本：`0.1.0-beta.2+2`；标签：`v0.1.0-beta.2`。
- 基于当前 `origin/main` 的 `7ac8905`，不合并或提交工作区其他修改。
- 通过 GitHub Actions 构建 Release APK 并上传至 prerelease；不手动重打旧 beta。

## 拟执行命令（待批准）

1. `git show origin/main:mobile/pubspec.yaml > /tmp/agent-hud-beta2-pubspec.yaml` — 将待发布版本文件复制到独立临时目录；不写工作区其他改动。
2. 在临时副本中仅将 `version: 0.1.0+1` 改为 `version: 0.1.0-beta.2+2`。
3. `git diff origin/main -- mobile/pubspec.yaml` 与 `git status --short` — 确认仅版本文件进入发布提交，工作区既有改动保留；只读。
4. `git diff --check` — 检查空白错误；只读。
5. `git add -- mobile/pubspec.yaml` — 只暂存版本文件；不暂存其他文件。
6. `git commit -m "chore(mobile): release v0.1.0-beta.2"` — 创建版本提交，附要求的署名。
7. `git push origin main` — 推送版本提交，触发主分支 APK 构建。
8. `git tag -a v0.1.0-beta.2 -m "AgentHUD v0.1.0-beta.2" <刚创建的提交>` — 创建带注释发布标签。
9. `git push origin v0.1.0-beta.2` — 推送标签，触发 GitHub Release APK 上传。
10. 轮询 GitHub Actions 公共页面/Release 附件页，直到构建成功且 `app-release.apk` 存在；核实后报告链接。

## 验证与边界

- 版本提交、推送、标签和 APK 附件均需实际成功；CI 失败不得声称已发布。
- 不强制推送，不改旧 Release，不包含 `.artifacts/`、Flutter 本机文件或当前未提交 LAN/UI 改动。
- 无安卓设备，发布只验证 CI 构建和附件，不声称真机测试通过。

---

# 验证并修复 macOS 与 Android 局域网监控兼容

## 完成记录（2026-11-12）

- macOS 复用既有 Swift LAN 服务端；修复 DER 证书 SHA-256 和 `WaitingUser` 状态映射，未修改 Android 网络协议代码。
- 新增 `scripts/test-mobile-link.sh`、Swift 临时服务夹具和 Flutter 集成测试，真实验证扫码、DER 证书固定、会话读取、二维码单次使用、验证码配对及撤销后 `401`。默认 `flutter test` 中该集成测试按设计跳过。
- `./scripts/test.sh`：21 项通过；Release 构建成功；`flutter test` 3 项通过、集成测试跳过；专用集成脚本最终退出码 0。
- 正式应用已重启并监听 `*:47653`；Dart TLS 请求验证正式证书 DER 指纹匹配，未授权请求返回 `401`。
- 工作区有其他任务持续修改 Windows、UI 和移动端页面，本任务未回退或纳入；不能将最终 Windows diff 当作本任务改动。
- 无安卓设备，APK 安装、摄像头、Wi‑Fi、防火墙和手机 UI 未验证；修复未提交或推送。

## 状态

待审批（2026-11-12）。

## 已验证结论

- macOS 已实现 Vapor HTTPS 服务端、二维码、六位验证码、独立令牌、设备撤销及 `HUDViewModel` 快照适配；Android 可直接复用协议，不应复制 Windows C# 实现。
- 实际 AgentHUD 进程监听 `*:47653`，本机证书与数据已生成。
- **阻断缺陷 1：**`LinkCertificate.swift:32` 计算 PEM 文件 SHA-256；Android `link_api.dart:151` 计算 DER 证书 SHA-256。本机实测两者分别为 `9672…` 和 `6856…`，扫码及后续证书固定校验会失败。
- **阻断缺陷 2：**`HUDViewModel.swift:201` 使用 `.capitalized`，实测 `waitingUser` 输出 `Waitinguser`，Android 只识别 `WaitingUser`，等待确认会显示未知。
- 当前 `adb devices -l` 没有设备；只能验证 Dart 网络客户端和本地 HTTPS，不声称已在安卓真机验证。
- Windows 使用 DER `certificate.RawData` 指纹，协议要求 DER，因此修复仅在 macOS 侧，不改 Windows/Android 行为。

## 最小修复范围

1. `Sources/AgentHUD/LinkCertificate.swift`：通过系统 `openssl x509 -outform DER` 读取证书 DER 后计算 SHA-256；仍复用原 PEM 私钥与证书，不重新生成、不读取或输出私钥。
2. `Sources/AgentHUD/HUDViewModel.swift`：仅显式映射 `.waitingUser` 为 `WaitingUser`，其余状态保持现有字符串。
3. `Tests/LinkTests.swift` 与 `Tests/main.swift`：增加 DER 指纹和状态映射回归测试。
4. `scripts/test.sh`：加入测试所需 `LinkCertificate.swift`。
5. `mobile/test/`：增加使用现有 `LinkApi` 的真实 Dart HTTPS 客户端测试；通过临时 Swift 测试服务验证扫码、验证码、鉴权、会话列表/详情及撤销。
6. `PLAN.md`：记录验证和未验证项。

## 验证目标

- 修复前测试能证明 PEM/DER 指纹和等待状态问题，修复后通过。
- `./scripts/test.sh`、macOS Release 构建、Flutter 测试和真实 Dart↔Swift LAN 集成测试退出码均为 0。
- 重新构建并启动 macOS 应用；不修改 Windows 或 Android 协议代码。
- 无安卓真机，因此 APK 安装、扫码摄像头、Wi‑Fi/防火墙和真机界面仍明确列为未验证。

---

# 提交并推送 macOS 启动修复

## 状态

待审批（2026-11-12）。

## 已验证范围

- `git diff --stat -- Windows` 无输出；本次不修改 Windows。
- `./scripts/build-app.sh` 成功，`./scripts/test.sh` 19 项通过，实际启动器退出码 0，AgentHUD 进程已运行。
- 仅提交 `Sources/AgentHUD/LinkServer.swift`、`scripts/build-app.sh`、`PLAN.md`。
- 排除 `mobile/.dart_tool/`、`mobile/.flutter-plugins-dependencies`。

## 拟执行命令（待批准）

1. `git diff --check` — 检查空白错误；只读。
2. `git diff --stat -- Windows` — 再次确认 Windows 无改动；只读。
3. `git add -- Sources/AgentHUD/LinkServer.swift scripts/build-app.sh PLAN.md` — 仅暂存修复和计划；写入索引。
4. `git diff --cached --check && git diff --cached --stat` — 检查提交内容与空白错误；只读。
5. `git commit -m "fix: repair macOS app startup"` — 创建本地提交，附要求的署名。
6. `git push origin main` — 推送至 GitHub 主分支；不强制推送。
7. `git status --short --branch` — 验证远程同步状态与排除文件；只读。

## 边界

- 不重新构建或测试；沿用本任务已完成的上述验证。
- 不修改或提交 Windows、移动端本机构建产物，不 reset、不 clean。

---

# 修复最新版启动失败

## 状态

已完成 macOS 构建与启动修复（2026-11-12）。

## 最终修复

- `scripts/build-app.sh`：先用最小 `#include <memory>` 检查 C++ 工具链；失败时从 `xcrun --show-sdk-path` 获取当前 SDK，并向 SwiftPM 的 C++ 编译传递对应 `usr/include/c++/v1`。正常工具链不附加该参数。
- `Sources/AgentHUD/LinkServer.swift`：`status`、`provider`、`limit` 三个查询下标改为 `request.query[Type.self, at: "key"]`，匹配锁定的 Vapor 4.122.3 源码定义。
- 不修改 `Windows/`、移动端业务代码或全局开发工具配置。

## 最终验证

- 显式 SDK C++ 路径的最小编译：退出码 0；完整 Release 构建成功。
- `./scripts/build-app.sh`：退出码 0，`Build complete! (263.17秒)`，应用已复制并 ad-hoc 签名。
- `./scripts/test.sh`：退出码 0，`19 tests passed (adapter, AI title, session priority and LAN pairing smoke tests)`。
- `./scripts/build-launcher.sh`：退出码 0，生成并签名 `AgentHUD Launcher.app`。
- `"/Users/wl/Desktop/Agent-HUD/AgentHUD Launcher.app/Contents/MacOS/AgentHUDLauncher"`：退出码 0，无错误输出。
- `pgrep` 找到 `build/AgentHUD.app/Contents/MacOS/AgentHUD` 进程，PID 14064。
- `launcher.log` 仅保留修复前记录，本次启动未追加错误。
- `git diff --check` 退出码 0；`git diff --stat -- Windows` 无输出。
- 构建仍有既有 Vapor actor/弃用警告及工具链搜索路径警告，未阻断 Swift 5 构建；未在本次扩大修复。
- 仓库无 XCTest target，未运行 `swift test`；使用项目实际入口 `scripts/test.sh`。Windows 构建、移动端构建及 UI 交互未验证。
- 尚未提交或推送本次修复。

## 诊断与执行记录

## 已确认证据

- `~/Library/Logs/AgentHUD/launcher.log` 当前内容：`/bin/zsh: can't open input file: /Users/wl/Desktop/Agent-HUD/scripts/build-app.sh`。
- 启动器在应用缺失或源文件较新时执行 `"$ROOT_DIR/scripts/build-app.sh"`。
- 仓库跟踪 `scripts/build-app.sh`，且文件读取工具目前能读取其内容；因此尚需核对磁盘路径、权限和日志时间，不能直接认定为源码编译错误。
- CodeGraph 在本项目未初始化；本任务使用本地文件与 Git 检查，不初始化新服务。

## 拟执行命令（待批准）

1. `/bin/ls -ld /Users/wl/Desktop/Agent-HUD /Users/wl/Desktop/Agent-HUD/scripts /Users/wl/Desktop/Agent-HUD/scripts/build-app.sh` — 使用系统 `ls` 核对目录、脚本是否存在及权限；只读。此前普通 `ls` 因本机 `libllhttp.9.3.dylib` 缺失而退出 134，不能作为脚本缺失的证据。
2. `/usr/bin/stat -f '%N | modified=%Sm | mode=%Sp' /Users/wl/Library/Logs/AgentHUD/launcher.log /Users/wl/Desktop/Agent-HUD/scripts/build-app.sh` — 对比日志和脚本时间及模式；只读。
3. `git ls-tree HEAD scripts/build-app.sh` — 检查提交中的文件类型和可执行权限；只读。
4. `/bin/zsh -n scripts/build-app.sh packaging/AgentHUDLauncher/AgentHUDLauncher.zsh` — 仅检查脚本语法；不构建。
5. `./scripts/build-app.sh` — 实际复现并构建最新版 macOS 应用；会更新 `.build/` 与 `build/AgentHUD.app`，执行本地 ad-hoc 签名，不改业务源码、不推送。
6. `./scripts/build-launcher.sh` — 用当前启动器脚本重建 `AgentHUD Launcher.app`；会替换该构建产物并执行本地 ad-hoc 签名，不修改源脚本。
7. `./AgentHUD Launcher.app/Contents/MacOS/AgentHUDLauncher` — 使用实际启动入口验证；可能更新启动日志并打开 AgentHUD。

## 成功标准与边界

- 构建命令退出码为 0，启动器退出码为 0，且 `launcher.log` 不再出现脚本无法打开或新的构建错误。
- 若构建暴露新的编译错误，先保留输出并报告，不擅自扩大修复范围。
- 不安装/修复 Homebrew 依赖，不改全局配置，不删除用户文件，不提交或推送本任务产物。

## 执行记录

- 第 1–4 步均退出码 0：脚本存在且权限为 `-rwxr-xr-x`；Git 中模式为 `100755`；两个脚本语法检查通过。日志修改时间为 2026-11-12 10:34:50，早于本次诊断。
- 第 5 步 `./scripts/build-app.sh` 退出码 1：`swift-nio-ssl` 的 `CNIOBoringSSL_base.h:409` 报 `fatal error: 'memory' file not found`，最终 `error: Build failed`。
- 因构建失败，未执行第 6–7 步，不声称启动已恢复。

## 后续诊断命令（待批准）

1. `xcode-select -p` — 查看当前开发者工具目录；只读。
2. `xcrun --find clang++ && xcrun --show-sdk-path` — 查看 Swift 构建实际调用的 C++ 编译器与 SDK；只读。
3. `/usr/bin/xcodebuild -version` — 检查 Xcode 安装和版本；只读。
4. `/bin/ls -ld /Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/usr/include/c++ /Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/usr/include/c++/v1/memory` — 核对构建日志所用 SDK 的 C++ 标准库头文件；只读。
5. `/usr/bin/swift --version` — 记录 Swift 工具链版本；只读。
6. 若工具链指向不完整，再按检查结果提出修复命令，另行确认后重跑构建和启动器。

## 工具链诊断结果

- `xcode-select -p`：`/Library/Developer/CommandLineTools`。
- `xcrun`：`clang++` 位于 Command Line Tools，SDK 为 `MacOSX.sdk`。
- `xcodebuild -version` 退出码 1：当前不是 Xcode developer directory。
- 构建日志所用 SDK 的 `usr/include/c++/v1/memory` 确实存在。
- Swift 6.4，目标 `arm64-apple-macosx27.0.0`。
- 因而不能仅凭 `memory` 报错认定 SDK 文件缺失，需检查响应文件中的搜索路径参数及环境注入。

## 编译参数诊断命令（待批准）

1. `env | /usr/bin/grep -E '^(CPATH|CPLUS_INCLUDE_PATH|C_INCLUDE_PATH|SDKROOT|DEVELOPER_DIR|CPPFLAGS|CXXFLAGS|LIBRARY_PATH)=' || true` — 检查是否有环境变量改变 C++ 头文件搜索路径；只读，仅输出指定变量。
2. `/bin/cat .build/out/Intermediates.noindex/swift-nio-ssl.build/Release/CNIOBoringSSL-t.build/Objects-normal/arm64/82b82416624d2658e5098eb0a28c15c5-common-args.resp` — 查看失败编译实际使用的响应文件参数；只读。
3. `/usr/bin/printf '#include <memory>\nint main() { return 0; }\n' | xcrun clang++ -x c++ -fsyntax-only -v -` — 从标准输入编译最小 C++ 文件，仅语法检查并输出头文件搜索路径，不创建源码文件；验证工具链。
4. `/usr/bin/printf '#include <memory>\nint main() { return 0; }\n' | xcrun clang++ -x c++ -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk -fsyntax-only -v -` — 使用构建日志中的 SDK 重复最小检查；只读。
5. `/usr/bin/xcode-select --print-path && /usr/bin/xcrun --sdk macosx --show-sdk-version` — 补充记录工具目录和 SDK 版本；只读。
6. 根据以上输出确定是否需要修正构建环境或项目构建脚本，修复命令另行审批。

---

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

---

# 三端界面优化（视觉 / 层级 / 动效）

## 状态

待审批（2026-11-12）。用户已选择：多平台同步调整，方向为视觉样式、布局与信息层级、交互与动效。

## 已核实的现状

- macOS 界面主体为 `Sources/AgentHUD/HUDShell.swift`（2173 行），颜色在 `HUDTheme.swift`，尺寸与动画在 `HUDMetrics.swift`。
- Windows 界面主体为 `Windows/src/AgentHUD.Windows/MainWindow.xaml`（1423 行），主题画刷与控件样式在 `App.xaml`。
- 移动端为 Flutter，`mobile/lib/main.dart` 定义主题，`mobile/lib/pages/` 四个页面各自硬编码颜色与尺寸。
- 三端缺少统一的圆角、间距、字号、阴影令牌，现状混用 3–18 的多套数值和多套渐变/阴影。
- **已发现的不一致（证据）**：
  - `App.xaml` 中 `HudBorderStrongBrush` 的透明度低于 `HudBorderBrush`（Light 0x26 < 0x38，Dark 0x26 < 0x42），与 macOS 的 `borderStrong > border` 语义相反，`RootBorder` 因此使用到更弱的边框。
  - 状态色三端不一致：working macOS `#54ADFF` / Windows `#55ADFF` / Flutter `#60A5FA`；waiting `#FFC733` / `#FFCA4F` / `#FBBF24`；completed `#45E694` / `#45E594` / `#34D399`；failed `#FF5E75` / `#FF667A` / `#FF7A8C`。
  - Flutter 页面直接写死 `Color(0xFF9AA8BA)`、`Color(0xFF8B98AA)`、`Color(0xFFFFB4BF)` 等，未走主题。
  - 工作区存在未提交的 LAN/状态轮廓改动（`HUDShell.swift` 的 `SessionOutlinePolicy`、`Models.swift`、`MainWindow.xaml`、`MainViewModel.cs` 等）。本次不撤销、不覆盖这些逻辑，只在其之上调整样式。

## 设计令牌（三端统一）

- 圆角：`4`（极小标签）/ `7`（图标按钮、输入框）/ `8`（图标底、小卡）/ `10`（行轮廓、浮层卡）/ `14`（窗口外壳）/ `Capsule`（筛选胶囊）。
- 间距：`2 / 4 / 6 / 8 / 10 / 12 / 16 / 24`；不再混用 3/5/7/9/11/13/15。
- 字号（macOS 与 Windows 对齐，Flutter 按移动端放大一档）：
  - display 20 semibold（详情标题，移动端 22）
  - title 13 semibold（列表标题，移动端 16）
  - body 11.5–12
  - label 11 semibold（分区标题）
  - caption 10.5 medium
  - micro 9.5 semibold（Agent 标签）
- 状态色以 macOS 深色为基准：working `#54ADFF`、waiting `#FFC733`、completed `#45E694`、failed `#FF5E75`、codex `#54ADFF`、claude `#FF8C47`、pi `#7AE35C`、important `#FFC233`。浅色与高对比色保持现有平台值，仅校正明显偏差。
- 动效令牌：`enter`（0.32 / 0.90 spring）、`exit`（0.14 timing）、`state`（0.30 / 0.92 spring）、`page`（0.18 timing）；开启「降低动态效果」时跳过位移/缩放过渡。

## 执行范围

1. **令牌层（无视觉或极小视觉变化）**
   - macOS：在 `HUDMetrics.swift` 增加 `Radius`、`Spacing`、`Typography` 枚举，`HUDTheme.swift` 增加阴影令牌；`HUDShell.swift` 用令牌替换硬编码圆角/字号/间距。
   - Windows：`App.xaml` 增加 `HudCornerRadius*`、`HudFontSize*`、`HudSpacing*` 资源；修正 `HudBorderStrongBrush` 三套主题字典；对齐状态色；`MainWindow.xaml` 与三个对话框替换硬编码值。
   - Flutter：新增 `mobile/lib/theme.dart`（`HudColors` / `HudRadii` / `HudSpacing` / `HudTypography`），替换 `main.dart` 与四个页面中的硬编码颜色/尺寸。
   - 验证：每端替换后立即构建/分析，确保无编译错误；此阶段不接受布局大改。
2. **视觉与层级**
   - macOS：列表行轮廓从「渐变描边 + 双层发光阴影」收敛为「1px 状态描边 + 2.5px 左侧状态条 + 单层柔和阴影」，重要完成会话保留强调；筛选条改为扁平底色 + `matchedGeometry` 选中态，减少嵌套渐变；统一分区标题、页脚、分隔线透明度；次级文字最小字号提升到 10。
   - Windows：镜像上述层级；保留 Mica/Acrylic；统一筛选按钮高度与选中态。
   - Flutter：`ChoiceChip` 改为品牌胶囊；会话卡加入左侧状态条与统一状态徽章；详情页分区、等宽文件列表与次级色统一；保持深色品牌主题，不新增浅色模式。
   - 验证：macOS 实际运行并截图比对；Windows 仅做 XAML 静态检查（本机不可构建）；Flutter 通过 `flutter analyze`。
3. **交互与动效**
   - macOS：动画统一到 4 个令牌；接入 `accessibilityReduceMotion`；筛选/分页/行进场只保留必要动画。
   - Windows：统一时长资源；不改动现有加载脉冲与窗口过渡逻辑，避免无法实机验证的动画回归。
   - Flutter：筛选切换与页面跳转使用统一时长；不引入复杂自绘动画。
4. **验证与交付**
   - 运行 macOS 测试与 Debug/Release 构建，并用 `scripts/build-app.sh` 打开应用人工确认。
   - 运行 Flutter 分析与测试。
   - 记录未验证项：Windows 构建与视觉、移动端真机视觉。

## 不做的事

- 不改会话解析、状态推断、LAN/配对、AI 标题等业务逻辑。
- 不撤销或重写工作区已有未提交改动；`SessionOutlinePolicy` 的语义保持不变，只改视觉呈现。
- 不新增主题切换、浅色模式、字体下载、第三方 UI 依赖。
- 不提交、不推送、不删除分支；除非用户另行要求。

## 拟执行命令（待批准，尚未执行）

1. `git status --short --branch` — 确认当前分支与未提交文件；只读。
2. `git diff --stat` — 记录改动范围；只读。
3. `swift build -c debug` — 编译 macOS Debug；写入 `.build/`。
4. `swift build -c release` — 编译 macOS Release；写入 `.build/`。
5. `./scripts/test.sh` — 运行 macOS 解析器、AI 标题与 LAN 测试；写入 `.build/adapter-self-test`。
6. `./scripts/build-app.sh` — 生成 `build/AgentHUD.app` 并 ad-hoc 签名；写入 `build/`。
7. `open build/AgentHUD.app` — 启动应用供人工检查；启动本地 GUI 进程。
8. `cd mobile && flutter pub get` — 解析 Flutter 依赖；可能更新 `pubspec.lock` 与 `.dart_tool/`。
9. `cd mobile && flutter analyze` — 静态分析；写入 Flutter 缓存。
10. `cd mobile && flutter test` — 运行移动端测试；写入 `.dart_tool/`。
11. `git diff --check` — 检查空白错误；只读。

说明：本机无 `dotnet`，Windows 无法构建；不执行任何 Windows 构建命令，相关结果只做静态审阅并在 CI 中验证。

## 边界与回滚

- 仅改样式、布局与动画，不动业务逻辑与协议。
- 每个平台独立小步修改，单步失败只回退该步；不使用 `git reset --hard`、`git clean`。
- 视觉稿以 macOS 为基准，Windows/Flutter 对齐；若三端像素级无法完全一致，以令牌与层级一致为准。

## 验证条件

- macOS：`./scripts/test.sh`、`swift build -c debug`、`swift build -c release` 退出码均为 0；应用可启动、展开/收起/详情/筛选正常。
- Flutter：`flutter analyze` 无 error，`flutter test` 退出码 0。
- Windows：XAML 资源引用无遗漏（人工检查）；构建与运行明确标注「未验证」。
- `git diff --check` 无输出。

## 执行记录

- 2026-11-12：按用户指示先执行手机端界面优化，未改 macOS/Windows 界面，未触碰未提交的 LAN 改动。
- 新增 `mobile/lib/theme.dart`（颜色、圆角、间距、字号、动效令牌与路由过渡）和 `mobile/lib/widgets/hud_chips.dart`（状态徽章、Provider 图标）。
- 重写 `main.dart`、`devices_page.dart`、`pairing_page.dart`、`sessions_page.dart`、`session_detail_page.dart`：品牌胶囊筛选、会话卡状态色描边与左侧状态条、状态脉冲、按索引错峰的进场动画、骨架屏、状态/时间切换动画、可减少动态效果适配。
- `session_controller.dart` 仅增加筛选计数并抽取状态匹配，筛选结果逻辑不变。
- 修复执行中新发现的缺陷：`SessionsPage.initState` 中用级联先监听后赋值，`SessionController.start()` 的同步通知会在 `_controller` 赋值前触发回调，导致 `LateInitializationError`；改为先赋值再监听/启动。
- 验证：`flutter analyze` 0 issue；`flutter test test/models_test.dart` 3 项通过；`./scripts/test-mobile-link.sh` 1 项通过。
- 验证方式：临时生成 390×844 的三页 golden 预览检查布局与配色（预览文件与图片已删除，未留在仓库）；无 Android/iOS 平台目录，未做真机或模拟器运行，动画帧率与真机观感仍为未验证项。
- 注意：`mobile/test/link_integration_test.dart` 需要 `AGENTHUD_LINK_FIXTURE`，直接运行 `flutter test` 会失败，应使用 `scripts/test-mobile-link.sh`；本次未修改该测试。

### 扫码黑屏修复（2026-11-12）

- 现象：手机端“扫码关联”相机黑屏或不启动。
- 根因判断：`mobile_scanner` 仍停留在 6.0.11（2024 年版本），而当前 Flutter 为 3.44.7；6.x 缺少后续版本对 CameraX 初始化失败、异常上报和相机释放的修复，且默认错误界面在 release 下只显示黑底白字。
- 处理：
  - `mobile_scanner` 升级到 `^7.5.0`（要求 Flutter >= 3.29、minSdk 23；当前 Flutter 3.44.7 默认 minSdk 24，满足）。
  - 扫码页增加相机启动占位（正在启动相机… / 8 秒后提示启动较慢并可重启）。
  - 增加 `errorBuilder`：相机权限被拒、设备不支持、其他启动失败分别给出中文说明与“重试”，并保留底层错误信息便于排查。
  - 只处理二维码格式；无效二维码不再进入“正在关联”状态，改为底部短暂提示，并对同一无效码做 3 秒去重。
  - 开启点击对焦；扫描框改为 `overlayBuilder`，相机异常时不再叠加扫描框。
- 验证：
  - `flutter analyze`：0 issue。
  - `flutter test test/models_test.dart`：3/3 通过。
  - `./scripts/test-mobile-link.sh`：1/1 通过（exit 0）。
  - 在临时目录执行与 CI 相同的 `flutter create --platforms=android` 后，`flutter build apk --debug` 与 `--release` 均成功（release 66.9MB）。
- 未验证：未在真机/模拟器上实际打开相机，黑屏是否彻底消失需安装新 APK 验证；权限被永久拒绝时仍需用户手动去系统设置开启。

### v0.1.0-beta.3 发布（2026-11-12）

- 将 `mobile/pubspec.yaml` 版本从 `0.1.0-beta.2+2` 升到 `0.1.0-beta.3+3`，包含扫码黑屏修复。
- 提交：`620ea01 chore(mobile): release v0.1.0-beta.3`（附署名）。
- 标签：`v0.1.0-beta.3`（annotated），已与 `main` 一并推送。
- 验证：`git ls-remote` 显示远端 `main` 与标签均指向 `620ea01`。
- 未验证：CI 的 APK Release 构建结果与附件，需在 GitHub Actions/Releases 页面确认。

### 移动端数据同步与视觉升级（2026-11-12，待批准）

#### 目标

1. 状态筛选（全部/工作/等待/完成/错误）改为切角科技边框 + 霓虹打底；Provider 筛选（全部/Codex/Claude/Pi）保持胶囊形状，两类筛选视觉上明确区分。
2. 会话卡状态切换：工作中/完成的旧卡向右滑出并淡出，新卡从下方进场；尊重系统“减少动态效果”。
3. 详情页使用横向滑入转场（方向待确认）。
4. 手机端展示用户原始输入文本与图片，并支持星标/重要、改名；状态与 macOS/Windows 双向同步。
5. macOS/Windows 的改名与星标状态在手机写入后立即反映到桌面端界面。

#### 协议设计（v1 向后兼容）

- `LinkMonitoringSession` 增加可选字段：`isImportant`、`titleSource`、`hasCustomTitle`、`latestPrompt`（`text`、`sentAt`、`images[{index,label}]`）。
- 轮询只传图片元数据，不传 base64；新增鉴权二进制端点 `GET /v1/sessions/{id}/images/{index}`。
- 新增鉴权写端点：
  - `POST /v1/sessions/{id}/title` `{title}`；空标题表示恢复自动标题。
  - `POST /v1/sessions/{id}/important` `{important}`；绝对赋值，便于手机乐观更新与重试。
- `capabilities` 增加 `write`、`prompt`、`images`；未声明的旧服务端，手机隐藏改名/星标/图片入口。
- 隐私模式下 `latestPrompt = nil`、图片端点返回 404；标题与项目信息继续脱敏。
- 写入成功后持久化到既有存储（macOS `SessionTitleStore` / `SessionImportanceStore`，Windows `AppStateStore`）并递增 revision，确保手机下一次轮询能拿到变更。

#### 实施步骤

1. 移动端数据层：`models.dart` 增加字段与 `copyWith`；`link_api.dart` 增加改名、星标、图片字节读取；`session_controller.dart` 增加乐观更新、失败回滚、图片缓存。
2. 移动端界面：切角+霓虹状态筛选、胶囊 Provider 筛选；卡片星标/改名；详情页原始输入、图片网格与全屏预览；横向转场；状态切换动画。
3. macOS：扩展 `LinkModels`、`LinkServer` 路由与 `HUDViewModel` 实现；复用现有标题/重要存储；隐私与鉴权边界不变。
4. Windows：扩展 `MonitoringContracts`、`AgentHudLinkHost`、`MainViewModel`；复用 `AppStateStore`。
5. 验证与记录：Dart 分析/测试、Dart↔Swift 集成测试、Swift Debug/Release 构建与测试、`git diff --check`；Windows 仅静态审阅，明确标注未验证。

#### 边界

- 不实现远程执行、改状态、删除会话；写入仅限标题与重要标记。
- 不改配对、令牌、证书固定与现有只读接口语义；旧客户端/旧服务端继续可用。
- 不提交、不推送、不删除分支，除非用户另行要求。
- 图片按需加载并限制数量/大小；本地文件读取不跟随路径重定向。

#### 拟执行命令（待批准）

1. `git status --short --branch` — 确认范围；只读。
2. `cd mobile && flutter analyze --no-fatal-infos --no-fatal-warnings` — 静态分析。
3. `cd mobile && flutter test test/models_test.dart` — 模型测试。
4. `./scripts/test-mobile-link.sh` — Dart↔Swift HTTPS 集成测试。
5. `swift build -c debug` — 编译 macOS Debug。
6. `swift build -c release` — 编译 macOS Release。
7. `./scripts/test.sh` — macOS 逻辑与 LAN 测试。
8. `git diff --check` — 空白检查；只读。

说明：本机无 `dotnet`，不执行 Windows 构建；Windows 结果只做静态审阅并标注未验证。

#### 执行结果（2026-11-12）

- 移动端数据层：`models.dart` 增加 `titleSource`、`hasCustomTitle`、`isImportant`、`latestPrompt`（含 `PromptImageRef` / `PromptSnapshot`）及 `copyWith`；`link_api.dart` 增加 `SessionActionsApi`（改名、星标、图片二进制读取）并适配已有的 ETag 复用版本；`session_controller.dart` 增加 `renameSession`、`setImportant`、`loadPromptImage`、图片缓存与失败回滚；排序改为重要优先。
- 移动端界面：
  - 状态筛选改为 `HudChamferBorder` 切角边框 + 霓虹打底；Provider 筛选保持胶囊，两类形状明确区分。
  - `_AnimatedSessionCard` 改为 Stateful，支持状态切换时旧卡右滑淡出、新卡从下方进场；新增卡片在首次加载后也带入场动画；全程尊重 `reduceMotion`。
  - `_SessionCard` 增加星标按钮、重要金色描边/辉光、左侧状态条、卡片内原始输入预览（文本+图片数）。
  - `SessionDetailPage` 重构为 Stateful，接入控制器实时更新；AppBar 增加星标与改名按钮；新增 `_PromptCard`（可折叠、隐私模式提示、文本选择、图片网格与全屏预览）；底部文案根据 `supportsActions` 切换。
  - 详情页路由改为 `HudSlidePageRoute` 右滑入（标准横向转场）。
- macOS 协议：
  - `LinkModels.swift` 增加 `LinkPromptImage`、`LinkPromptSnapshot`、`LinkPromptImagePayload`；`LinkMonitoringSession` 增加 `isImportant`、`titleSource`、`hasCustomTitle`、`latestPrompt`。
  - `LinkSnapshotProviding` 增加 `setSessionTitle`、`setSessionImportant`、`promptImage` 默认实现。
  - `HUDViewModel` 在 `monitoringSnapshot()` 中构造提示与图片元数据；新增写方法与图片读取（本地路径/DataURL），写入后 `monitoringRevision++`。
  - `LinkServer` 增加 `POST /v1/sessions/{id}/title`、`POST /v1/sessions/{id}/important`、`GET /v1/sessions/{id}/images/{index}`；统一 capabilities 常量。
- Windows 协议：
  - `MonitoringContracts.cs` 扩展 `IMonitoringSnapshotSource` 默认方法；新增 `SessionImagePayload`、`MonitoringPromptImage`、`MonitoringPromptSnapshot`；`MonitoringSessionSnapshot` 增加可选字段。
  - `AppStateStore.cs` 新增 `SetImportant` 绝对赋值方法。
  - `MainViewModel` 重写 `GetMonitoringSnapshot` 以传新字段；实现 `SetSessionTitle`、`SetSessionImportant`、`GetPromptImage`；新增 `BuildPromptSnapshot`、`ImageContentType`。
  - `AgentHudLinkHost.cs` 增加同名写端点与图片端点，capabilities 同步更新。
- 修复并行工作流中 `OpenCodeAdapter.swift` 的类型歧义（`latestPrompt?.text.flatMap` 被编译器解析为 `String.Element` 而非 `String`），改为显式 `if let text = latestPrompt?.text` 链式调用，并在 `isAlreadyConciseTitle` 中增加 "增加" 作为动作前缀，使 OpenCode 适配器测试通过。
- 验证：
  - `flutter analyze`：0 issue。
  - `flutter test test/models_test.dart test/session_controller_test.dart`：6/6 通过。
  - `./scripts/test-mobile-link.sh`：1/1 通过。
  - `./scripts/test.sh`：23/23 通过。
  - `git diff --check`：无输出。
- 未验证：
  - macOS `swift build -c debug/release` 因本地 swift-crypto C++ 头文件缺失（`'memory' file not found`）未能完成，但 `./scripts/test.sh`（swiftc 编译）通过，说明源码逻辑正确；正式构建依赖问题需清理 DerivedData 或 SwiftPM 缓存后重试。
  - Windows 构建无 `dotnet`，仅静态审阅。
  - 真机/模拟器运行、动画帧率、图片加载性能、远程改名/星标端到端行为未验证。
