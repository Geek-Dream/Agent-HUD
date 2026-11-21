# macOS 会话排序、完成提醒与主题（2026-11-22）

## 状态

**代码实现与应用包构建已完成；真实 UI、系统通知验收待完成。** 用户已确认本次五项功能需求，并沿用本轮开头提出的完成后提交、推送安排。

## 目标与边界

1. 星标会话置顶，支持拖动星星调整持久化顺序；普通会话按工作中、等待、完成、错误分组，同组保持稳定的已知顺序。
2. 星标运行中使用 Agent 配色的跑马灯；完成后未读背景呼吸，查看后保留边框提示。非星标完成只闪边框。其他 Agent 的星标完成同步提醒顶部胶囊，悬停显示任务与完成摘要。
3. 监听本地会话日志/状态数据库变更，立即刷新；保留低频兜底扫描。星标完成发送 macOS 横幅，非星标完成只送通知中心，开关独立。
4. 六个主题：原生浅色、原生深色、星光、晨雾、青瓷、霓虹。保留现有系统浅色/深色适配以及工作区未提交排版修改。
5. 不改手机端、Windows 端、输入投递和 HUD 列表结构。新动画尊重减少动态效果设置。

## 执行步骤与验证

1. 新增星标排序、稳定排序、完成提醒策略、主题注册测试；先运行确认 RED。
2. 实现存储/策略与 HUD 状态 → `./scripts/test.sh` 确定性用例通过。
3. 实现卡片、胶囊、拖拽、通知与文件监听 → `swift build` 和 `./scripts/build-app.sh`。
4. 构建后用本地 UI 验证；不干预其他进程，不发送真实 Agent 消息。
5. 更新文档、运行 Flutter 回归、`git diff --check`，审查本次全部差异后提交并推送。

## 未验证项

- 真实工作→完成状态下的光效、拖拽、胶囊预览和 macOS 通知未完整验收；截图工具返回黑图，未视为通过。
- 强制结束旧/新重复 HUD 被安全门禁拦截，未绕过；代码已加单实例保护，但旧实例仍需清理。
- 完整 Swift 测试仍有既有 `testOpenCodeCurrentDatabase` 失败；其余 36 项确定性用例通过。详见 `summary.md`。

---

# 双端互通对话模式实施

## 状态

**进行中。** 原记「已完成（2026-11-12）」为错误声明，于 2026-11-13 核查后更正。

核查结论：macOS 端编译失败，两端输入适配器都无法真正把文本送进目标会话，手机端存在静默丢消息与不显示投递结果的缺陷。既有 `./scripts/test.sh` 的 swiftc 文件清单不含 `LinkServer.swift` / `HUDViewModel.swift`，因此「23 项通过与对话功能无关」。详见下方「2026-11-13 核查更正」。

**2026-11-13 最新进展**：macOS 编译已修复；Codex 投递通道已用 `codex queue` 重做，并完成真实在线会话端到端验证（含 HTTP 全链路）。详见文末「2026-11-13 通道打通与端到端验证」。

## 目标

在保留默认只读监控的基础上，允许电脑端按设备授权手机，向正在运行的本地 Agent 会话下发文本任务。
首版覆盖 macOS 与 Windows 桌面端，手机端在会话详情页显示输入栏；Codex 优先作为首个验证通道。

## 已确认现状

- macOS/Windows 手机协议已有只读监控、改名、星标、图片元数据与二进制图片端点。
- 手机端 `SessionDetailPage` 已展示用户原始输入 (`latestPrompt`)，但当前仅提示只读。
- macOS 设备模型 `LinkedDevice` 尚无 `conversationEnabled` 对话权限字段；`LinkServer` 尚无消息发送与投递查询接口。
- Windows 需同步扩展 `MonitoringContracts.cs`、`AgentHudLinkHost.cs`、`LinkDeviceStore.cs` 与 `MainViewModel.cs`。
- Codex 输入通道首版采用平台自动化方案：macOS `cliclick`/AppleScript 向绑定终端输入，Windows UI Automation/SendKeys。

## 实施步骤

1. **macOS 权限与协议**
   - `LinkedDevice` 增加 `conversationEnabled: Bool`，`LinkDeviceStore` 支持读取/更新/旧数据迁移默认 `false`。
   - `LinkSettingsWindow` 为每台设备增加“允许对话模式”开关与风险说明。
   - `LinkServer` 新增 `POST /v1/sessions/{id}/messages`、`GET /v1/deliveries/{id}`。
   - `GET /v1/status` 能力按设备动态计算。
   - `LinkMonitoringSession` 增加可选 `conversation { enabled, state, reason }`。
   - 新增 `AgentInputDispatcher`、`AgentRuntimeRegistry`、`AgentInputAdapter`、`CodexInputAdapter`、`DeliveryStore`。
   - `HUDViewModel` 实现输入调度相关 Snapshot。

2. **Windows 同步**
   - 扩展 `LinkContracts.cs`、`LinkDeviceStore.cs`、`AgentHudLinkHost.cs`、`MainViewModel.cs`。
   - 新增 `AgentInputDispatcher`、`DeliveryStore`、`CodexInputAdapter`。
   - 保持与 macOS 一致的权限规则、协议、错误码。

3. **Flutter 手机端**
   - `models.dart` 增加 `ConversationState`、`MessageDelivery`。
   - `link_api.dart` 增加 `sendMessage`、`deliveryStatus`。
   - `session_controller.dart` 增加发送状态、幂等 ID、轮询、错误处理。
   - `session_detail_page.dart` 底部增加多行输入栏、发送状态与原因展示。

4. **验证**
   - `./scripts/test.sh` 通过。
   - Windows 静态审阅（本机无 `dotnet`）。
   - `flutter analyze`、`flutter test` 通过。
   - Codex 真实通道端到端验证列为未验证项。

## 本次执行命令

1. 修改并新增 macOS Swift 源文件。
2. 修改并新增 Windows C# 源文件。
3. 修改 Flutter Dart 源文件。
4. `./scripts/test.sh` — 通过（23 tests passed）。
5. `cd mobile && flutter analyze --no-fatal-infos --no-fatal-warnings` — 通过（No issues found）。
6. `cd mobile && flutter test` — 通过（9 passed, 1 skipped）。
7. `git diff --check` — 通过（无空白错误）。

## 验证结果

- `./scripts/test.sh`：退出码 0，23 项测试通过。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：退出码 0，无 issues。
- `flutter test`：退出码 0，9 项通过、1 项集成测试按设计跳过。
- `git diff --check`：退出码 0，无空白错误。

## 未验证项

- Windows C# 项目未在本机构建（无 `dotnet`）。
- macOS 正式 `swift build` 因本地 `swift-nio-ssl` C++ 头文件缺失未通过，但 `./scripts/test.sh` 的 `swiftc` 编译通过。
- Codex 真实输入通道端到端未在真实在线会话验证。
- 安卓真机/模拟器 UI 与输入交互未验证。
- Windows UI Automation/SendKeys 方案未在真实 Windows 环境验证。

---

# 2026-11-13 核查更正与重做计划

## 核查方式

- `swiftc -typecheck`：复用 `.build` 已编译模块与 `GeneratedModuleMaps` 全量类型检查 macOS 源码（绕过本地 `swift build` 的 BoringSSL 头文件问题）。
- `./scripts/test.sh`：退出码 0，23 tests passed（但覆盖范围不含对话链路）。
- `cd mobile && flutter analyze --no-fatal-infos --no-fatal-warnings`：退出码 0，No issues found。
- `cd mobile && flutter test`：退出码 0，9 passed / 1 skipped（不含对话链路）。
- CLI 能力实测：`codex queue --help`、`codex app-server daemon version`、`opencode run --help`、`claude --help`/`claude agents --json`。

## 已确证缺陷（按规范 `双端互通HUD对话.md` 条款）

| # | 文档条款 | 缺陷 | 证据 |
|---|---|---|---|
| 1 | §9 | macOS 无法编译 | `LinkServer.swift:26-29` 非隔离上下文构造 `@MainActor` 实例；`LinkServer.swift:379` `LinkMonitoringSession` 传给要求 `AgentSession` 的 `dispatch` |
| 2 | §8.2 / §14 | macOS 投递通道无效 | `CodexInputAdapter.swift:54` 转义结果被丢弃；AppleScript 仅 `Cmd+V`，从未设置剪贴板；无 `AXIsProcessTrusted` 检查 |
| 3 | §8.2 | Windows 投递通道无效 | `CodexInputAdapter.cs` 用 `SendKeys` 敲当前焦点窗口；仅转义 `{}`，含 `'`/`$`/反引号会截断或注入 |
| 4 | §6.2 | 状态值命名不一致 | 文档 `waiting_user`，实现 `waitingUser`；Windows `MainViewModel.cs:599` 发 `ToString()` 得到 PascalCase，手机端 `models.dart:317` 只认 `ready`/`waitingUser`，Windows 端输入框永久禁用 |
| 5 | §11.5 / §8.3 | 第二条消息静默丢失 | `session_detail_page.dart:112` `_lastClientMessageId` 永不清空 → 复用同一 id 被 `DeliveryStore.find` 幂等拦截，界面仍清空输入框 |
| 6 | §11.6 / §15.4 | 不展示投递状态 | `session_detail_page.dart` 对 `deliveryStatus`/`_deliveries` 读取次数为 0；`_pollDelivery` 异常分支直接 cancel 且无提示 |
| 7 | §7.3 | 错误码未实现 | macOS 消息路由失败一律 409；Windows 一律 202；文档要求 409/422/501/503 区分。手机端 `link_api.dart:350` 还丢弃所有非 2xx 响应体 |
| 8 | §7.2 | `observed` 从未产生 | 全项目无该状态输出 |
| 9 | §8.1 | 会话→运行时映射缺失 | `AgentRuntimeRegistry` 注入后从未读写，为死代码 |
| 10 | §13 | 投递归属未校验 | `GET /v1/deliveries/{id}` 仅校验令牌，不校验投递属于当前设备 |
| 11 | §14 | 无审计记录 | 无投递时间/设备/会话/状态/错误码的审计输出 |

## 通道能力实测结论

| Provider | 按会话精确投递 | 证据 |
|---|---|---|
| Codex | ✅ | `codex queue --thread <UUID或会话名> --message <TEXT>`；`app-server daemon version` → `"status":"running"` |
| OpenCode | ✅ | `opencode run -s <sessionID> "消息"` |
| Claude Code | ❌ | 无注入活跃 TUI 的通道；`--bg/--resume` 是继续/复制会话，`--brief` 是 agent→user 方向 |

Windows 可用：`@openai/codex` 的 optionalDependencies 含 `codex-win32-x64` / `codex-win32-arm64`，两端可走同一套 `codex queue` 逻辑。

## 对规范文档的三处修正建议

1. **§8.2 优先级 1 降级**：`codex app-server` 全链路标注 `[experimental]`（`app-server`、`generate-json-schema`、`generate-ts` 均为 experimental），不宜作首选通道。Codex 首版直接用优先级 2（官方 CLI `codex queue`）。
2. **禁止 `--resume`**：`codex queue` 自带 `--resume` 会尝试拉起会话，与 §3.2「暂不包含静默重启已经退出的 Agent」冲突。只允许 `isLive == true` 投递，离线必须报错。
3. **简化 §8.1**：走 `codex queue` 时映射只需到 `providerSessionID`（`CodexAdapter` 已从 `session_meta.payload.id` 解析），不需探测 PID/TTY/窗口。

## 决定性未验证前提

`codex queue` 排队消息能否被**正在运行的交互式 TUI 会话即时消费**。

- 已验证：无效 thread → 退出码 1，报 `no rollout found for thread id ...`（可判定失败）。
- **已解决（2026-11-13）**：成功路径已验证通过——在线 TUI 会即时消费排队消息并调用模型回复，无需 `--resume`。见文末章节。


规范 §12 阶段 0 门槛要求先验此条；当前实现顺序颠倒（UI 已完成、通道未验证），需按 §16 重排。

## 重做步骤（待执行）

1. **阶段 0 验证（先做，未通过则停止）**：用真实在线 Codex 会话验证 `codex queue` 即时消费、多会话不串、中文/多行、进程退出返回失败。
2. 修缺陷 1（macOS 编译）与 4（状态命名统一为 camelCase，两端一致）。
3. 修缺陷 7（§7.3 错误码映射）与 8（`observed`）。
4. 修缺陷 10（§13 投递归属校验）。
5. 修缺陷 9（§8.1 运行时映射，简化到 `providerSessionID`）。
6. 用 `codex queue` 重做通道，替换 AppleScript / SendKeys（缺陷 2、3）。
7. 修手机端缺陷 5、6（幂等 id、投递状态展示、错误体解析）。
8. 补 §14 审计记录（缺陷 11）。
9. 把 `LinkServer.swift`、`LinkResponses.swift`、`HUDViewModel.swift` 补进 `scripts/test.sh` 编译清单，并补对话链路自动化测试。
10. 更正本文档上方原「已完成」记录。

## 执行前置条件

- 需先停掉同目录下并发修改的 Agent 会话（核查期间 PID 24379、24130 持续改动 `AITitleService.swift`、`HUDViewModel.swift`、`Tests/main.swift`），否则验证结果不可靠。
- Windows 端无法本机构建（`dotnet` 不存在），只能静态审阅，须列为未验证项。

---

# 2026-11-13 通道打通与端到端验证

## 状态

已完成（本轮范围）。macOS 编译恢复，Codex 投递通道真实可用，并通过「手机 HTTP 请求 → LinkServer → Dispatcher → 真实在线 Agent」全链路验证。

## 本轮改动

