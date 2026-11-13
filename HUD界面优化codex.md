# AgentHUD 界面优化与联调进度（Codex）

更新时间：2026-11-12

## 1. 当前结论

本轮完成了 macOS 会话卡片状态框、毛玻璃背景、展开尺寸设置、OpenCode 数据源接入，
以及 Android 模拟器联调环境的基础搭建。

当前应用和 Android 模拟器均在运行。Android 模拟器已改用 Mac 硬件 GPU，不再使用
软件渲染。手机端内网配对尚未完成，不能把当前状态描述为“联调已全部完成”。

## 2. 会话卡片状态框

最终规则：

- 只有标星会话才显示状态色边框。
- 启动中、工作中：蓝框。
- 已完成：绿框。
- 等待确认：黄框。
- 错误：红框。
- 未标星：不显示状态边框。
- 空闲、未知：不显示状态边框。

macOS 与 Windows 均使用独立的 `SessionOutlinePolicy` 统一判断，状态徽标、星标置顶
及完成会话过渡动画保持原有行为。Windows 未标星卡片的中性边框也已移除。

已补充普通/标星、工作/完成/等待/错误、空闲/未知等回归测试。

## 3. 毛玻璃背景

调整过程中先后验证了以下问题：

- 仅降低颜色透明度，视觉仍接近全白。
- 直接移除系统材质会透出清晰底层文字，影响阅读。
- 系统 `NSVisualEffectView` 材质层本身也会遮挡背景，不能只改颜色层。

最终实现：

- 使用 `.hudWindow` 系统磨砂材质。
- 材质层 `alphaValue` 为 `0.45`。
- 浅色遮罩为 `0.62`，深色遮罩为 `0.70`。
- 列表表面遮罩为 `0.82`。
- 原生容器和 SwiftUI 宿主视图背景显式清空。
- Windows 同步提高面板底色不透明度，高对比度模式保持不透明。

最终截图中，下层仅显示模糊光影，不再出现清晰文字穿透列表的问题。

## 4. 展开宽度与高度设置

macOS 在“AI 标题与显示设置”中增加宽度、高度滑杆，Windows 在设置对话框中增加
对应的 `NumberBox`。

- 默认尺寸：`424 × 620`。
- 宽度范围：`360–720`。
- 高度范围：`480–1000`。
- 支持恢复默认。
- 设置持久化保存。
- 收起尺寸保持不变。
- Windows 尺寸保存不依赖 AI 配置是否有效。

已实际拖动宽度至 `720`，并读取窗口边界确认宽度确实变为 `720`，随后恢复默认尺寸。

## 5. OpenCode 接入

本机 OpenCode 版本为 `1.19.5`，实际数据位于：

```text
~/.local/share/opencode/opencode.db
```

新增只读 SQLite 适配，覆盖：

- `session`：任务标题、项目目录和起止时间。
- `message`：用户与助手消息。
- `part`：文本、工具调用、文件、运行状态和错误。
- 标题、项目路径、最近用户输入、工具动作和 Git 上下文。
- 工作、等待、完成、错误状态。
- macOS、Windows 和手机端 Provider 图标、颜色及独立筛选。
- Orca 存在时合并 OpenCode 会话，避免被原有早退逻辑跳过。

实际数据中特别处理了三个兼容点：

- `part.message_id` 是数据库列，不在 JSON 内容中。
- `message` 表没有 `message_id`，查询时返回 `NULL`，只有 `part` 读取真实关联列。
- 工具输入的 `filePath` 需要显式提取，不能只依赖通用路径扫描。

Windows 使用 `Microsoft.Data.Sqlite`，并新增了对应 C# 适配器及测试。
OpenCode 使用青绿色标识，与 Codex 蓝色、Claude 橙色和 Pi 绿色区分。

实际应用已显示 OpenCode 的真实标题、项目名、文件改动数、错误状态和筛选入口。

## 6. Android 模拟器联调环境

已完成：

