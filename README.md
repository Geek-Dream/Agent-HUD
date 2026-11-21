# AgentHUD

> 看得见每个 Agent，不碰它们的工作。

[![Windows Build](https://github.com/Geek-Dream/Agent-HUD/actions/workflows/windows-build.yml/badge.svg)](https://github.com/Geek-Dream/Agent-HUD/actions/workflows/windows-build.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827)
![Windows 10+](https://img.shields.io/badge/Windows-10%20%2F%2011-2563EB)
![Read Only](https://img.shields.io/badge/local%20data-read--only-16A34A)

AgentHUD 是一个本地优先的 coding agent 常驻浮窗。它集中展示 Codex、
Claude Code、OpenCode 和本地 Orca 会话的实时状态、任务标题、完成总结、Git 上下文与历史记录，
但不会启动、停止、审批或控制任何 Agent。

## 核心能力

- 常驻桌面并始终置顶，支持快速展开、收起和拖动锁定。
- 展示工作、等待、完成和错误状态，并按 Codex、Claude、Pi、OpenCode 等 Agent 筛选。
- 自动读取最近会话，显示用户目标、Agent 动作、耗时、项目路径和只读 Git 上下文。
- 完成记录支持分页加载。星标会话始终置顶，可按住星星拖到另一张星标卡片前调整顺序，
  手动顺序持久化；普通会话按工作、等待、完成、错误分组，同组保持稳定身份顺序。
- 星标运行卡片显示 Agent 配色的激光边框；星标完成未读显示同色背景呼吸，非星标
  完成只提示边框。查看后停止背景强提醒。其他 Agent 的星标完成会提醒顶部胶囊，
  悬停显示任务和完成摘要，点击仍按正常规则切换筛选。
- macOS 监听本地会话日志和状态数据库变更并立即扫描，保留 10 秒兜底刷新。
  设置中可分别开启星标完成的系统横幅、非星标完成的纯通知中心记录；默认均关闭。
- 提供原生（跟随系统浅色/深色）、晨雾、青瓷、星光、霓虹共五种主题、六种外观。
- macOS 重复启动会激活现有实例，避免多个 HUD 同时监听和堆积。
- 展开面板支持轻度透明背景，并可在设置中调整宽度和高度，上限为 720 × 1000。
- 会话列表默认显示最近 10 条；Mac 与手机设置可选择全部、最近 3/5/10/15/20 条。
  星标会话始终常驻，不占数量上限，也不会删除历史记录。
- Codex 会话支持在授权后通过队列续发消息；恢复失败会显示真实错误，不会假报已投递。
- 运行中的会话完成后向右滑出，再从列表底部平滑渐入。
- 支持手动修改标题，也可通过 OpenAI 兼容接口生成更易读的任务标题。
- 支持查看用户原始输入和会话图片，并提供可缩放、可切换的图片预览。
- 支持隐私模式，一键隐藏标题、路径、动作和总结。
- macOS 使用菜单栏常驻，Windows 使用系统托盘常驻。

## 平台支持

| 平台 | 界面 | 最低版本 | 后台形态 |
| --- | --- | --- | --- |
| macOS | SwiftUI + AppKit | macOS 14 | 菜单栏 |
| Windows | WinUI 3 | Windows 10 1809 | 系统托盘 |

Windows 11 下会优先启用 Mica，不可用时回退到 Acrylic。界面同时提供浅色、深色和
高对比度资源，并尽量保持与 macOS 版一致的布局和交互。

## 快速启动

### macOS

```bash
swift run AgentHUD
```

构建可直接打开的应用包：

```bash
./scripts/build-app.sh
open build/AgentHUD.app
```

安装桌面启动器：

```bash
./scripts/install-launcher.sh
```

### Windows

首次启动会自动下载官方 .NET 8 SDK 到 `Windows\.dotnet`，不需要管理员权限，
也不会修改系统级环境变量。该过程需要联网，首次下载和构建通常需要几分钟。

直接双击：

```text
Windows\start-agent-hud.cmd
```

或手动构建并启动：

```powershell
Windows\build.ps1 -Configuration Release
Windows\start-agent-hud.cmd
```

首次启动会自动准备 .NET 8 SDK、构建应用并打开 AgentHUD。
`start-agent-hud.cmd` 启动应用时不会保留控制台窗口。若需要手动构建，也可以安装
.NET 8 SDK 后运行 `Windows\build.ps1`。
更新源码后再次启动时，如果构建产物早于源码，启动器会自动重新构建。

如果应用启动后立即退出，启动器会显示退出码，并打印
`%LOCALAPPDATA%\AgentHUD\startup-error.log` 中的启动错误。

## 手机监控与会话管理

Windows 标题栏或托盘菜单中的“手机关联”会生成两分钟有效的二维码和六位验证码。
手机与电脑位于同一局域网时，可以通过 `mobile/` 中的 Flutter App 关联设备并查看会话状态。
每台设备使用独立、可撤销的令牌，连接层需要 .NET 8 的 ASP.NET Core 运行时；
启动器已同步检查该运行时。

对话能力需要电脑端单独授权。手机会话页的「会话显示设置」可选择全部、最近 3/5/10/15/20 条，
默认最近 10 条；在会话卡片或详情页点星标即可指定常驻会话。设置只保存在本机，不修改会话日志。
协议见 `docs/lan-monitoring.md`，手机构建说明见 `mobile/README.md`。
macOS 菜单栏同样提供“手机关联”，对应 Swift 实现见 `docs/macos-lan.md`。

## 数据来源

- Codex：`~/.codex/sessions/**/*.jsonl`
- Claude Code：`~/.claude/projects/**/*.jsonl`
- OpenCode：`~/.local/share/opencode/opencode.db`（只读 SQLite）
- Orca：读取其本地会话元数据
- Git：仅执行 `rev-parse`、`branch`、`status`、`diff` 等只读命令

默认展示最近七天内有活动的会话，最多 24 个。`继续`、`确认`、`continue` 这类
追问不会覆盖会话原本的实质任务标题。

AgentHUD 不安装 Agent hooks，不修改 `~/.codex`、`~/.claude`、OpenCode 数据或项目配置，不会自动提交、合并、回滚或清理 Git 改动。

## AI 标题

AI 标题默认关闭。打开 HUD 标题栏的设置按钮，或从菜单栏选择 `AI 标题设置...`，
然后填写：

- OpenAI 兼容 API Base URL
- Chat Completions 模型名称
- API Key

标题优先级为：

1. 用户手动修改的标题
2. AI 根据最近一次有效输入生成的任务总结
3. 本地规则生成的确定性标题

当输入包含本地或内嵌图片时，最多六张图片会作为 OpenAI 兼容的多模态内容发送，
帮助模型理解用户意图。AI 不可用、超时或返回无效内容时，会自动回退到本地标题。

macOS 的 API Key 保存在 Keychain。Windows 的 API Key 保存在 Windows Credential
Manager。密钥不会写入仓库、日志或构建产物。

## 开发与验证

运行 macOS 解析器与标题逻辑测试：

```bash
./scripts/test.sh
```

构建 Debug 和 Release：

```bash
swift build -c debug
swift build -c release
```

Windows 核心测试与构建：

```powershell
dotnet test Windows\tests\AgentHUD.Core.Tests\AgentHUD.Core.Tests.csproj -c Release
Windows\build.ps1 -Configuration Release
```

GitHub Actions 会在 `windows-latest` 上运行 Windows Core 测试、编译 WinUI 项目，
并上传 x64 构建产物。

## 项目结构

```text
Sources/AgentHUD/             macOS SwiftUI 应用
Windows/src/AgentHUD.Core/    跨平台会话解析与共享模型
Windows/src/AgentHUD.Windows/ WinUI 3 应用
Tests/                        macOS 快速验证
Windows/tests/                Windows Core 单元测试
packaging/                    应用包与启动器配置
scripts/                      构建、测试和安装脚本
```

## 已知限制

- 当前主要支持 Codex、Claude Code、Pi、OpenCode 和 Orca 的本地会话格式。
- 会话状态来自本地日志推断，无法确认时会标记为未知或推测。
- macOS 开发机无法编译 WinUI。Windows 端最终视觉和运行时行为建议在 Windows 11
  实机或 GitHub Actions 产物中确认。
- 完整历史搜索、全局快捷键和更多 Agent 适配器仍在后续计划中。