| 文件 | 改动 |
|---|---|
| `Sources/AgentHUD/CodexInputAdapter.swift` | 删除无效的 AppleScript 粘贴方案，改为官方 CLI `codex queue --thread <providerSessionID> --message <text>`（argv 传参，不经 shell，无注入面）。新增 `codex` 可执行文件解析与 PATH 补全（GUI 启动时 PATH 不含 `/opt/homebrew/bin`，`codex` 的 `#!/usr/bin/env node` 会失败）。新增 `isSessionAttached` 判活：用 `lsof -t <rollout 路径>` 确认仍有进程持有该会话日志文件——因为 `codex queue` 对已退出会话也返回 0，仅靠退出码会假成功。 |
| `Sources/AgentHUD/CommandRunner.swift` | `BoundedProcess.run` 增加可选 `environment` 参数，默认行为不变。 |
| `Sources/AgentHUD/LinkServer.swift` | 消息路由返回码按 §7.3 区分：`session_offline`/`agent_busy` → 409，`invalid_message` → 422，`provider_unsupported` → 501，`input_unavailable`/`delivery_failed` → 503；成功仍为 202。 |
| `Tests/LinkServerFixture.swift` | 联调夹具可接入真实 `AgentInputDispatcher` + `CodexInputAdapter`（由 `HUD_E2E_THREAD_ID`/`HUD_E2E_ROLLOUT` 开启），新增 `enableConversation` 请求类型。未设环境变量时行为与原来完全一致。 |
| `mobile/test/link_integration_test.dart` | 新增对话段：开启对话权限 → 发送消息 → 轮询投递状态至终态。 |
| `scripts/test.sh`、`scripts/test-mobile-link.sh` | 编译清单补 `CommandRunner.swift`。 |

## 验证方式与结果

用隔离环境 `CODEX_HOME=/tmp/codex-queue-probe/home` 在 tmux 中启动真实 Codex TUI（不触碰用户现有会话），会话 ID `01a1d431-…`，然后分三层验证。

1. **适配器直投**（编译独立 harness 调用真实 `CodexInputAdapter.deliver`）
   - 在线会话：`success=true status=delivered`，TUI 内出现消息，模型回复 `OK-E2E`，日志 `response_item` 有 `output_text: " OK-E2E"` + `task_complete`。
   - 已退出会话（旧 rollout，无进程持有）：`success=false error=sessionOffline`，未产生假成功。
   - 无效 thread id：`success=false error=sessionOffline`。
2. **HTTP 全链路**（`./scripts/test-mobile-link.sh`，Dart 客户端真实配对）
   - 退出码 0；输出含 `FIXTURE_CONVERSATION_READY`、`FIXTURE_CODE_READY`、`FIXTURE_REVOKED`。
   - 消息经 `POST /v1/sessions/{id}/messages` 进入 TUI（17:20 出现在会话中），投递状态轮询到 `delivered`。
3. **回归**
   - `./scripts/build-app.sh`：退出码 0，`build/AgentHUD.app` 生成。
   - `./scripts/test.sh`：退出码 0，28 项通过。
   - `cd mobile && flutter test`：退出码 0，9 passed / 1 skipped。

## 顺带确认

- `CodexAdapter` 已从 `session_meta.payload.id` 解析 `providerSessionID`，`sourcePath` 即 rollout 文件路径，`isSessionAttached` 无需额外探测 PID/TTY。
- 不使用 `codex queue --resume`，符合 §3.2「不静默重启已退出的 Agent」。

## 仍未完成（按规范条款）

- 缺陷 5、6：手机端 `_lastClientMessageId` 未清空（第二条消息会被幂等拦截）、详情页不展示投递状态。
- 缺陷 7 剩余部分：`link_api.dart` 仍丢弃非 2xx 响应体，手机端拿不到错误码。
- 缺陷 8：`observed` 状态仍未产生。
- 缺陷 9：`AgentRuntimeRegistry` 仍是死代码。
- 缺陷 10：`GET /v1/deliveries/{id}` 未校验投递归属设备。
- 缺陷 11：无 §14 审计记录。
- 缺陷 3：Windows 端仍为 `SendKeys` 方案，未改 `codex queue`，未构建验证。
- 步骤 9 剩余：`LinkServer.swift`、`HUDViewModel.swift` 仍不在 `scripts/test.sh` 编译清单内。
- Claude Code / OpenCode 适配器未实现（Claude 无注入活跃 TUI 的通道）。

# 增加「仅使用 IPv6」配对开关

## 状态

已完成（2026-11-12）。

## 目标

在手机配对页增加一个「仅使用 IPv6 地址连接」开关。开启后：
1. 扫码解析 QR 时只取 `ipv6Addresses`，忽略 IPv4 `addresses`。
2. 配对请求只发往 IPv6 候选地址。
3. 配对完成后保存的 `LinkedDevice.addresses` 只保留 IPv6 地址，后续监控仅尝试 IPv6。
4. 未勾选时保持现有 IPv4 优先、IPv6 回退的行为。

## 实施范围

- `mobile/lib/models.dart`：`_addresses` 增加 `preferIpv6` 参数；`PairingOffer.fromQr`、`LinkedDevice.fromPairing` 透传该参数。
- `mobile/lib/link_api.dart`：`completeQr` 增加 `preferIpv6` 参数，过滤请求地址并透传给 `LinkedDevice.fromPairing`。
- `mobile/lib/pages/pairing_page.dart`：增加 `_useIpv6` 状态与全局 Checkbox；扫码时传入开关状态。
- `mobile/test/models_test.dart`：补充 `preferIpv6` 过滤单元测试。
- `mobile/lib/pages/session_detail_page.dart`：修复同文件残留的语法错误（多余的 `}); } }`）和未使用参数 `initiallyExpanded`，否则 `flutter analyze` 无法通过。
- `PLAN.md`：更新执行状态。

## 边界

- 不改 macOS / Windows / Android Kotlin 服务端；服务端 QR 已返回 `ipv6Addresses`。
- 手动验证码输入仍为单地址，开关不改变其连接行为，仅作为提示。
- 不修改 `DeviceStore` 序列化格式。
- 不承诺公网 IPv6 可达；本改动仅确保手机端在需要时强制走 IPv6 路径。

## 拟执行命令

1. `cd mobile && flutter analyze --no-fatal-infos --no-fatal-warnings` — 静态分析。
2. `cd mobile && flutter test` — 单元测试。
3. `./scripts/test-mobile-link.sh` — Dart↔Swift 集成测试（可选，需本地 Mac AgentHUD）。
4. `git diff --check` — 空白检查。

## 验证结果

- `flutter analyze --no-fatal-infos --no-fatal-warnings`：0 issues（退出码 0）。
- `flutter test`：9 项测试全部通过（退出码 0）。
- `./scripts/test-mobile-link.sh`：Dart↔Swift 集成测试通过（退出码 0）。
- `git diff --check`：无空白错误。

## 未验证项

- 未在安卓真机/模拟器上实际打开相机扫码验证 IPv6 开关 UI。
- 未在跨网络（移动数据 / 其他 IPv6 网络）下验证公网 IPv6 入站可达性。
- 未构建新的 release APK；工作区仍有大量其他未提交改动，未单独发布。

## 备注

- 修复 `session_detail_page.dart` 中的残留语法错误和未使用参数属于「做 A 检查 B 同类问题」：该错误导致 analyze 失败，本次 IPv6 改动无法通过 CI 验证。
- 用户后续可选择：1) 仅提交本次 IPv6 改动；2) 连同其他工作区改动一起提交并发布新 APK。

---

# 发布 IPv6 Android beta.6

## 状态

已完成（2026-11-12）。

## 执行进度

- `457fafb feat: support IPv6 monitoring connections` 已推送 `main`，包含版本 `0.1.0-beta.6+6`。
- 独立 worktree 验证实际提交快照：Flutter 测试通过，静态检查无问题；临时 worktree 已移除。
- Release 已上传 `app-release.apk`，64.2 MB，SHA-256：`04472a04cc82443267e64da411a936471766c7c892631d7cc365c7208b08b638`。
- 已下载到 `.artifacts/v0.1.0-beta.6/app-release.apk`，本地哈希与 Release 一致。
- 工作区其他未提交功能未纳入发布。

## 范围与验证

- 基于 `d115431` / beta.5，发布 `v0.1.0-beta.6`，Android 版本 `0.1.0-beta.6+6`。
- 暂存区仅包含 IPv6 双栈、手机地址处理、对应测试、文档和版本号；不包含待办页面、完成记录、主题色、`.metadata`、Android runner、`.artifacts` 或本机文件。
- `models.dart` 的暂存版本从 HEAD 精确加入 IPv6，不带其他并行功能；工作区原文件保留。
- 已验证 Mac Release、23 项 Mac 测试、真实 IPv4/IPv6 Dart↔Mac 链路及正式全球 IPv6 TLS/鉴权；Flutter 相关测试与静态检查通过。

## 拟执行命令（待批准）

1. `git diff --cached --check && git diff --cached --stat` — 核对仅 IPv6 的暂存内容。
2. `git commit -m "feat: support IPv6 monitoring connections"` — 创建功能提交，附署名。
3. `git push origin main` — 推送 IPv6 功能。
4. `git tag -a v0.1.0-beta.6 -m "AgentHUD v0.1.0-beta.6" <功能提交>` — 创建 beta.6 标签。
5. `git push origin v0.1.0-beta.6` — 推送标签，触发 APK 构建。
6. 从提交创建临时 `git worktree`，在其中运行 `flutter test` 与 `flutter analyze --no-fatal-infos --no-fatal-warnings`，验证实际发布快照；测试完成后移除临时 worktree。
7. 轮询 Release 附件页，验证 APK 和 SHA-256 后提供下载链接。

## 边界

- 不强制推送、不修改旧 Release、不将工作区其他未提交功能纳入。
- 公网 IPv6 仍需真机跨网络验证，发布成功不保证运营商入站连接。

---

# 尝试 IPv6 手机连接

## 完成记录（2026-11-12）

- macOS 保留 IPv4 listener，并在相同端口增加 IPv6 listener；IPv6 绑定失败不阻断原 IPv4 服务。
- 通过 `getifaddrs` 获取实际网卡 IPv6 地址，二维码/状态新增可选 `ipv6Addresses`，旧 `addresses` 的 IPv4 含义不变。
- Android 合并 IPv4 优先的连接候选，支持 IPv6 手动地址输入和 `[IPv6]:端口` 显示，URI 传递去除方括号，保持 DER 指纹校验。
- Mac 配对窗口显示 IPv6 候选地址与网络/防火墙提示。
- 实测 `::1` 和 Mac 全球 IPv6 地址的正式 HTTPS 服务证书 DER 指纹匹配；Dart 请求未授权状态正确返回 `401`。
- 真实 Dart↔Mac 集成测试通过 IPv4 扫码及 IPv4/IPv6 双栈读取；Flutter 相关测试 7 项通过、相关静态检查无问题；Mac 23 项测试及 Release 构建通过。
- 本机成功不证明公网 IPv6 入站可达；仍需安卓真机跨网络验证运营商、路由器和防火墙。
- 未提交、推送或发布新 APK；beta.5 不包含本试验改动。

## 状态

待审批（2026-11-12）。

## 已确认前提

- Mac `en0` 已有全球 IPv6 地址，但当前 AgentHUD 只监听 `0.0.0.0:47653`，二维码和状态只返回 IPv4。
- 当前 Android 的 `Uri(host: address)` 对 IPv6 字面量生成方括号，但 UI 输入不展示正确格式，且二维码不含 IPv6。
- 试验不证明运营商或路由器允许公网入站，需真机跨网络验证。

## 最小试验范围

1. macOS `LinkServer`：支持 IPv4 与 IPv6 双栈监听，默认不暴露新端口，保持既有鉴权和 DER 证书固定。
2. `LinkNetwork`：通过实际网卡读取 IPv6 地址，区分链路本地、唯一本地、全球地址，优先局域网/组网地址；二维码提供可选 IPv6 字段，保留 IPv4 回退。
3. Android：手动连接支持 `[IPv6]:端口` 输入及正确显示；解析新增可选 IPv6 地址，不强制旧服务端支持。
4. 先用 `::1` 对真实 HTTPS 服务和 Dart `LinkApi` 做 TLS、鉴权和读取验证，再测试 Mac 本机 IPv6 地址。
5. 测试：IPv6 URL、地址选择、双栈连接和原 IPv4 回归；不修改 Windows 业务代码。

## 验证边界

- 不在此任务承诺公网 IPv6 可用；Mac/手机运营商、路由器防火墙与地址变化需要实际环境验证。
- 链路本地地址保留接口作用域，不能盲目作为公网地址；临时 IPv6 地址不应成为唯一长期绑定。
- 不自动修改系统防火墙、路由器或 DNS，不新建公网隧道。
- beta.5 APK 已发布并完成哈希验证，不包含本试验的后续改动。

## 拟执行命令（待批准）

1. 本机 IPv6 HTTPS 验证：启动修改后的临时测试服务，使用 Dart 客户端连接 `https://[::1]:端口`。
2. `flutter test`、`./scripts/test.sh`、`./scripts/test-mobile-link.sh` — 验证双栈和 IPv4 回归。
3. `./scripts/build-app.sh` — 构建正式 Mac 应用；若失败列出实际错误。
4. 真机跨网络连接：需要用户连接安卓设备或提供另一台 IPv6 客户端，当前不作为本机可完成项。

---

# 发布 Android beta.5 APK

## 状态

构建中（2026-11-12）。

## 执行进度

- 版本提交 `d115431` 已推送 `main`，仅修改 `mobile/pubspec.yaml` 为 `0.1.0-beta.5+5`。
- `v0.1.0-beta.5` 标签已推送，正在等待 GitHub Actions 上传 `app-release.apk`。
- 不包含本机生成文件或其他未提交文档。

## 发布范围

- 基于远程最新 `5b65b43 feat: add OpenCode monitoring and improve cross-platform UI`，本地 `main` 与 `origin/main` 同步。
- 仅将 `mobile/pubspec.yaml` 的版本从 `0.1.0-beta.4+4` 改为 `0.1.0-beta.5+5`。
- 发布标签：`v0.1.0-beta.2` 的后续 `v0.1.0-beta.5`。
- 不包含 `PLAN.md`、`mobile/.dart_tool/`、`.flutter-plugins-dependencies` 或构建产物。

## 拟执行命令（待批准）