- 接受 Android SDK 许可证。
- 安装 Android Emulator `37.2.13`。
- 安装 Android 36、ARM64、Google APIs 系统镜像。
- 创建 AVD：`AgentHUD_Android`。
- 使用 Pixel 6 配置。
- 链接 Homebrew 安装目录到 `~/Library/Android/sdk`，使 Flutter 能识别模拟器和镜像。
- 使用 `flutter create --platforms=android .` 生成 Android 工程。
- 在 Manifest 中加入 `INTERNET` 和 `CAMERA` 权限，应用显示名改为 `AgentHUD`。
- 成功构建 `app-debug.apk` 并安装到 `emulator-5554`。
- 已启动 AgentHUD，看到设备列表和“关联电脑”页面。

初次启动曾遇到 GPU 上下文错误和软件渲染卡顿。最终已改为：

- GPU：`host`，已识别 Apple M1 Max 硬件 GPU。
- 分辨率：`720 × 1280`。
- 不再使用 `swiftshader_indirect` 软件渲染。
- ADB 设备：`emulator-5554`。

启动命令：

```bash
"$HOME/Library/Android/sdk/emulator/emulator" \
  -avd AgentHUD_Android \
  -gpu host \
  -skin 720x1280 \
  -no-audio \
  -no-snapshot-save
```

后续调试可运行：

```bash
cd /Users/wl/Desktop/Agent-HUD/mobile
flutter run -d emulator-5554 --debug
```

## 7. 内网配对现状

Mac 的局域网服务正在监听 `*:47653`。

Android 模拟器中的 `127.0.0.1` 指向模拟器自身，不是 Mac 主机。
本机联调应使用：

```text
10.0.2.2:47653
```

已打开 Mac 的“手机关联”窗口和 Android 的验证码页面。用户明确选择不用相机，
因此后续只需在 Mac 上重新生成六位码，再填入 Android 的验证码页面。

截至本文生成时，尚未填写最终验证码，也尚未确认模拟器内会话列表连接成功。
因此以下事项仍属于未完成：

- 完成模拟器与 Mac 的六位码配对。
- 验证会话列表、详情和 OpenCode 筛选在模拟器内显示。
- 验证 Flutter 热重载工作流。
- 验证二维码摄像头流程；本轮选择跳过，不影响内网验证码联调。

## 8. 验证记录

已执行并通过：

- macOS 解析、状态、标题、OpenCode 和局域网烟雾测试：`23` 项。
- Flutter 模型与会话控制器测试：`6` 项。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`：无问题。
- macOS Release 构建与 ad-hoc 签名：成功。
- Android `app-debug.apk` 构建与安装：成功。
- 实际界面检查：星标完成绿框、未标星无框、毛玻璃可读性、尺寸拖动及恢复、
  OpenCode 真实会话和筛选。

并行任务新增的 `HUDViewModel.refreshTask` 曾出现可选返回类型编译错误，已显式改为
`Task<Void, Never>` 后恢复完整构建。

未执行或未完成：

- Windows .NET 编译与测试。
- Windows 实机视觉效果。
- OpenCode 在 Windows 上的 SQLite 数据库实测。
- Android 真机安装、摄像头、Wi-Fi 和防火墙验证。
- 模拟器内网配对及热重载验收。

## 9. 工作区与分支状态

文档生成时，当前 `HEAD` 为：

```text
471c6a5 (tag: v0.1.0-beta.7, origin/main) feat(mobile): add hidden mode, todo list, and run history
```

本地 `main` 与 `origin/main` 同步。工作过程中存在多个并行任务，部分修改已经由
并行任务提交；本文只记录本轮界面优化和联调相关工作，不代表所有工作区改动均由
当前 Codex 会话完成。

生成本文时仍有未提交的 `PLAN.md`、`.artifacts/`、`mobile/.metadata`、`mobile/android/`
等本机或生成文件。本文本身也是未提交文档，未执行新的提交或推送。

## 10. 下次继续入口

1. 启动 macOS AgentHUD 和 `AgentHUD_Android`。
2. 在 Mac 的“手机关联”中重新生成六位码。
3. 在 Android 验证码页填写地址 `10.0.2.2`、端口 `47653` 和六位码。
4. 确认会话列表及 OpenCode 会话出现。
5. 使用 `flutter run -d emulator-5554 --debug` 进行后续页面热重载。
