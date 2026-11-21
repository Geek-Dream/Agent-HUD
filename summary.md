# Agent-HUD 会话筛选与续发任务 summary（2026-11-19）

## 完成内容

- Mac：新增会话显示数量策略（默认最近 10；全部/3/5/10/15/20），星标会话额外常驻；设置持久化到 UserDefaults；设置窗口和底栏可访问。
- Mac：Codex 输入改用 `codex queue --resume`，支持运行中排队与完成后续发；识别 CLI 恢复失败、未知线程、旧版 CLI、超时等错误，不将恢复失败显示为已投递。
- 手机：新增会话显示设置页、数量摘要、星标常驻说明；显示数量持久化；新增筛选/偏好/设置页测试。
- 文档：README、PLAN.md 已同步；Windows 按用户要求未改。
- 分支：`feature/session-scoping-and-resume`；未提交、未推送、未发布 Release。

## 验证结果（真实命令）

| 命令 | 结果 |
| --- | --- |
| `./scripts/test.sh` | exit 0，35 tests passed；有 1 个既有 Swift 6 并发警告（测试闭包捕获可变变量） |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | exit 0，No issues found |
| `flutter test` | exit 0，75 tests passed，1 个既有跳过 |
| `flutter build apk --debug` | exit 0，APK 已生成 |
| `git diff --check` | exit 0 |

APK：`mobile/build/app/outputs/flutter-apk/app-debug.apk`
大小：约 196 MiB
SHA-256：`e6afdeada4191bee1015f3e667f73d625498c9a71a782f8b4eea2c22c339f47c`

## 未验证项 / 阻塞

- Mac 完整 SwiftPM 构建未完成：两次下载依赖都遇到 GitHub `curl 56 Connection reset by peer` / early EOF；后台任务已停止。核心 Swift 测试通过，但不能据此声称完整应用构建通过。
- 未对真实 Codex 线程发送消息；CLI 使用可注入 stub 测试，避免修改用户真实会话。
- `adb devices -l` 无设备，APK 未安装、未运行、未截图。
- Windows 按用户要求跳过。
- 全局 MACHINE_CHECKS 四个脚本不存在；`.scale/skills-registry.json` 不存在；codegraph 未初始化，均未运行。
- 工作区原有 Mac UI 未提交改动及 staged 构建产物未回退、未暂存、未清理。

## 交付审计（2026-11-19 后续）

- 审计状态：`passed`（登记闭环完成，不代表产品真实环境验收）。
- 已登记：requirements、diff、behavior（Flutter 75 tests）、self_review、independent_review（本地对抗审查）。
- 独立 Fusion 不可用（导入错误）；Hook 外援因 DeepSeek 未登录未产生外部审查，未伪称独立复核。
- 审计脚本默认 tracker 路径缺失，使用内存绑定现有 tracker 策略；未修改安全策略文件。
- Mac 复测发现实时 OpenCode 用例失败：数据库存在 `session_message` / `session_v2` 新表，现有解析器读取旧表为空；这是既有数据源问题，未顺手修改适配器。
- 设置窗口内层固定高度已按批准同步为 690。
- 临时行为包装脚本：`/tmp/agent_hud_audit_flutter.py`（仅执行 flutter test 并输出计数）。



- 直接源码探索与测试先行实现；新增测试先于实现执行并观察到失败，再修复到通过。
- MCP local-memory 已查询，无 Agent-HUD 命中。
- AgentRelay 本地归档已查询，无匹配记录。
- codegraph 尝试后报告项目未初始化；改用源码读取/搜索。
- 未调用在线外援模型；本任务是已批准的直接实现，未满足必须求助的条件。

## 合并远程 main（2026-11-20）

- 原工作区完整备份于 `stash@{0}`（提交 `505677a8`），包括原有暂存内容和未跟踪文件；未 drop stash。
- `main`、当前分支及 `origin/main` 已同步到 `ec7be4b`；未提交、未推送。
- 手机端没有整边覆盖：保留远程新版会话页面和顶部快捷菜单，合入本地 `SessionListLimit`、独立筛选函数、显示摘要、完整设置页和测试。
- 持久化采用远程已有的 `FlutterSecureStorage`，复用存储键 `hud.session_limit.v1`；补入内存实现供测试。`pubspec.yaml` 和 `pubspec.lock` 与远程一致，不再引入 SharedPreferences。
- 本地设置页、筛选策略、偏好封装和两组测试均保留；远程 `mobile/lib/session_display_store.dart` 已由新偏好封装取代，经用户批准后删除。
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`：exit 0，No issues found。
- `flutter test --no-pub`：exit 0，78 tests passed，1 个既有跳过。
- `git diff --cached --check`（排除原有构建产物）：exit 0；两个手机端冲突已解决。
- 本轮未重新构建/安装 APK，未做真实设备验收；Mac 既有 OpenCode 实时数据库用例问题仍未修复。
- 发布前复测：完整 `./scripts/test.sh` 仍失败于 `testOpenCodeCurrentDatabase`；使用临时测试入口仅排除该实时数据库用例，其余 34 项通过，有 1 个 Swift 6 测试闭包并发警告。

## Mac 输入与同步修复（2026-11-20 后续）

- 新部署 `build/AgentHUD.app`：同时注册 Codex 与 Claude 输入适配器；Claude 完成后使用 `claude --bg --resume <session-id> <text>`，并设置真实项目工作目录；运行中明确拒绝复制会话。
- `LogFileReader` 共享日志窗口缓存；`SessionTranscriptParser` 在未变化且最多 1 秒内复用解析结果，避免时间驱动状态被缓存冻结。
- Orca 旧 `working` 不再覆盖更新的日志完成/失败/空闲状态；状态时间使用原始 Hook 条目的时间。
- 真实扫描基准：首轮约 14.1 秒建立缓存，第二次约 0.39 秒，第三次约 0.19 秒。
- 除既有实时 OpenCode 数据库用例外，35 项确定性 Mac 测试通过；新增 Claude 测试有可修复的 Swift 6 测试闭包并发警告。
- Release 构建使用项目现有 C++ 头文件兼容参数成功；已签名并启动新版，PID 61013，继续监听 47653，配对与对话授权数据保留。
- 尚未完成最新构建的 Android 真机/模拟器验收；用户手动切换模拟器，未再自动重启模拟器，也未向真实 Agent 会话发送探测消息。
- 当前 `mobile/lib/pages/sessions_page.dart` 有用户/其他会话的新 UI 改动，未纳入本轮修复、未覆盖。

### 真机验证与 Link 回退

- 真机 `A7EB6R6116001694` 已连接 Mac `192.168.0.43:47653`，新版 Mac 服务正常；13 个会话同步，最近 10 条加星标共显示 11 条。
- 已完成 Codex、Claude 详情均显示可下发授权文本任务；Claude 输入框曾实测可编辑，未发送测试消息。
- 手机多地址连接改为：先尝试最近成功地址，失败后并行尝试其他候选，首个有效响应胜出；仍保留证书指纹与授权错误处理。
- 真实 HTTPS 单文件集成测试通过，包含不可达 IPv6 与可用 IPv4 回退；Flutter analyze 无问题，标准测试 78 通过、2 个集成用例按环境跳过。
- 连续 3 次真机手动刷新成功；最终同步显示 13 个会话、4 个进行中，无多地址超时错误。
- 本机 Debug APK 与手机签名不同，改用 Release 构建；安装后 Android 记录了新的 firstInstallTime，配对已重新创建，未删除 Mac 旧配对。
- 真机安装包：`mobile/build/app/outputs/flutter-apk/app-release.apk`；本轮修复尚未提交或推送。