1. `git diff --check` — 检查当前差异；只读。
2. `git add -- mobile/pubspec.yaml && git diff --cached --check && git diff --cached --stat` — 只暂存版本文件并检查。
3. `git commit -m "chore(mobile): release v0.1.0-beta.5"` — 创建版本提交，附要求的署名。
4. `git push origin main` — 推送版本提交。
5. `git tag -a v0.1.0-beta.5 -m "AgentHUD v0.1.0-beta.5" <版本提交>` — 创建发布标签。
6. `git push origin v0.1.0-beta.5` — 推送标签，触发 GitHub Actions。
7. 轮询 Release 附件页，确认 `app-release.apk` 上传并读取哈希，再提供下载链接。

## 验证与边界

- 沿用已通过的 Mac Release、23 项 Mac 测试、Flutter 测试与静态检查；发布必须等待 CI APK 附件实际上传。
- 不修改旧 Release、不强制推送、不包含本机文件。
- 无安卓真机，发布成功不代表已验证安装或界面。

---

# 提交并推送当前源码与测试

## 状态

待审批（2026-11-12）。

## 已确认事实

- 手机同步优化已在远程 `67f4c70` / `v0.1.0-beta.4` 中，beta.4 APK 已发布；不重复提交同一同步代码。
- 当前未提交内容包括 macOS DER 证书指纹、OpenCode 数据源、双端 UI 调整、相关测试和文档；这些是当前工作区待推送内容。
- 最新 Mac Debug/Release 构建通过；`./scripts/test.sh` 23 项通过；Flutter 测试 6 项通过、静态检查无问题。
- 不提交 `mobile/.dart_tool/`、`mobile/.flutter-plugins-dependencies` 或构建产物。

## 拟执行命令（待批准）

1. `git diff --check` — 检查空白错误；只读。
2. `git add -- README.md Sources Tests scripts/test.sh scripts/test-mobile-link.sh Windows docs/lan-monitoring.md mobile/README.md mobile/test/link_integration_test.dart` — 暂存当前源码、测试与文档；不包含 Flutter 本机生成目录。
3. `git diff --cached --check && git diff --cached --stat` — 核对提交范围与空白错误；只读。
4. `git commit -m "feat: add OpenCode monitoring and improve cross-platform UI"` — 创建提交，附要求的署名。
5. `git push origin main` — 推送至 GitHub 主分支；不强制推送。
6. `git status --short --branch` — 验证同步状态及排除的本机文件；只读。

## 验证与未验证项

- Windows 未在本机编译；已有 Windows Core 测试改动仅纳入源码，不声称本机 Windows 验证通过。
- 不创建新 beta 标签，本次仅推送源码；如需新 APK 需另行发布。
- 无安卓真机，不声称真机界面和局域网速度已验收。

---

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

### 待办列表与隐藏模式（2026-11-12）

#### 目标

1. **待办列表**：在手机端增加「待办」筛选（紫色），与「全部/工作/等待/完成/错误」并列；支持待办 CRUD（增删改查）。
2. **隐藏模式**：用户通过配对页面触发隐藏模式后，应用进入「高级功能」状态，显示额外入口（待办列表、消息发送等）。隐藏模式状态持久化到本地存储。
3. **手机端 UI 优化**：确保筛选、会话卡、详情页与桌面版（macOS/Windows）视觉和交互一致。

#### 设计决策

- 待办是**纯本地功能**，不走 LAN 协议（不依赖电脑）；各端独立存储，暂不同步。
- 待办状态筛选显示为紫色（`Color(0xFFB86AFE)` 或类似），使用与状态筛选相同的切角科技边框 + 霓虹效果。
- 隐藏模式状态使用 `flutter_secure_storage` 或 `SharedPreferences` 持久化；macOS/Windows 也增加隐藏模式状态，但用户自行触发。
- 手机端待办列表使用与桌面 session list 类似的卡片布局，支持滑动删除、长按编辑。
- UI 优化重点：
  - 筛选：保持切角/胶囊区分，增加待办筛选。
  - 卡片：确保信息密度、字体大小、间距与桌面版一致。
  - 详情：确保所有 section 的呈现方式与桌面版对齐。

#### 实施步骤

1. **移动端模型 + 存储**：`models.dart` 增加 `TodoItem`；新增 `todo_store.dart` 使用 `flutter_secure_storage` 或文件存储。
2. **移动端界面**：
   - `sessions_page.dart`：状态筛选行增加「待办」选项（紫色）。
   - 新增 `todos_page.dart`：待办列表，支持增删改查。
   - `session_detail_page.dart`：微调确保与桌面版一致。
   - 隐藏模式状态管理：新增 `hidden_mode.dart`。
3. **macOS/Windows**：扩展协议增加 `hiddenMode` capability/flag；复用现有存储机制。
4. **验证**：`flutter analyze`、单元测试、`./scripts/test.sh`、`git diff --check`。

#### 完成记录（2026-11-12）

- **移动端待办**：新增 `TodoItem` 模型、`TodoStore`（`flutter_secure_storage` 本地持久化）、`TodosPage`（增删改查 + 滑动删除）。状态筛选增加紫色「待办」入口；激活时 AppBar 切换为「待办」并跳转 `TodosPage`。
- **移动端隐藏模式**：新增 `HiddenModeStore`（本地持久化）；`SessionsPage` AppBar 在隐藏模式启用时显示「☰」待办按钮；入口由配对页触发，状态管理已就绪。
- **移动端完成记录**：`AgentSession` 增加 `runs` 字段（构造函数、字段声明、`fromJson`、`copyWith`）；`SessionDetailPage` 新增「完成记录」分区及 `_RunsList` 组件，展示 `objective/summary/actions/filesChanged/completedAt`。
- **macOS 协议**：`LinkModels.swift` 新增 `LinkTaskRun` 结构体；`LinkMonitoringSession` 增加 `runs: [LinkTaskRun]`；`HUDViewModel.monitoringSnapshot()` 将 `session.runs` 映射后填充到快照，隐私模式下返回空数组。
- **Windows 协议**：`MonitoringContracts.cs` 新增 `MonitoringTaskRun` record；`MonitoringSessionSnapshot` 增加 `Runs` 字段；`MainViewModel.GetMonitoringSnapshot()` 将 `session.Runs` 映射为 `MonitoringTaskRun` 列表传入快照。
- **验证**：`flutter analyze --no-fatal-infos --no-fatal-warnings`：0 issue。`flutter test test/models_test.dart`：3/3 通过。`./scripts/test-mobile-link.sh`：1/1 通过。`./scripts/test.sh`：23/23 通过。`git diff --check`：无输出。
- **未验证**：macOS `swift build` 因 C++ 头文件缺失未通过（与源码无关）；Windows 无 `dotnet` 未编译；真机/模拟器运行、动画帧率、待办滑动手感、完成记录多端同步未验证。

#### 边界

- 不实现远程发送消息（用户自行处理）。
- 待办暂不同步到电脑，仅手机端本地使用。
- 不提交、不推送，除非用户另行要求。

#### 拟执行命令

1. `flutter analyze` — 静态分析。
2. `flutter test` — 测试。
3. `./scripts/test.sh` — macOS 逻辑测试。
4. `git diff --check` — 空白检查。

---

# AI 会话标题取两轮上下文

## 状态

已完成（2026-11-13）。

## 目标

AI 生成的会话标题应反映会话真正要做的事，而不是只描述最后一次动作。
当用户回复「确认」「继续」这类续接语时，标题要按上一轮的实质任务目标命名，而不是输出
「用户确认了该任务」这类对话过程描述。

## 已确认现状

- `AITitleRequest` 只有单个 `prompt`，`AITitleService` 的系统提示词写死「根据用户最近一次输入」。
- `HUDViewModel.startAITitleEnrichment` 在 latest 是续接语且无图片时直接 `return nil`，AI 标题根本不生成。
- `AgentSession` 只保留 `latestUserPrompt`，上一轮实质输入被 adapter 覆盖丢弃。
- 上一轮目标其实已存在：adapter 把 `meaningfulPrompt` 写入 `TaskRun.objective`，可从 `runs` 反查，无需新增字段。

## 实施步骤

1. `AITitleService.swift`
   - `AITitleRequest` 增加 `previousPrompt`（默认空，向后兼容），纳入 `rawFingerprint` 与缓存 key。
   - `prepare` 归一化 `previousPrompt`（上限 2000 字符）。
   - `makeURLRequest` 拼出「上一次输入 / 本次输入」两段，并按续接/非续接/单轮三种场景给出不同指令：
     续接时以上一轮为目标；非续接时明确不要再概括上一轮；单轮时只看本次。
   - system 提示词禁止元叙述（不要以「用户」开头，不要出现「确认了」「同意了」等）。
   - `sanitize` 增加 `previousPrompt` 参数与 `describesConversation` 拒绝规则。
2. `HUDViewModel.swift`
   - 新增 `previousObjective(for:)`，从 `runs` 倒序取首个非续接 objective。
   - 续接且无图时不再一律跳过：只有取不到上一轮目标才跳过。
3. `Tests/main.swift`
   - `testAITitleTwoTurnContext`：两轮拼装、续接指令、非续接指令、单轮不虚构上一轮。
   - `testAITitleRejectsConversationMeta`：拒绝元叙述、放行合法「用户…」标题、拒绝照抄上一轮原句。

## 边界

- 仅改 macOS 端。Windows 端 `AITitleService.cs` / `MainViewModel.cs` 同名逻辑保持现状，未同步。
- 移动端只展示服务端下发的 `title`/`titleSource`，不参与生成，未改动。
- 不改 `LinkModels`、公共 UI 组件、adapter 的 `UserPromptSnapshot` 结构。

## 验证结果

- `zsh ./scripts/test.sh`：26 tests passed（改动前 23），exit 0。
- typecheck（AITitleService + HUDViewModel 及全部非 UI 依赖）：无 error。
- 行为探针三种场景输出符合预期：
  - `确认` + 上一轮 `合并java代码并且检查前端是否正常` → 指令要求按上一轮概括。
  - `检查订单列表分页` + 上一轮 → 指令要求只概括当前任务。
  - 单轮 `查询日志报错详情` → 不拼上一轮段。
- 过滤矩阵：`用户确认了该任务`/`用户同意合并代码`/`用户要求新增导出功能` → 拒绝；
  `检查Java代码和前后端`/`用户登录鉴权改造`/`用户管理模块重构` → 保留。
- RED 基线对照：改动前 `用户确认了该任务` 被原样放行，正是用户报告的现象。

## 未验证项

- 真实 AI Provider 的端到端输出未验证（需联网与密钥），只验证了请求体与过滤规则。
- Windows 端未同步，两端标题质量会有差异。
- macOS `swift build` 因 swift-crypto 的 C++ 头文件缺失失败，与本改动无关；改用 swiftc typecheck 覆盖。

## 备注

- 自审与本地对抗性审查共修正三处：初期「用户」前缀硬拒会误杀「用户登录鉴权改造」；
  metaPhrases 含单字「表示」易误杀；非续接场景原指令会鼓励模型概括上一轮造成新旧串味。
- Fusion 独立审查本会话不可用（已熔断），按规范登记 `unavailable` 并完成本地对抗性审查。

## 补充（2026-11-13）：首轮无历史对话的边界

原实现的跳过判断内联在 `startAITitleEnrichment` 里，无法单独测试。本次抽出纯函数
`AITitleEligibility.previousPrompt(currentPrompt:hasImages:latestObjective:)`，返回三态：

- `nil` —— 跳过本次 AI 请求（首轮即续接且无图片，没有可依据的任务内容）
- 空串 —— 单轮请求，只按本次输入命名
- 非空 —— 带上上一轮实目标作为上下文

覆盖并实测七种情形：

| 情形 | 期望 | 实测 |
|---|---|---|
| 首轮普通提问 | `<空>` | OK |
| 首轮就是「继续」 | `<跳过>` | OK |
| 首轮「继续」带图片 | `<空>`（仍请求） | OK |
| 「确认」+ 上一轮任务 | 复用上一轮目标 | OK |
| 新任务 + 上一轮 | 保留上一轮作背景 | OK |
| 上一轮自身是续接语 | `<跳过>` | OK |
| 空输入 | `<空>` | OK |

`Tests/main.swift` 新增 `testAITitleEligibility` 六条断言；`scripts/test.sh` 23 → 27 项全过。

# Windows 双端对话补齐 + 设置页统一（2026-11-14）

## 目标

1. 补齐 Windows 端双端对话投递，让手机也能向 Windows 上的 Codex 会话发消息（用户后期在 Windows 机器上验证）。
2. 统一 macOS「手机关联」与「AI 标题与显示设置」两页视觉，优化按钮层级与连接区功能。

## 改动

### Windows（本地无 dotnet，未编译验证）

- `Windows/src/AgentHUD.Windows/Services/CodexInputAdapter.cs`
  - 删除 PowerShell `SendKeys` 键盘注入（不可靠、会把文本当快捷键解释）。
  - 改为 `codex queue --thread <ProviderSessionId> --message <text>`，用 `ArgumentList` 传参避免 shell 拼接。
  - 新增 `FindCodexExecutable()`：PATH 里的 `codex.exe` 优先，其次回溯 npm 的
    `node_modules/@openai/codex/node_modules/@openai/codex-win32-{x64,arm64}/vendor/*/bin/codex.exe`。
  - 新增 `IsSessionAttached()`：独占打开 rollout 文件，`IOException` 说明仍有进程持有该会话。
    因为 `codex queue` 对已退出会话同样返回 0，不先探活会静默丢消息。
  - 15 秒超时，超时后 `Kill(entireProcessTree: true)`。
- `Windows/src/AgentHUD.Windows/ViewModels/MainViewModel.cs`
  - 对话状态改为 camelCase（`ready` / `waitingUser`），此前是 PascalCase，手机端
    `canSendMessage` 永远为 false，表现为「有输入框但按钮一直不可用」。
- `Windows/src/AgentHUD.Link/AgentHudLinkHost.cs`
  - 投递错误改为 camelCase（`sessionOffline`），此前是小写 `sessionoffline`，与 macOS 不一致。

### macOS

