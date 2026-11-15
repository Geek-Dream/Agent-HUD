# AGENTS.md — Agent-HUD 工作约束

> 本文件对本仓库及其子目录下的所有 Agent 会话生效。新增/修改约束请追加，不要删除既有条目。

## 一、HUD 进程管理（必须遵守）

本项目是常驻托盘应用，**点关闭按钮不会退出进程**（`AppWindow_Closing` 里 `args.Cancel = true` + `HideToTray()`），且 `App.xaml.cs` 没有单实例保护。因此反复启动会堆积大量后台实例，表现为“一堆 HUD 卡死”。

### 规则

1. **改代码/验证前，先清理旧实例**：

```powershell
Get-Process -Name 'AgentHUD.Windows' -ErrorAction SilentlyContinue | Stop-Process -Force
```

2. **同一时刻最多保留 1 个实例**。启动新实例前必须确认上一步已清空。
3. **验证完立即关闭**，不要留在后台：

```powershell
Get-Process -Name 'AgentHUD.Windows' -ErrorAction SilentlyContinue | Stop-Process -Force
```

4. **不要用点击 X 的方式关闭**——它只会进入托盘，进程仍在。
5. 每次启动/关闭后确认结果：

```powershell
@(Get-Process -Name 'AgentHUD.Windows' -ErrorAction SilentlyContinue).Count
```

6. 多个构建输出目录（`Windows/ui-build/binNN/`）会让“当前在跑的是哪个版本”变得模糊。验证时显式记录使用的 `binNN` 路径。

## 二、Windows 环境注意事项

1. **.NET 用仓库自带的**：`Windows/.dotnet/dotnet.exe`，不要用系统 `dotnet`。
2. **PowerShell 输出中文易乱码**。读写源码时用 Python + 显式 `encoding="utf-8"`，或
   `[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding($false)))`。
   判断乱码不要看终端输出，要看文件本身：检查是否含 `U+FFFD` 或“锟斤拷”。
3. 仓库里的 `.xaml/.cs` 本身就是 UTF-8 无 BOM，**不要用 PowerShell here-string 直接改中文内容**。
4. **不要用 `python - <<'PY'` 形式**（PowerShell 不支持 heredoc），先把脚本写到 `.py` 文件再执行。

## 三、UI 验证流程

1. 构建：

```powershell
cd E:\My_File\Agent-HUD\Windows
.\.dotnet\dotnet.exe build src/AgentHUD.Windows/AgentHUD.Windows.csproj `
  -c Debug -p:Platform=x64 `
  -p:BaseOutputPath="E:\My_File\Agent-HUD\Windows\ui-build\binNN\"
```

2. 启动必须带 `--show`，否则直接进托盘。
3. 截图必须 DPI 感知（150% 缩放下物理像素 = 逻辑 × 1.5）：
   - `Windows/ui-build/probe/pw.ps1`：按当前尺寸抓图
   - `Windows/ui-build/probe/pw2.ps1`：先 `MoveWindow` 到 780×1350（520×900 逻辑）再抓图
4. `settings.json`（`%LOCALAPPDATA%\AgentHUD\settings.json`）中的 `expandedWidth/expandedHeight` 会覆盖默认值，注意旧值可能把窗口卡在很小尺寸。

## 四、不要改动的部分

以下已验证的机制，除非用户明确要求，否则不要破坏：

- `MainViewModel.ReconcileVisibleRows()` — 增量对账，消除列表闪烁
- `HudMotion.PlayRowEntrance()` + `SessionList_ContainerContentChanging` — 逐条入场动画
- `HudMotion.PlayEnterAsync/PlayExitAsync` — 页面推入/推出
- `HudMotion.PlayScalePop()` — 筛选回弹
- `HudMotion.PlayCardEntrance()` — 详情卡片错峰

UI 调整以像素级微调为主，不要重排结构。