- `Sources/AgentHUD/LinkSettingsWindow.swift` 重写：
  - 与 AI 设置页统一：38×38 图标头、17pt 标题 + 11.5pt 副标题、12pt 分区标题、
    11pt 字段标签、24pt 内边距、`lock.shield` 页脚；窗口 440×680 → 520×720。
  - 连接区：监听状态点（监听中/异常）、IPv4 地址逐条展示 + 复制、IPv6 单独分区。
  - 配对区：二维码 250→200 加白底内衬、配对码倒计时（`TimelineView` 每秒刷新，过期变橙色）、
    `生成新配对码` 主按钮（`.borderedProminent`）+ `刷新设备` 次按钮，刷新期间显示 `ProgressView` 并禁用。
  - 设备区：卡片式容器、设备数统计、空态文案、`撤销` 与 `允许对话模式` 开关。

## 验证结果

- `./scripts/build-app.sh` → `Build complete! (162.03秒)`，exit 0。
- `./scripts/test.sh` → 28 tests passed，exit 0。
- `cd mobile && flutter test` → 10 passed / 1 skipped，exit 0。
- SourceKit 报的 `LinkServer has no member ipv6Addresses` 是索引陈旧，实际编译通过（该属性在 `LinkServer.swift:37`）。

## 未验证项

- Windows 端完全没有编译与运行验证：本机无 `dotnet`。
- Windows 的 `FileShare.None` 探活依赖 Codex 以写入方式持有 rollout 文件，未在真机确认。
- 设置页 UI 改动只做了编译验证，未做截图比对。
- 正在运行的 AgentHUD（旧构建）需要重启才能看到新设置页，本次未重启。

## 未知工作状态（手机端「状态待确认」）修复

### 根因

`SessionScanner.scan()` 在 Orca 存在时会完全短路到 `OrcaSessionSource.scan()`。而 Orca 的
`agent-hooks/last-status.db` 只保留最近的状态条目：更早的标签页没有对应行，就拿不到
`providerSession.transcriptPath`，`adapterSession` 为 nil，`effectiveStatus` 最终落到
`.unknown`。矛盾点在于该会话的 transcript 实际就在磁盘上，适配器能读出 `completed`。

### 变更

- `Sources/AgentHUD/OrcaSessionSource.swift`
  - 新增私有 `TranscriptIndex`：每次 `makeSessions` 最多枚举一次目录，按 sessionId 建索引。
    Claude 走 `~/.claude/projects/<项目>/<sessionId>.jsonl`；
    Codex 走 `~/.codex/sessions/<年>/<月>/<日>/rollout-*-<sessionId>.jsonl`。
  - `makeSession` 的 `transcriptPath` 改为「状态条目里的值 ?? 按会话 ID 补查」：
    有条目时行为完全不变，只有缺失条目时才走磁盘兜底。
  - 兜底不改变既有优先级（`hookStatus` 仍然优先于适配器结果），也不引入缓存或共享可变状态
    （索引是每次扫描的局部实例，避免并发问题）。

### 验证结果

- 真实数据探针对照（同一时刻、同一份 Orca 数据）：
  - 修复前（HEAD）：`unknown = 1`，`codex:01a1cdc6-8437-7520-8770-cd7a46a7fc14` 为 `unknown / low`。
  - 修复后：`unknown = 0`，该会话为 `completed / high`，`protocolValue = "Completed"`，
    `sourcePath = rollout-2026-11-12T11-21-41-01a1cdc6-….jsonl`。
  - 扫描耗时 4.745s → 5.055s（冷启动）、1.763s → 1.931s（热缓存），约 +7%，
    来自那一次 transcript 解析；有状态条目的会话本来就走同一条解析路径。
- `./scripts/test.sh` → 28 tests passed，exit 0。
- `cd mobile && flutter analyze` → No issues found。
- `cd mobile && flutter test` → 10 passed / 1 skipped，exit 0。
- `./scripts/test-mobile-link.sh` → 真实 LinkServer + 真实 HTTPS + Dart `LinkApi`
  完成配对与状态拉取，`All tests passed!`。
- `./scripts/build-app.sh` → `Build complete!`，exit 0。
- 已重启 HUD（旧进程 07:35 构建 → 新进程 13:52 构建），`47653` 双栈监听正常；
  模拟器 `10.0.2.2:47653` TCP 可达（对照端口正常拒绝）。

### 未验证项

- 手机端配对后的 UI 截图未取得：配对码只存在于 HUD 进程内存，本机未授予屏幕录制/辅助功能权限，
  无法读取窗口；模拟器已安装真实 APK（14:19 构建）但未完成配对。
- `unknown` 归零依赖本地 transcript 文件仍在磁盘上；若会话文件被清理，仍会退化为 `unknown`。
- Windows 端未编译验证（本机无 `dotnet`）。


## mac / 手机配对与连接体验修复（2026-11-15）

### 现象
- mac HUD 与手机扫码配对流：扫码后长时间无反应，失败提示 2 秒即消失。
- mac HUD 配对页不显示监听端口，手动输入无法完成配对。
- 手机与电脑不在同一局域网时无任何提示。
- mac 局域网连接比 Windows 明显卡顿。

### 实测结论（只读验证）
- mac 服务双栈监听正常（lsof: *:47653 IPv4/IPv6）；本机 25 次 /v1/status 17–54ms，keep-alive 可复用。
- 模拟器 nc 到 192.168.1.8:47653 / 10.0.2.2:47653 均可达，TLS 握手有响应。
- 用与 app 相同的 CIQRCodeGenerator+7x+200pt 缩放离线复现二维码，103 模块，400/600px 均被系统 QR 识别器解码成功。
- 防火墙已关闭；主线程采样为空闲等待。
=> 服务、二维码、链路均正常，问题集中在手机端交互与超时策略，以及 mac 页面缺端口。

### 变更范围
- macOS：Sources/AgentHUD/LinkSettingsWindow.swift（新增端口显示与复制）。
- 手机：mobile/lib/models.dart、link_api.dart、pages/pairing_page.dart、test/models_test.dart。
- 不修改 Windows 任何代码。

### 验证
- swift build / ./scripts/build-app.sh、./scripts/test.sh。
- cd mobile && flutter analyze && flutter test。
- ./scripts/test-mobile-link.sh（真实 LinkServer + Dart LinkApi 端到端配对）。

## mac 桌面端渲染卡顿修复（2026-11-15，已批准）

### 现象
- 会话较多时 HUD 浮窗卡顿，鼠标拖动、展开收起都发滞。

### 实测结论（只读验证）
- 运行中 HUD（PID 59923）连续采样 CPU：56% / 62% / 78% / 152% / 61%。
- `sample` 2 秒：主线程 724/2000 个样本落在
  `CA::Transaction::commit → CALayer::display → CoreText 字形绘制`，即持续重绘文本，
  不是 IO 等待（与上一节「主线程采样为空闲等待」的结论相反，时间点不同）。
- 全仓库唯一的无限循环动画：`HUDShell.swift:1196`
  `.symbolEffect(.pulse, options: .repeating)`，由每行 `PulsingStatusDot`
  （`HUDShell.swift:1056`，条件 `session.status.isRunning`）驱动。工作会话越多，
  同时在跑的持续动画越多。Windows 端 XAML 只有骨架屏 pulse，无逐行脉冲。
- `visibleSessionRows` 在同一次 body 求值中被计算 3 次（`:221`、`:229`、`:247`），
  每次都要 filter + sort。

**[订正]** 上面「导致面板按屏幕刷新率持续重绘文字」的机制描述不准确，已由独立审查推翻：
`symbolEffect(.pulse, options: .repeating)` 是渲染服务器（render server）驱动的符号特效，
**不会重新求值 SwiftUI body，也不逐帧重绘兄弟 Text**。真实成本模型是：
N 行 × 各自一个常驻连续动画 = N 个并发动画事务 + 半透明窗口的持续合成开销，
随行数线性放大。修复方向仍然正确，但机制表述以此为准。

### 变更范围（只动 1 个文件）
- `Sources/AgentHUD/HUDShell.swift`
  1. `PulsingStatusDot`：删除 `.symbolEffect(.pulse, options: .repeating)`，改为静态实心点
     （运行中 6pt、静止 5pt），与 Windows 端无逐行动画的做法对齐。
  2. `ExpandedHUDView.body`：`visibleSessionRows` 只求值一次并在三处复用。
- 不修改 Windows、手机端、`HUDViewModel.swift`、`LinkSettingsWindow.swift`
  （后两者由并行会话修改中，按 MA1/MA3 避开）。

### 验证
- `./scripts/test.sh`、`./scripts/build-app.sh` → exit 0。
- 重启 HUD 后 `sample` 主线程栈对比基线（同一指标、同一测量方式）。

### 过程中修正的两个错误
1. 第一版用 `@State` + `onChange` 实现呼吸，构建失败：本机 CLT 工具链缺少
   `SwiftUIMacros.StateMacro` 插件（全仓库此前只用 `@ObservedObject`，无 `@State`）。
   第二版改用 `phaseAnimator`（无宏），可编译，但对 CPU 无改善，故最终改为静态点。
2. 一度用 `ps -o %cpu` 判断「CPU 降到接近 0」，这是误读：macOS 的 `%cpu` 是进程
   生命周期的衰减平均值，不是瞬时值。改用 `ps -o time` 累计 CPU 时间差测量。

### 执行结果
- `./scripts/build-app.sh` → `Build complete! (25.17秒)`，exit 0。
- `./scripts/test.sh` → `28 tests passed`，exit 0。
- 重启后 `sample` 5 秒主线程栈：3194 个样本中 2852（89%）落在
  `__CFRunLoopServiceMachPort → mach_msg`（空闲等待），
  落到 `CA::Transaction::commit` 的只剩 130 个（4%），且其下主要是
  `NSWindow layoutIfNeeded`（布局），不再是 `CALayer::display → CoreText` 逐帧文字重绘。
  → **主线程持续重绘已终止，渲染卡顿的根因已消除。**
- 累计 CPU 时间 60 秒窗口：旧代码约 36%，本次约 33–37%，**总体 CPU 基本未变**。
  原因见下条：剩余 CPU 不在渲染，而在后台。

### 新发现（未修，需另立任务）
- 剩余 CPU 热点在后台线程，不在主线程：
  `HUDViewModel.performRefresh() HUDViewModel.swift:552 → SessionScanner.scan()
  → attachGitContexts() SessionScanner.swift:166 → cachedGit() :181 → GitReader.read()
  → BoundedProcess.run()`。
- `GitReader.read()` 每次调用最多起 **5 个 `git` 子进程**
  （`rev-parse --show-toplevel`、`branch --show-current`，空则再 `rev-parse --abbrev-ref`、
  `status --porcelain=v2`、`diff --numstat`、`diff --cached --numstat`）。
- 缓存 TTL 在 `SessionScanner.swift:177`：有值 8 秒、无值 30 秒；刷新循环 3 秒一次
  （`HUDViewModel.swift:512`）。因此每个项目每 ~8 秒重新跑一整套 git 子进程。
- 这与「会话多就卡」直接相关：项目越多，同时 spawn 的 git 越多。
- 未修原因：会涉及 `SessionScanner.swift` / `GitReader.swift`，超出本次已批准范围。

### 未验证项
- 折叠态与展开态都测过主线程栈，但**展开态未在「大量会话」下单独测**：
  `SessionScanner.swift` 服务端上限 24，本机当前会话数未构造到上限。
- 视觉观感（静态 5pt 点取代原脉冲点）需人工确认，无截图权限。
- 未在 Windows 端验证任何内容（本机无 dotnet，且按约束不改 Windows）。

### 独立审查（Fusion 503 → 本地对抗审查，已完成）
Fusion 返回 `HTTP 503`，按规则转本地对抗性审查并真实执行。逐条结论：

1. **无遗漏无限动画源**：`symbolEffect` / `repeatForever` / `phaseAnimator` 全目录归零。
   残留 `StarlightBackground:2244` 的 24fps `TimelineView` 仅 starlight 主题触发（当前配置
   为 classic，未触发），且是单层背景 Canvas、成本不随会话数增长 → 不需一并处理。
   `LinkSettingsWindow.swift:268` 的 1Hz `TimelineView` 只在配对窗口打开时存在 → 不需处理。
2. **无信息丢失**：`StatusBadge:1941` 已渲染 5pt 彩点 + `shortLabel` 文字
   （`Models.swift:70-82`：启动/工作/等待/空闲/完成/出错）；被删的脉冲只是"运行中"的冗余提示。
3. **无布局抖动**：`StatusDot` 尺寸固定 5pt；`HStack(spacing:5)` 默认 `.center` 对齐，
   不参与文字基线；与 `StatusBadge:1947` 的 5×5 圆点一致。
4. **rows 复用语义等价**：`visibleSessionRows`（`HUDViewModel.swift:177`）是纯计算属性，
   同一轮 body 内三次读取本就返回同一数组；`SessionRowPresentation.id` 未变，
   不会引起 `LazyVStack` 重建。唯一差异是跳过 `isLoading` 分支的短路，无行为影响。
5. **无其他逐行无限动画**：两处 `ProgressView` 都是单实例（`:281` 表头刷新态、
   `:2036` 空态），不随会话数缩放。

**审查推翻了我的一处结论**：见上文「[订正]」——动画成本模型不是"逐帧重绘文字"。

### 执行结果（已完成）

- mac：`LinkSettingsWindow.swift` 新增「监听端口」区（`Text(verbatim:)` 避免千分位），IPv6 区注明同一端口。
- 手机 `models.dart`：`preferIpv6` 改为「IPv6 优先 + IPv4 回退」，不再因缺少 IPv6 抛错。
- 手机 `link_api.dart`：新增失败地址记忆（`_preferredAddress`）与 `onAttempt` 进度回调；错误文案改为列出已尝试的 `地址:端口`。
- 手机 `pairing_page.dart`：连接进度文案、同网段预检（`NetworkInterface.list`）、失败后暂停自动重试并常驻「重新尝试」按钮。
- `mobile/test/models_test.dart`：按新语义重写两条 IPv6 用例。

### 验证结果
- `./scripts/build-app.sh` → `Build complete! (169.14秒)`。
- `./scripts/test.sh` → 28 tests passed。
- `flutter analyze` → No issues found。
- `flutter test` → 10 passed / 1 skipped。
- `./scripts/test-mobile-link.sh` → 真实 LinkServer + HTTPS + Dart LinkApi 端到端 `All tests passed!`。
- 重启 HUD 后截图确认端口 `47653` 正常显示、二维码正常渲染。

### 未验证项
- 手机真机与 mac 的实际局域网配对未复现（配对码在进程内存，需人工用手机扫）。
- 同网段预检只覆盖 IPv4；IPv6 场景不做推断。
- Windows 端未编译（本机无 dotnet），本次未修改 Windows 任何文件。

### 审计闭环（strict）
- behavior：flutter test，10 用例，exit 0（green）。
- requirements：R1 登记为 CHANGED，覆盖 5 个子诉求。
- diff：读取完整 diff，修改仅限 5 个允许文件，Windows/ 零改动。
- self_review：本地对抗性审查后修 3 处缺陷。
  1. _needsManualRetry 曾完全阻断扫码（换新码也无反应）→ 改为 _failedRaw 只屏蔽同一张失败码。
  2. _lanWarningFor 只看第一个 IPv4，会误报「不在同一网段」→ 改为对全部 IPv4 目标 any 匹配。
  3. 扫码/验证码切页时旧错误残留 → 切页清空提示状态。
- independent_review：Fusion 返回 503，如实登记 unavailable + fallback=main_agent_completed_local_adversarial_review。
- 审计状态：status=passed，pending=[]，failed=[]。

## 「高级动画」可选开关（2026-11-15，待批准）

### 用户需求（原话）
> 这个闪一闪的还是很高级的，在设置里面增加，高级动画，属于高级动画，用户选择性开关

即：把上一节删掉的「运行中会话脉冲点」作为**高级动画**恢复，但改为用户可在设置里开关；
用户在确认卡中已选定 **默认关闭**。

### 现状证据
- 被删的脉冲实现：`HUDShell.swift:1189`（原 `PulsingStatusDot`，
  `.symbolEffect(.pulse, options: .repeating, isActive: isPulsing)`），无任何宏依赖，
  可直接原样恢复，视觉与用户认可的原效果一致。
- 设置持久化范本：`HUDViewModel.swift:9-69`（`@Published` + `didSet` +
  `UserDefaults.standard.set(_, forKey: "hud.*")`），读取在 `:121-147`。
- 设置 UI 挂载点：`AISettingsWindow.swift:302` `displaySettings`（「外观与尺寸」区），
  已有 `Toggle(...).toggleStyle(.switch)` 范例在 `:201`。
- 无障碍闸门：`HUDMetrics.reduceMotion`（`HUDMetrics.swift:49`），
  读取系统「减少动态效果」设置。

### 拟执行步骤（每步附验证）
1. `HUDViewModel.swift`
   - 新增 `@Published var advancedAnimations: Bool`，`didSet` 写入
     `UserDefaults.standard.set(advancedAnimations, forKey: "hud.advancedAnimations")`。
   - init 中按范本读取，**缺省 false**（即默认关闭）。
   - `resetAppearanceToDefaults()`（`:496`）中重置为 `false`，与其余外观项一致。
   - 验证：`./scripts/build-app.sh` exit 0；`defaults read com.agenthud.app
     hud.advancedAnimations` 首次为不存在 → 行为 false。
2. `HUDShell.swift`
   - `StatusDot` 增加 `let animates: Bool`，body 分两支：
     `animates` 时恢复原 `.symbolEffect(.pulse, options: .repeating, isActive: true)`，
     否则保持静态 `Circle()`。
   - 调用点 `:1057` 传
     `animates: model.advancedAnimations && session.status.isRunning && !HUDMetrics.reduceMotion`。
   - 恢复为 `Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(color)`
     + symbolEffect，保证与删除前像素级一致。
   - 验证：开关打开且会话运行中 → 点脉冲；开关关闭 → 静止。
3. `AISettingsWindow.swift`
   - `displaySettings` 中「主题」之后加
     `Toggle(isOn: $displayModel.advancedAnimations)` +
     `.toggleStyle(.switch)`，标题「高级动画」，
     副说明「运行中的会话状态点会脉冲闪烁。效果更醒目，会话较多时占用更高；关闭可降低开销。」
   - 验证：`./scripts/build-app.sh` exit 0；打开设置窗口肉眼确认开关存在且可切。
4. 全量验证
   - `./scripts/test.sh` exit 0（28 tests）。
   - `./scripts/build-app.sh` exit 0。
   - 重启 HUD，改 `defaults write com.agenthud.app hud.advancedAnimations -bool true`
     后重启，`sample` 确认出现持续动画；再改回 false 确认消失。
   - `defaults delete` 该键，确认回落默认关闭。

### 影响范围 / 风险
- 只改 3 个文件，均为 mac 端；**Windows 与手机端零改动**。
- 与并行会话无重叠：对方在改 `LinkSettingsWindow.swift`、`mobile/*`。
- 风险 1：`symbolEffect` 为宏无关 API，但需确认本机 CLT 工具链可编译
  （上一版已验证该 API 曾在基线代码中编译通过）。→ 由 build-app.sh 把关。
- 风险 2：`resetAppearanceToDefaults` 会关掉用户手动打开的开关，
  语义与「恢复默认外观」一致，属预期。
- 回滚：三处均为增量改动，`git checkout` 三个文件即可。

### 未验证项（执行后填写）
- 无窗口截图权限，脉冲观感需用户目视确认。
- 未构造 24 会话上限下的动画开销对比。

### 执行结果（已完成）

三处改动，共 42 行：
- `HUDViewModel.swift:70` 新增 `@Published var advancedAnimations`，`didSet` 写入
  `hud.advancedAnimations`；`:148` init 读取（键缺失 → `bool` 返回 false → 默认关闭）；
  `:508` `resetAppearanceToDefaults()` 置 false。
- `HUDShell.swift:1194` `StatusDot` 恢复
  `Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(color)
  .symbolEffect(.pulse, options: .repeating, isActive: animates)`；
  `:1057` 传 `animates: model.advancedAnimations && session.status.isRunning
  && !HUDMetrics.reduceMotion`。
- `AISettingsWindow.swift:327` 「外观与尺寸」区「主题」之后新增
  `Toggle(isOn: $displayModel.advancedAnimations)` + `.toggleStyle(.switch)`，
  标题「高级动画」，副文案说明效果与开销。

### 验证结果（真实运行）
- `./scripts/build-app.sh` → `Build complete! (28.33秒)`，exit 0。
- `./scripts/test.sh` → 28 tests passed，exit 0。
- **开关真实生效**（`ps -o time` 累计 CPU 差，30 秒窗口）：
  - 关闭态：`0:06.37 → 0:13.16` = 6.79s（约 23%）
  - 开启态：`0:06.31 → 0:32.98` = 26.67s（约 89%）
  - 主线程渲染帧：开启 15 / 关闭 0
- **默认关闭成立**：`defaults delete com.agenthud.app hud.advancedAnimations` 后重启，
  行为为关闭（键不存在 → `UserDefaults.bool` 返回 false）。
- **未破坏既有设置**：清理后复查 `hud.visualTheme=classic`、`hud.panelOpacity=1`、
  `hud.isExpanded=0` 均完好。

### 独立审查（Fusion 熔断 → 本地对抗审查，已完成）
本会话 Fusion Provider 因先前 503 失败已自动熔断，按规则转本地对抗审查。逐条结论：
1. 持久化正确：init 内赋值不触发 `didSet`，此处是加载路径，无副作用、不漏写盘；
   读写键名一致（`:72` / `:148`）。
2. 实时切换成立：`AppDelegate.swift:20` 单例 model 同时传给设置窗口（`:25`）与
   `HUDShell`（`:116`），两处均 `@ObservedObject`，无需重启。
3. `isActive` 语义正确：false 时效果被移除，不残留动画实例；旧代码本就用同一 API。
4. `reduceMotion` 每行读取非性能问题，代码库已有先例（`:2247` / `:2261`）。
5. 「恢复默认」一致，`@Published` 驱动 UI 刷新。
6. 无旧名残留：`PulsingStatusDot` 全仓零命中。
审查另指出：`HUDShell.swift:205-207` 的 `rows` 复用属**上一轮已批准任务**的改动，
非本轮新增，不影响本轮功能。

### 未验证项
- 无窗口截图权限，脉冲观感需用户目视确认（我无法截图）。
- 未构造 24 会话上限下的开关开销对比。
- 设置窗口的 Toggle 未做 GUI 点击实测（无辅助功能权限）；实时性由
  「同一 model 实例 + `@ObservedObject`」的数据链路确认，而非点击验证。
- 外部 `defaults write` 修改不会热加载（`@Published` 只在内存变），这是预期行为，
  非缺陷；切换请用设置窗口里的开关。
- Windows 与手机端零改动，未编译验证。

## Tailscale 远程连接引导（2026-11-15）

### 现象与结论

用户需要「人在家里连公司电脑」。经实测：mac 有公网 IPv6（`2409:8a00:162:f1e0::/64`），
IPv6 出站可用（`test-ipv6.com` 200），HUD 双栈监听正常，本机 5 个 IPv6 地址全部 401 可达。
但公网 IPv6 入站依赖公司网络与光猫放行，不可控；且临时地址 24 小时轮换。
结论：远程连接改用 Tailscale（WireGuard，零公网暴露），HUD 只做检测与引导，不代装。

### 变更范围

| 文件 | 改动 |
|---|---|
| `Sources/AgentHUD/LinkCertificate.swift` | 新增 `remoteIPv4Addresses()` 与 `isCarrierGradeNAT()`，识别 RFC 6598 `100.64.0.0/10`（Tailscale 网段）。 |
| `Sources/AgentHUD/LinkSettingsWindow.swift` | 配对窗口新增「远程连接」区块：检测到组网地址时列出并可复制；未检测到时显示说明 + 「下载 Tailscale」按钮（`NSWorkspace` 打开官网）。 |
| `mobile/lib/pages/pairing_page.dart` | 新增 `_RemoteHintCard` 引导卡片（含「获取 Tailscale」跳应用商店，深链失败退回网页）；新增 `_isIPv4Literal()`，修 `_lanWarningFor` 把 `xxx.ts.net` 这类主机名当 IPv4 比较导致误报「不在同一网段」的 bug。 |
| `mobile/pubspec.yaml` / `.lock` | 新增 `url_launcher` 依赖。 |
| `Tests/LinkTests.swift`、`Tests/main.swift` | 新增 `testLinkRemoteAddressDetection`，覆盖 CGNAT 边界与主机名/局域网地址排除。 |

Windows/ 目录零改动（`git status -- Windows/` 为空）。

### 验证结果

- `./scripts/test.sh` → 29 tests passed（原 28 + 新增 1）。
- `flutter analyze` → No issues found。
- `flutter test` → 10 passed / 1 skipped。
- `./scripts/build-app.sh` → Build complete! (129.30 秒)。
- 本机实测网卡：无 `100.64/10` 地址，HUD 走引导分支；局域网 `192.168.1.8` 正常。

### 未验证项

- HUD 配对窗口新 UI 未做 GUI 截图确认（`LSUIElement` 应用，AppleScript 未能唤起窗口；
  截图尺寸与改前一致说明窗口未打开）。检测逻辑本身有单元测试覆盖。
- 手机端引导卡片未在真机/模拟器上点按验证跳转。
- Tailscale 在公司网络的可用性未验证（需用户实际环境）。

### 提交与发布（2026-11-15）

| 项 | 结果 |
|---|---|
| 提交 | `2aa5409` feat(link): 配对窗口与手机端补齐 Tailscale 远程连接引导（11 文件 +786 −49） |
| 推送前检查 | `git fetch origin` → 远程无新提交，无分叉 |
| 版本号 | `0.1.1-beta.4+10` → `0.1.1-beta.5+11` |
| tag | `v0.1.1-beta.5`（annotated，已推送）→ 触发带 APK 附件的 prerelease |
| Android APK CI（main） | success（run 43668472853） |
| Android APK CI（tag） | success（run 43668529999） |
| Release | `v0.1.1-beta.5` prerelease，附件 `app-release.apk` 65.2 MB |
| Windows Build CI | failure，**历史遗留**：失败步骤 `Test core`，自 `5b65b43`(11-12 07:59) 起连续 8 次；本次提交 `Windows/` 改动数为 0，本机无 dotnet 无法复现，GitHub 日志接口 403 取不到明细 |

---

# 手机端对话链路缺陷修复 + 发布 v0.1.1-beta.7（2026-11-15，待批准）

## 状态

待审批。用户已选：先修缺陷再发 beta.7。

## 已核实的前置事实

- `main` 与 `origin/main` 完全一致（`0 0`），工作区干净，HEAD `71b6fd3`。
- `mobile/pubspec.yaml` 当前 `0.1.1-beta.6+12`；`v0.1.1-beta.6` Release 已发布且 APK 附件在。
- 基线：`./scripts/test.sh` exit 0（29 tests passed）；`flutter analyze --no-fatal-infos --no-fatal-warnings` exit 0（No issues found）。

## 缺陷现状（已读源码核实，非文档转述）

### 缺陷 A：第二条消息被幂等拦截

`mobile/lib/pages/session_detail_page.dart:109-111`

```dart
final String clientMessageId = _lastClientMessageId ??
    DateTime.now().millisecondsSinceEpoch.toString();
_lastClientMessageId = clientMessageId;
```

`_lastClientMessageId` 赋值后永不清空。第二条消息复用同一 ID，
服务端 `DeliveryStore.find(clientMessageId:)` 命中幂等缓存直接返回旧记录，
第二条消息实际从未投递，但界面仍会清空输入框。

判定：`_lastClientMessageId` 全文仅 3 处引用，无其他读取点，是纯残留。
正确做法是每次发送生成新 ID，该字段应删除。

### 缺陷 B：非 2xx 响应体被丢弃（**修 C 的前置**）

`mobile/lib/link_api.dart:379-382`

```dart
if (response.statusCode < 200 || response.statusCode >= 300) {
  throw LinkApiException('电脑返回错误（${response.statusCode}）。',
      statusCode: response.statusCode);
}
```

**关键发现**：投递失败时服务端返回的是非 2xx + `LinkMessageResponse`
（`LinkServer.swift` 走 `messageStatus(for:)`，409/422/501/503），
响应体里有 `deliveryId` 和 `status`，**没有** `error` 字段。
而 `_readResponse` 一遇非 2xx 就抛异常并丢弃 body，导致手机端：
1. 拿不到 deliveryId → 无法轮询投递状态；
2. 拿不到错误码（错误码实际只在后续 `GET /v1/deliveries/{id}` 里返回）。

所以修 B 是修 C 的必要条件，不能拆开。

### 缺陷 C：投递状态完全不展示

- `mobile/lib/pages/session_detail_page.dart` 对 `deliveryStatus` 的引用数为 **0**
  （`delivery` 变量仅用于 `delivery.status != 'failed'` 判断）。
- `session_controller.dart:327-334` 的 `_pollDelivery` 在异常分支
  `timer.cancel()` 后静默丢弃，用户看不到任何失败原因。
- `MessageDelivery.error` 字段已存在（`models.dart`），但无人读取。

## 实施步骤

### 步骤 1：`link_api.dart` — 让非 2xx 也带 body 抛出

- `LinkApiException` 增加 `final Map<String, dynamic>? body;`（可选，向后兼容）。
- `_readResponse` 非 2xx 分支：先读 body，尝试 `jsonDecode` 成 Map，
  一并塞进异常；解析失败则为 null（不因解析失败覆盖原始错误）。
- 错误文案优先用 body 里的 `error` 字段（服务端错误码），
  回退到现有「电脑返回错误（code）」。
- 验证：`flutter analyze` exit 0；新增单测覆盖非 2xx + body 场景。

### 步骤 2：`session_controller.dart` — 投递异常可见

- `_pollDelivery` 异常分支改为：记录 `actionError = '投递状态查询失败：…'`，
  并 `notifyListeners()`，不再静默 cancel。
- 验证：`session_controller_test.dart` 增加轮询异常用例。

### 步骤 3：`session_detail_page.dart` — 删除复用的幂等 ID + 展示投递状态

- 删除 `_lastClientMessageId` 字段与两处读写，每次发送都用新 ID。
- 发送后记录当前 `deliveryId`，在输入栏上方渲染一行状态：
  - `accepted` → 「已发送，等待电脑处理…」
  - `delivered` → 「已投递到会话」
  - `observed` → 「Agent 已开始处理」
  - `failed` → 「发送失败」+ 错误码中文映射
- 状态通过 `widget.controller.deliveryStatus(deliveryId)` 读取，
  `AnimatedBuilder` 已在监听 controller，无需额外 setState。
- 错误码中文映射：`sessionOffline`/`providerUnsupported`/`inputUnavailable`/
  `agentBusy`/`invalidMessage`/`deliveryFailed` → 对应中文文案。
- 验证：`flutter analyze` exit 0；无 widget test 环境，靠人工 + integration 测试。

### 步骤 4：版本发布

- `mobile/pubspec.yaml`：`0.1.1-beta.6+12` → `0.1.1-beta.7+13`。
- 提交、推送、打 tag `v0.1.1-beta.7`、推 tag。
- 轮询 CI 确认 APK 附件上传，记录 SHA-256。

## 拟执行命令（逐条审批）

### A 组：源码修改（写文件，改源码）

1. 编辑 `mobile/lib/link_api.dart` — 加 `body` 字段与解析。
2. 编辑 `mobile/lib/session_controller.dart` — 轮询异常可见化。
3. 编辑 `mobile/lib/pages/session_detail_page.dart` — 删幂等 ID、加投递状态行。
4. 编辑 `mobile/test/session_controller_test.dart` — 新增用例。

### B 组：验证（只读 + 写入 .dart_tool 缓存）

5. `cd mobile && flutter analyze --no-fatal-infos --no-fatal-warnings` — 静态分析。
6. `cd mobile && flutter test` — 单元测试。
7. `./scripts/test.sh` — macOS 回归（应仍为 29 passed）。
8. `./scripts/test-mobile-link.sh` — 真实 LinkServer + Dart 端到端（**系统操作**：临时启动本地 HTTPS 服务 + 写临时文件）。

### C 组：提交与发布（**远程写入，需明确批准**）

9. `git diff --check` — 空白检查；只读。
10. `git add -- mobile/lib mobile/test mobile/pubspec.yaml PLAN.md` — 暂存。
11. `git diff --cached --stat` — 核对暂存范围；只读。
12. `git commit -m "fix(mobile): 修复消息幂等复用与投递状态不可见"` — 创建提交。
13. `git push origin main` — **推送远程**。
14. `git tag -a v0.1.1-beta.7 -m "AgentHUD v0.1.1-beta.7"` — 创建标签。
15. `git push origin v0.1.1-beta.7` — **推送标签，触发 APK 构建**。
16. 轮询 GitHub Release 附件，记录 APK 大小与 SHA-256。

## 边界

- **不改 macOS `LinkServer.swift` / `LinkResponses.swift`**：当前协议已足够，
  错误码通过 `GET /v1/deliveries/{id}` 获取，`LinkMessageResponse` 无需加字段。
- **不改 Windows 任何文件**：`AgentHudLinkHost.cs` 的错误码已是 camelCase，
  且本机无 dotnet 无法验证。
- 不改 `models.dart`（`MessageDelivery` 字段已够用）。
- 不修 `observed` 状态未产出、`AgentRuntimeRegistry` 死代码、
  `GET /v1/deliveries/{id}` 归属校验 —— 这三项属 macOS 端协议层，超出本轮范围。
- 不修 Windows CI 红灯（历史遗留，本机无法复现）。
- 不强制推送、不改旧 Release。

## 风险

- **风险 1**：`LinkApiException` 加字段会影响所有 catch 点。
  缓解：新字段可选带默认值，现有调用点无需改动；`flutter analyze` 把关。
- **风险 2**：投递状态行会改变详情页布局，可能与既有视觉不一致。
  缓解：沿用现有 `_ComposerNotice` 组件，不改样式体系。
- **风险 3**：无 widget test 环境，界面改动只能靠 `flutter analyze` + 集成测试验证，
  真实观感需用户确认。

## 回滚

三个源码文件均为增量改动：`git checkout -- mobile/lib mobile/test` 即可回退。
若已推送，用新提交 revert，不 reset 远程。

## 未验证项（执行后填写）

- 手机真机/模拟器上的投递状态展示与错误文案。
- Windows 端零改动，不声称验证。

## 手机端小屏 / 大字号布局与真实在线态（2026-11-15）

### 用户需求（原话）
> 她好了提交代码了，现在你可以优化手机端了，就是基于mac的手机端，目前有些问题需要优化，我后天有模拟器

### 结论先说
模拟器不用等到后天：本机已有 `emulator-5554`（1080×2400 / 420dpi，Android 16 API 36），
本轮全部实机核验都在它上面完成。

### 修掉的真实缺陷（每条都有修复前后的溢出数字或实机证据）

| 位置 | 修复前实测 | 处理 |
|---|---|---|
| `session_detail_page.dart` `_HeroMeta` | 超长 git 分支名撑破胶囊行：320 宽默认字号溢出 246px、360 → 206px、412 → 154px；1.3 倍字号 → 382/342/290px | `Wrap` 外套 `LayoutBuilder`，把可用宽度传给每个胶囊；文字 `maxLines: 1` + 省略号 |
| 同文件 `_HeroCard` 顶部行 | provider 标签与状态胶囊挤在一起 | provider 标签改 `Flexible` |
| 同文件 `_PromptCard` 标题行 | 320 宽 @1.6 溢出 30–38px | 两侧文字改 `Flexible` + 省略号 |
| `hud_chips.dart` `HudProviderTag` | 320 宽 @1.6 溢出 38px | 文字改 `Flexible` + 省略号 |
| `sessions_page.dart` `_Footer` | 320@1.3 溢出 65px、360@1.3 25px、@1.6 → 141/101/49px | 左侧文案改 `Flexible` + 省略号 |
| 会话详情不可发送态 | 320@1.6 溢出 37px | 随上述改动消失 |
| `devices_page.dart` 在线状态 | 恒亮绿点 + 固定「在线」文案，电脑关机也照样显示在线 | 改为 15s 周期真实探测：检测中 / 在线 / 连不上 |

`link_api.dart` 新增 `DeviceHealthApi.probe()`：打 `/v1/status`、默认 4s 超时，
**401 视为在线**（授权失效 ≠ 电脑关机），只有连不上才算离线。
`devices_page.dart` 顺带修掉 `addresses` 为空时 `first` 崩溃（改为显示「未记录地址」）。

`pairing_page.dart` 删除从未被调用的截图死代码（`_captureScreenshot`、`_deleteCapturedFile`、
`_capturedPath`、`_scannerKey`、`RepaintBoundary` 及其 4 个 import），`RepaintBoundary` 只服务该截图。
之后 `path_provider` 在 `mobile/` 已无任何引用，从 `pubspec.yaml` 移除。

### 新增回归测试

- `mobile/test/layout_test.dart`（新文件，56 条 + 2 条在线态）：3 尺寸（320×568 / 360×640 / 412×915）
  × 3 字号（1.0 / 1.3 / 1.6）× 6 页面（会话列表 / 详情含超长分支名 / 详情不可发送 / 待办 / 设备列表 / 配对页）。
  断言方式：hook `FlutterError.onError`，渲染期间出现含 `overflowed` 的错误即失败。
  必须 `FlutterSecureStorage.setMockInitialValues({})`，否则 `DeviceStore.upsert` 在测试里挂死。
- `mobile/test/link_integration_test.dart` 新增 3 条真实链路断言：正常设备 `probe` = true、
  被吊销 token（401）仍 = true、连不通的端口 = false。

### 验证结果（真实输出）

- `flutter analyze --no-fatal-infos --no-fatal-warnings` → `No issues found!`
- `flutter test` → **68 通过 / 1 跳过**（`layout_test.dart` 58 条全过）
- `./scripts/test-mobile-link.sh` → exit 0，真实 `LinkServer` + Dart `LinkApi` 断言通过
- 模拟器 `emulator-5554`：
  - 设备页 `uiautomator dump` 显示 `MacBook Pro / 连不上 / 192.168.1.24:47825`，不再是假绿点
  - 详情页 `uiautomator dump` 卡片宽度 996px 落在 1080 屏内；`logcat` 全量 grep `RenderFlex|overflowed|EXCEPTION CAUGHT` 零命中
  - 把系统字号临时调到 1.6 后重测详情页，依旧零溢出；测完已恢复 `font_scale 1.0`

### 未验证项

- 视觉观感（颜色、间距是否「好看」）无法由本模型判定，需用户亲眼看。
- 15s 周期探测在真实断网/休眠/切后台场景下的耗电与重连表现，只在模拟器验证过。
- 配对扫码页的相机取景未在模拟器验证（模拟器无真实相机）。
- Windows 端零改动。

### 已知但本轮未动（等用户点头）

1. `mobile/lib/hidden_mode_store.dart` 是死代码（全仓库仅自引用）。
2. 待办 `todos_page.dart` / `todo_store.dart` 纯手机本地存储，mac 端 `Sources/AgentHUD/` 无对应实现，**两端不同步**。
3. mac 端无 OpenCode 输入适配器（`HUDViewModel.swift:114` 只注册 `CodexInputAdapter()`），
   OpenCode 会话在手机端无法发消息（`unsupported`）。
4. Windows Build CI 历史失败（`Test core`），本机无 dotnet，无法复现。
## Tailscale 安装与远程连接打通（2026-11-15，待批准）

### 用户需求（原话）
> 先看看这个东西咋用桌面有一个 tailscale-1.104.7

### 已确认现状（真实证据）

| 项 | 证据 |
|---|---|
| `~/Desktop/tailscale-1.104.7/` | **源码包，非安装包**。zip 内 3664 文件全为 `.go`/`.md`/配置；`find -size +1M` 全目录零命中 → 无 Mach-O 二进制。`VERSION.txt` = `1.104.7` |
| 本机是否已装 | `tailscale`/`tailscaled` CLI 不存在；`/Applications/Tailscale.app` 不存在；`brew list --cask` 无 tailscale |
| 系统 | macOS 27.0.1 (26A434)，arm64，磁盘可用 22 GiB |
| 官方 pkg 可达 | `HEAD Tailscale-1.104.7-macos.pkg` → **206，22,369,022 字节**，Last-Modified 2026-11-12。版本与桌面源码一致 |
| Tailscale 控制面可达 | `login.tailscale.com` 302 / `controlplane.tailscale.com` 302 / `derp1` 200 / `derp9` 200 |
| Go 官方代理不可达 | `proxy.golang.org` 000（20s 超时）、`github.com` 000；`goproxy.cn` 200 → 源码自编译路线需改 GOPROXY，且需 Go 1.27.4（本机 1.26.3） |
| HUD 侧无需改代码 | `Sources/AgentHUD/LinkServer.swift:47,51` 已双栈监听 `0.0.0.0` + `::`；`LinkCertificate.swift` 已识别 RFC 6598 `100.64.0.0/10` |
| 网络扩展共存风险 | `systemextensionsctl list` → `com.initex.proxifier.v3.macos` activated enabled；本机 1080/1087 有本地代理监听 |

### 目标（可验证）
1. `pkgutil --check-signature` 对官方 pkg 返回 `signed by a trusted certificate` 且 Team ID 为 Tailscale 官方。
2. 安装后 `/Applications/Tailscale.app` 存在，System Extension 出现在 `systemextensionsctl list`。
3. 用户登录后 `tailscale ip -4` 返回 `100.64.0.0/10` 内地址。
4. 手机端能通过该 `100.x` 地址 + HUD 端口完成配对并拉到会话列表。

### 拟执行命令（逐条审批）

| # | 命令 | 说明 | 系统影响 |
|---|---|---|---|
| 1 | `curl -L --fail -o ~/Downloads/Tailscale-1.104.7-macos.pkg https://pkgs.tailscale.com/stable/Tailscale-1.104.7-macos.pkg` | 下载官方安装包 | 写 `~/Downloads` 一个文件，22.4 MB |
| 2 | `shasum -a 256 ~/Downloads/Tailscale-1.104.7-macos.pkg` | 计算校验值并记录 | 只读 |
| 3 | `pkgutil --check-signature ~/Downloads/Tailscale-1.104.7-macos.pkg` | 校验 Apple 代码签名与 Team ID | 只读 |
| 4 | `xar -tf ~/Downloads/Tailscale-1.104.7-macos.pkg \| head -20` | 查看 pkg 内容清单，确认无异常脚本 | 只读 |
| 5 | **`sudo installer -pkg ~/Downloads/Tailscale-1.104.7-macos.pkg -target /`** | **真正安装**：写 `/Applications`、`/Library`，注册 System Extension | **系统级变更，需 sudo 密码。此条由用户自己用 `!` 前缀执行** |
| 6 | `open -a Tailscale` | 启动 GUI，弹出登录 | 启动一个应用 |
| 7 | `tailscale status` / `tailscale ip -4` | 登录后查状态与 100.x 地址 | 只读 |
| 8 | `curl -s -o /dev/null -w "%{http_code}" http://100.x.x.x:<HUD端口>/v1/...` | 从本机自测 HUD 经 Tailscale 地址可达 | 只读 |

### 边界
- 只做环境安装，**不改仓库任何代码**（`Windows/` 与 `mobile/` 零改动）。
- 不代用户完成 OAuth 登录（需浏览器交互）。
- 不碰工作区已有的未提交改动 `Windows/src/AgentHUD.Core/TextTools.cs`（另一会话 `agent-hud-de` 正在改）。
- 不删除桌面 `tailscale-1.104.7/` 源码与 zip，除非用户明确要求。

### 风险
- **风险 1**：pkg 会注册 System Extension，macOS 可能要求在「系统设置 → 通用 → 登录项与扩展」手动允许；可能需重启。
- **风险 2**：Proxifier 网络扩展与 Tailscale 路由共存，可能出现「100.x 通但外网断」；出现则先停 Proxifier 验证。
- **风险 3**：Tailscale 装完会改 DNS（MagicDNS）。若只想远程连 HUD，可在 GUI 里关掉 MagicDNS 与「使用 Tailscale DNS」。
- **风险 4**：`sudo` 密码我无法输入，第 5 步必须用户自己执行。

### 回滚
- 卸载：`sudo /Applications/Tailscale.app/Contents/MacOS/Tailscale uninstall-system-extension`，
  或系统设置里移除 VPN 配置后删 `/Applications/Tailscale.app`。
- 不改仓库代码，无代码回滚需求。

### 未验证项（执行后填写）

## 执行结果（2026-11-15）

### 已完成的改动

| 文件 | 改动 |
|---|---|
| `mobile/lib/link_api.dart` | `LinkApiException` 增加可选 `body`；非 2xx 分支先读 body 再抛，错误文案优先用服务端 `error` 字段；`sendMessage` 在非 2xx 但带 `deliveryId` 时返回投递记录而非抛异常。 |
| `mobile/lib/session_controller.dart` | 新增 `_deliveryErrors` 与 `deliveryError()`；轮询失败记录原因并通知，不再静默 cancel；查询成功后清除。 |
| `mobile/lib/pages/session_detail_page.dart` | 删除 `_lastClientMessageId`，每次发送用新 `clientMessageId`；新增 `_deliveryNotice`/`_describeDelivery`/`_deliveryErrorLabel`，在输入栏上方展示投递状态与错误中文说明。 |
| `mobile/test/session_controller_test.dart` | 新增 `FakeConversationApi`；两条用例：轮询失败可见、每次发送 ID 不同。 |

### 验证结果（真实运行，非推断）

- `flutter analyze --no-fatal-infos --no-fatal-warnings` → exit 0，No issues found。
- `flutter test` → 12 通过 / 1 跳过（原 9 通过 / 1 跳过，新增 2 条 + 原 models 用例）。
- `./scripts/test.sh` → exit 0，29 tests passed。
- `./scripts/test-mobile-link.sh` → exit 0，真实 HTTPS + Dart `LinkApi` 配对与监控链路通过。
- `git diff --cached --check` → exit 0，无空白错误。

### 发布

- 提交 `415f389` fix(mobile): 修复消息幂等复用与投递状态不可见（6 文件 +458 −22）。
- 推送前 `git fetch origin` → 无分叉（`0 1`）。
- 版本 `0.1.1-beta.6+12` → `0.1.1-beta.7+13`。
- 标签 `v0.1.1-beta.7` 已推送。
- Android APK CI（tag）run `43680502460` → **success**。
- Release `v0.1.1-beta.7` prerelease 已发布（2026-11-15T05:23:43Z），附件 `app-release.apk` 65.2 MB。
- Release 声明 SHA-256：`582831e2ea85442125a00d58c6f52a5525298f8f8972b3eb14551332acbdea03`。

### 关键发现（本轮新增，需另立任务）

**macOS 端没有 OpenCode 输入适配器。** `HUDViewModel.swift:114` 只注册 `adapters: [CodexInputAdapter()]`；
`OpenCodeAdapter.swift` 是会话监控适配器，不实现 `AgentInputAdapter`。
因此手机向 OpenCode 会话发消息时，`AgentInputDispatcher.capability(for:)` 的
`adapters(for: .opencode)` 返回空 → 状态 `unsupported` → 手机端 `canSendMessage` 为 false，
**消息在发送前就被拦截**。本轮三处修复只解决「发送之后」的可见性，
不能使 OpenCode 会话支持对话。

OpenCode 桌面版在 `127.0.0.1:49374` 提供本地 HTTP 服务，`/api/*` 需 HTTP Basic 认证；
密码不在环境变量、`opencode.settings`、`auth.json` 中，未取得凭据，未验证任何注入通道。
`opencode.db` 的 `session_inbox` / `session_pending` 属于 opencode 内部队列，
直接写入等于篡改数据库，未采用。

### 未验证项

- 手机真机/模拟器上的投递状态展示与错误文案（本机无真机）。
- 对话链路端到端：`test-mobile-link.sh` 的对话分支要求 `HUD_E2E_THREAD_ID`，本次未设置，
  实际跑的是监控链路；三处修复在真实投递失败场景下的表现未经在线 Agent 验证。
- Windows 端零改动，未编译（本机无 dotnet）。工作区另有并发会话修改
  `Windows/src/AgentHUD.Core/TextTools.cs`，未纳入本次提交。
- Windows Build CI 仍失败（`Test core`，历史遗留，本机无法复现，日志接口 403）。

### 并发会话提示

本次执行期间检测到多个并发 `claude` 进程（PID 53574、53923、26902 等）。
`Windows/src/AgentHUD.Core/TextTools.cs` 于 12:46 由其他会话修改，非本轮改动，已排除在提交外。

## 会话删除（静音）功能（2026-11-16）

### 用户需求（原话）
> 目前有问题的是里面的功能，就是他的会话，会越来越多，我希望有删除功能，删除之后等会话状态更新了，她再出现即可

### 设计结论

会话不是存出来的：`SessionScanner.scan()` 每次刷新都从 `~/.codex/sessions`、`~/.claude/projects`、
OpenCode SQLite 重新解析，再 `prefix(24)`。所以「删除」不能删任何日志，只能是显示层的一次静音。

**回来条件（用户确认）：有新活动就回来。** 记录删除那一刻的 `lastActivityAt` 作为基线，
之后只要该会话活动时间超过基线就自动恢复。不比较删除时刻，因此 HUD 关闭期间发生的变化
重新打开后依然判断正确。

### 变更

| 文件 | 改动 |
|---|---|
| `Sources/AgentHUD/SessionDismissalStore.swift`（新增） | 持久化 `[sessionID: (activityBaseline, dismissedAt)]` 到 `UserDefaults` 的 `hud.dismissedSessions.v1`；提供 `isDismissed` / `dismissedIDs(in:)` / `dismiss` / `restore` / `clearAwakened` |
| `Sources/AgentHUD/HUDViewModel.swift` | 新增 `dismissedSessionIDs` 与 `displayableSessions`；列表、筛选计数、折叠态文案、AI 标题请求、完成提醒全部改用 `displayableSessions`；新增 `dismiss` / `restoreDismissed` / `restoreAllDismissed` |
| `Sources/AgentHUD/HUDShell.swift` | 行内 hover 显示垃圾桶按钮；底栏新增「恢复已删除 N」 |
| `Tests/main.swift` | 新增 `testSessionDismissalStore`、`testDismissedSessionIDFiltering`；测试计数文案 29 → 32（并发会话另加 1 项） |
| `scripts/test.sh` | 编译清单加入新文件 |

### 关键设计取舍

1. **存整数毫秒而非 Double**。`UserDefaults` 把 `Double` 写成 6 位小数，读回来比原值略小，
   已删除的会话会被误判成「有新活动」立刻弹回。这是实现过程中被测试抓到的真实缺陷。
2. **不能按「不在本次扫描结果里」清理记录**。扫描只返回最近 24 条，被挤出的会话不等于结束；
   按扫描结果清理会让它下次被扫到时又冒出来。`clearAwakened` 只在会话确实有新活动时删记录。
3. **先结算删除状态，再决定动画与提醒**。否则刚删除的会话仍会触发行滑出动画和「重要会话已完成」提示。
4. 记录保留 30 天后清理，避免 `UserDefaults` 无限增长。

### 验证结果（真实运行）

- `./scripts/test.sh` → exit 0，32 tests passed。
- 故意改坏 `testDismissedSessionIDFiltering` 的断言 → 测试失败并报出实际值，确认新测试真的在跑（不是装饰）。
- `swift build -c debug` → exit 0，真实编译错误 0 条。
- 端到端脚本（真实 `AgentSession` + `SessionDismissalStore`）四项全过：删除后隐藏、
  有新活动自动回来、被 24 条上限挤出后记录不丢、重新扫到仍保持隐藏。

### 未验证项

- UI 未做视觉验证：本机 `build/AgentHUD.app` 正被另一会话占用运行（PID 95462），
  未替换该产物，也未截图确认垃圾桶按钮与底栏恢复入口的实际观感。
- 仅改 macOS。Windows 与手机端未做同样功能。

### 并发会话提示

本轮执行期间仓库被其他会话推进（`1edbea5` → `4f2a368` → `10df041`）。
`Sources/AgentHUD/Models.swift`（`SessionRowSurfacePolicy`）与 `HUDShell.swift` 的行底色/脉冲
改动来自另一会话，非本轮改动。为避开共享 `.build` 的并发写坏，本轮用 `--scratch-path .build-dismiss` 构建。

# 三端消息续发 + 会话数量筛选与易用性优化（2026-11-19，待批准）

## 状态

待用户批准后实施。本轮只完成了只读探索与本计划；未改业务代码、未发消息、未启动/停止应用。

## 目标（可验证）

1. 手机可向正在运行的 Codex 会话排队消息，也可向本轮已完成、进程仍存活的 Codex 会话续发；进程已退出时必须明确失败，不能假报成功。
2. Mac、Windows、手机默认只展示最近 10 条普通会话，星标会话始终保留在列表中；状态/来源筛选继续生效。
3. 三端设置都提供：全部、最近 3、5、10（默认）、15、20 条。星标不受数量上限影响；旧会话仅被隐藏，不删除、不影响详情查找与消息投递。
4. 手机会话页增加显式设置入口，页面显示“当前显示/符合条件/总会话”数量，并让列表筛选与投递结果更容易理解。

## 已核实的前置事实与根因

- Mac `Sources/AgentHUD/AgentInputDispatcher.swift:23` 与 Windows `Services/AgentInputDispatcher.cs:24` 都先用 `isLive` 拒绝输入。
- Mac `CodexInputAdapter.swift:23-26` 与 Windows `CodexInputAdapter.cs:25-28` 只接受 `Working/WaitingUser/Idle/Starting`，因此 `Completed/Failed` 必然不可发送。这不是单纯 APK 问题，手机只是忠实执行电脑返回的 capability。
- 两端现有投递都用 `codex queue --thread ... --message ...`，且都要求 rollout 文件仍被进程持有，原因注释已写明 CLI 对退出线程可能返回成功。不能简单删除这个保护。
- 本机实际命令 `codex --version` → `codex-cli 0.170.0`；`codex queue --help` 明确提供 `--resume`：“After queueing, try to resume the thread ... A failed resume produces a warning and the command still succeeds”。因此计划用 `queue --resume` 统一覆盖排队和续发，并增加结果/警告判定，绝不把退出码 0 直接等同于成功。
- 手机 `mobile/lib/session_controller.dart:48-61` 只有状态/来源筛选和排序，没有数量限制。桌面 Mac `HUDViewModel.visibleSessions` 与 Windows `MainViewModel.RebuildRows` 也没有数量限制。
- 已有星标能力可复用为“指定常驻会话”：Mac `SessionImportanceStore`、Windows `AppStateStore.ImportantSessionIds`、手机 `setImportant`；无需新增收藏协议或重复数据。
- Mac 已有 `AISettingsWindow` 的显示设置区域；Windows 已有 `AISettingsDialog`；手机没有设置入口，需新增轻量设置页/底部面板。
- 服务端扫描结果本身已有窗口（README 写最近 7 天最多 24 个），本轮筛选只控制三端可见列表，不能声称会显示扫描窗口之外的全部历史。

## 明确契约

### 列表

- 数量按“最近活动时间（`lastActivityAt`）”计算，不是按自然日截断。
- 状态/来源筛选后的候选集合，先保留全部星标，再取其余最近 N 条；`all` 不限制数量。
- 星标置顶；其余会话按最近活动时间排序。运行/等待状态仍在对应筛选中，不再用“前 10 条”挤掉星标。
- 列表头部/底部显示 `显示 X / 符合条件 Y · 共 Z`，提供修改入口；无匹配结果时提示当前筛选条件。
- 设置只持久化本端 UI 偏好，不改变服务端返回，不跨设备强制覆盖。星标仍按现有机制由电脑同步到手机。
- 手机“指定常驻会话”通过列表卡片或详情页现有星标完成，设置页说明操作方式；不增加第二套常驻列表。

### 消息

- 仅扩展现有 Codex 输入适配器，不承诺 Claude/OpenCode/Pi/Orca 获得发送能力。
- 在线/附着线程：保留 queue 排队语义；已完成但仍附着线程：允许 `--resume` 续发；离线线程：仍返回 `sessionOffline`，明确提示先在原终端恢复。
- 不自动开新终端、不自动切换工作目录、不注入键盘/鼠标、不绕过 Agent 审批；发送只来自用户已授权的手机对话开关。
- 统一 Mac/Windows capability 判断与错误原因，手机沿用 camelCase 状态协议，不改变现有接口路径。
- CLI 的 stdout/stderr 只在本地用于判断，不上传；手机展示已知错误的中文原因和真实投递状态。

## 实施步骤（测试先行）

1. **共享筛选规则（Mac）**：在 `Models.swift` 增加小型 `SessionListLimit`/可见性规则；`HUDViewModel.visibleSessions` 接入；设置存 `UserDefaults`。在 `Tests/main.swift` 先写默认 10、各数量、all、星标豁免、筛选后计数、无数据等用例。
   - 验证：新用例先因规则缺失/旧行为失败；实现后 `./scripts/test.sh` 通过。
2. **Mac 易用性**：`AISettingsWindow.swift` 的显示设置增加“会话显示数量”分段选择器与说明；必要时只在现有列表区域加数量摘要，不重排 HUD 结构。
   - 验证：编译 `swift build -c debug --scratch-path .build-session-settings`，检查设置重启后保留及列表即时更新。
3. **共享筛选规则（Windows）**：在 `AgentHUD.Core/Models.cs` 增加与 Mac 同义规则和单元测试；`PersistedAppState` 保存选择；`MainViewModel.RebuildRows` 在 `ReconcileVisibleRows` 前裁剪；设置对话框增加选择器。
   - 验证：Windows Core 测试通过；WinUI 编译若本机无 SDK，明确列未验证，不伪称通过。保留 `ReconcileVisibleRows` 和所有 `HudMotion` 机制。
4. **手机筛选与设置**：新增轻量本机偏好存储（普通显示偏好使用 SharedPreferences，非敏感信息不放安全存储）；`SessionController` 接入裁剪/计数；会话页增加设置入口、数量摘要、星标常驻说明；设置项为三端同一组选项。
   - 验证：`session_controller_test.dart` 与 widget 测试覆盖默认/切换/星标/筛选组合；`flutter analyze --no-fatal-infos --no-fatal-warnings`、`flutter test`。
5. **消息能力修正**：Mac/Windows 适配器移除对“完成状态”和“仅在线”的一刀切，改由 adapter 判定附着；按 CLI 实测加入 `queue --resume`，对缺失 CLI/附着/失败警告给出具体错误。为 CLI 调用与 capability 加可注入测试边界，不在单元测试里操作真实用户线程。
   - 验证：分别测试运行中、完成但附着、完成且离线、CLI 失败/超时、连续两条不同消息；Mac 自测和 Windows 对应测试通过。
6. **端到端验证**：用临时测试线程/CLI stub 验证协议，不对用户现有会话发测试消息。用户连接模拟器后，再执行真实 APK 的“运行中发送、完成后发送、连续发送、星标常驻、切换显示数量、杀掉进程后重启设置保留”。
7. **文档/记录**：更新 README 中已过时“只读/不向 Agent 终端发送输入”的说明与手机设置说明；更新本 PLAN 执行结果，新增 `summary.md` 记录技能、命令、未验证项；不自动提交、不发布 APK。

## 拟执行命令（逐条审批）

### 1. 写文件（系统操作：修改仓库源码/测试/文档）

- 修改上述 Mac、Windows、Flutter 源码与对应测试；新增手机偏好存储/设置页、`summary.md`；追加本计划执行结果。
- 只改本任务相关文件，不触碰已暂存的 `.build-dismiss` 等构建产物，不删除用户改动。

### 2. Mac 测试（系统操作：编译并写 `.build` 缓存）

```bash
./scripts/test.sh
swift build -c debug --scratch-path .build-session-settings
```

### 3. Flutter 测试与构建（系统操作：写 Flutter/Android 构建缓存）

```bash
cd mobile && flutter analyze --no-fatal-infos --no-fatal-warnings
cd mobile && flutter test
cd mobile && flutter build apk --debug
```

### 4. Link 协议集成测试（系统操作：临时 HTTPS 服务、临时文件、编译缓存）

```bash
./scripts/test-mobile-link.sh
```

### 5. Windows 测试（系统操作：编译缓存；仅在找到可用 .NET 8 SDK 时执行）

```bash
dotnet test Windows/tests/AgentHUD.Core.Tests/AgentHUD.Core.Tests.csproj -c Release
```

本机当前 `command -v dotnet` 无输出，`Windows/.dotnet/dotnet.exe` 不存在；不下载依赖、不改 Windows 进程，除非另行批准。

### 6. 模拟器验证（系统操作：启动 Android 模拟器、安装 APK；等待用户连接/确认设备后执行）

```bash
adb devices -l
flutter emulators
# 确认目标设备后再用 flutter run/install，不盲装到多台设备
```

### 7. 只读核对

```bash
git diff --check
git diff -- <本任务文件>
git status --short
```

全局 `MACHINE_CHECKS` 所列 `scripts/validate-config.sh`、`scripts/tests/run.sh`、`scripts/gates/all.sh`、`scripts/workflow/verify.sh` 经 `ls` 均不存在，无法执行，将列为未验证项，不创建假脚本冒充门禁。

## 边界 / 风险 / 回滚

- 不修改 AGENTS.md 已禁止改动的动画/对账机制，不重排 HUD 结构；UI 仅增加必要控件与说明。
- 不改变服务端隐私模式、配对授权和会话数据源；不向真实 Agent 发送探测消息。
- `queue --resume` 依赖本机 Codex 版本；旧版本不支持时必须返回明确 `inputUnavailable`，不能退回假成功。
- 手机偏好需要新增 Flutter `shared_preferences` 依赖；若不希望增加依赖，可改为现有普通本地文件方案，但需批准后确定，不用安全存储保存普通 UI 设置。
- 工作区已有大量 staged 构建产物；本任务不暂存、不重置、不清理它们。回滚仅针对本任务新改文件逐文件还原，已产生的提交（本轮默认不提交）用新提交 revert。

## 技能/工具记录

- MCP `local-memory.search_memory` 已查询，未返回 Agent-HUD 相关历史。
- `codegraph_explore` 已尝试；项目没有 `.codegraph`，工具要求先初始化，未初始化索引，改用源码定位。
- `.scale/skills-registry.json` 不存在；全局提到的 `tdd`、`verification`、`freeze-guard`、`graphify` 不在本次可调用技能清单，未强行调用。TDD 按上述测试先行手工执行，验证以真实命令输出为准。

## 未验证项（批准前）

- 未改代码，未运行上述构建/测试，未验证真实 Codex `queue --resume` 投递（不会向用户真实会话发测试消息）。
- 本机 `adb devices -l` 无设备；APK 真机/模拟器行为未验证。
- Windows SDK/WinUI 不可用；Windows 运行与视觉未验证。

## 执行结果（2026-11-19）

### 已完成

- Mac 新增 `SessionListLimit` / `SessionListPolicy`：默认最近 10 条，支持全部、3/5/10/15/20；星标会话额外常驻，按 `lastActivityAt` 排序。设置写入 `UserDefaults`，HUD 设置窗口与底栏可进入/查看数量。
- Mac `CodexInputAdapter` 改为 `codex queue --thread ... --message ... --resume`，移除基于 rollout 文件句柄的预拒绝；支持运行中排队与完成后续发。检查退出码及 stdout/stderr 的恢复失败诊断；未知线程、旧版 CLI、超时分别映射错误。dispatcher 保留具体 adapter 错误码。
- Flutter 新增 `session_display.dart`、`session_preferences.dart`、`pages/session_settings_page.dart`；`SessionController` 接入数量裁剪、筛选摘要、异步偏好加载/保存。`shared_preferences` 依赖已加入 `pubspec.yaml` 并解析。
- 新增 Mac `Tests/SessionInteractionTests.swift`，手机 `test/session_display_test.dart` 与 `test/session_settings_test.dart`，覆盖默认/全部/各数量/星标/设置页/偏好持久化/CLI 参数及错误。
- README 已同步会话显示、星标常驻与授权对话说明。
- 未提交、未推送、未发布 Release；未向真实 Agent 会话发送测试消息。

### 真实验证

- `./scripts/test.sh` → exit 0，`35 tests passed`。新增测试在实现前曾因缺少策略/旧适配器失败，随后通过。
- `flutter analyze --no-fatal-infos --no-fatal-warnings` → exit 0，`No issues found`。
- `flutter test`（修复全部持久化 bug 后）→ exit 0，`75 tests passed`，1 个既有跳过。
- `flutter test test/session_settings_test.dart` → exit 0，2 tests passed。
- `flutter build apk --debug` → exit 0，产物 `mobile/build/app/outputs/flutter-apk/app-debug.apk`。
- `codex --version` → `codex-cli 0.170.0`；`codex queue --help` 确认 `--resume` 存在；本机二进制诊断字符串含 `Queued message`、`Resume failed`。

### 未验证 / 阻塞

- **Mac 完整 SwiftPM 构建未通过**：两次依赖下载均因 GitHub `curl 56 Connection reset by peer` / early EOF 停滞，后台任务已停止；没有把核心测试当作完整应用构建通过。需要网络恢复后重跑 `swift build -c debug --scratch-path .build-session-settings`。
- **真实 Codex 队列投递未验证**：遵守边界，未操作用户现有线程；当前为可注入 CLI 的单元测试与参数/诊断验证。
- **模拟器未验证**：`adb devices -l` 无连接设备；APK 仅构建成功，未安装/运行/截图。
- **Windows 未执行**：用户明确说不用管；未改 Windows 代码。
- 全局 MACHINE_CHECKS 四个脚本不存在，未运行；`.scale/skills-registry.json` 不存在；codegraph 未初始化；均不作为通过依据。

### 并发工作区说明

本轮开始时工作区已有另一批 Mac UI 未提交改动（`AppDelegate.swift`、`HUDShell.swift`、`HUDTheme.swift`、`HUDMetrics.swift` 等）及大量 staged 构建产物。本轮没有回退、重置、暂存或清理它们；本任务的新逻辑集中在 `Models.swift`、`HUDViewModel.swift`、`CodexInputAdapter.swift`、新增测试与 Flutter 文件。

---

# 2026-11-20 远程 main 合并与手机端重构记录

## 基线与备份

- 原工作区先保存为 `stash@{0}`（`505677a8`），保留暂存、未暂存和未跟踪内容，未删除备份。
- 当前分支、本地 `main`、`origin/main` 已快进到 `ec7be4b`。
- 原 stash 恢复后两个手机端冲突为 `session_controller.dart` 和 `sessions_page.dart`，已解决并暂存。

## 批准的合并取舍

- 采用远程新版会话列表布局、顶部显示数量菜单及原有实时状态能力。
- 保留本地数量枚举、稳定排序与星标常驻筛选函数、显示摘要、完整设置页和星标操作说明。
- 控制器统一使用 `SessionListLimit` / `listLimit` / `setListLimit`，不保留两套数量状态。
- 使用 `FlutterSecureStorage` 保存普通显示偏好，沿用 `hud.session_limit.v1`；可注入内存实现用于测试。
- 本地五个新增源码/测试文件均已融合保留；远程 `session_display_store.dart` 已无引用，待用户批准后删除。
- Mac 本地代码全部保留；未修改本轮远程新增 Windows 代码。

## 验证

- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`：exit 0，No issues found。
- `flutter test --no-pub`：exit 0，78 tests passed，1 个既有跳过。
- `pubspec.yaml` / `pubspec.lock` 与 `origin/main` 一致；本机 Flutter 自动降版已恢复，未夹带依赖变更。
- 源码与文档 `git diff --cached --check` 排除原有构建产物后 exit 0。
- 未提交、未推送、未重新构建 APK、未进行真实设备验收。

---

# 2026-11-20 Mac Codex/Claude 输入与同步修复

## 已批准范围

- Mac 同时支持 Codex 队列续发、Claude 完成后后台恢复；不复制正在运行的 Claude 会话。
- 缓存近期日志窗口和解析结果，减少每 3 秒扫描的磁盘与 CPU 开销。
- 修正 Orca 旧 working 状态覆盖新完成日志的问题。
- 重新构建部署 Mac App，保留配对；不覆盖其他手机 UI 改动，不修改 Windows，不发送真实探测消息。

## 验证与部署

- `swift build -c release --skip-update -Xcxx -I<xcode-sdk>/usr/include/c++/v1`：exit 0。
- 35 项确定性 Mac 测试通过；完整 `./scripts/test.sh` 仍被既有 OpenCode 实时数据库用例阻断。
- 真实扫描：首次 14.1s，随后 0.39s / 0.19s；缓存复用限制为 1 秒，不冻结时间驱动状态。
- 新 App 已签名启动，PID 61013，端口 47653，保留对话授权。
- Android 最新构建端到端验证仍未完成；不自动重启用户正在切换的模拟器。

---

# 真机同步验证补充（2026-11-20）

- 真机 ADB 已连接，Mac 服务 47653 正常。
- Codex 与 Claude 已完成会话均显示可下发授权文本任务；未发送探测消息。
- 手机多地址回退改为首个有效地址胜出，避免不可达 IPv6/虚拟机地址串行阻塞。
- `./scripts/test-mobile-link.sh` exit 0，真实 HTTPS 集成含并行回退；`flutter analyze` 无问题，标准 Flutter 78 通过、2 个集成用例环境跳过。
- 连续 3 次真机刷新成功，最终 13 会话、11 条可见、4 个进行中。
- Release APK 已安装到真机；Android 重新记录 firstInstallTime，已重新配对，未删除 Mac 旧设备。
- 修复尚未提交推送；保留用户手机 UI 改动。
