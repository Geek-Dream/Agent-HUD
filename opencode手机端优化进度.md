# OpenCode 手机端优化进度

> 更新日期：2026-11-12
> 当前版本：`v0.1.0-beta.7+7`
> 对应提交：`471c6a5`

---

## 一、已完成工作

### 1. 待办列表（Todo List）

| 模块 | 文件 | 说明 |
|------|------|------|
| 数据模型 | `mobile/lib/todo_store.dart` | `TodoItem` 模型 + `TodoStore` 本地持久化（`flutter_secure_storage`） |
| UI 页面 | `mobile/lib/pages/todos_page.dart` | 待办列表页，支持增删改查、滑动删除 |
| 入口集成 | `mobile/lib/pages/sessions_page.dart` | 状态筛选增加紫色「待办」选项，激活时跳转 `TodosPage` |

- 待办是纯本地功能，不走 LAN 协议，各端独立存储。
- 筛选 UI 使用与其他状态筛选一致的切角科技边框 + 霓虹效果。

### 2. 隐藏模式（Hidden Mode）

| 模块 | 文件 | 说明 |
|------|------|------|
| 状态存储 | `mobile/lib/hidden_mode_store.dart` | `HiddenModeStore`（`flutter_secure_storage` 持久化） |
| UI 集成 | `mobile/lib/pages/sessions_page.dart` | 隐藏模式启用时 AppBar 显示「☰」待办按钮 |

- 隐藏模式状态持久化到本地，应用重启后保持。
- 入口由配对页面触发，状态管理已就绪。
- 用户明确：**消息发送功能不由 Agent 处理**。

### 3. 完成记录（Run History）

| 模块 | 文件 | 说明 |
|------|------|------|
| 数据模型 | `mobile/lib/models.dart` | `AgentSession` 增加 `runs: List<TaskRun>` 字段 |
| UI 展示 | `mobile/lib/pages/session_detail_page.dart` | 新增「完成记录」分区及 `_RunsList` 组件 |

- 展示内容：`objective`（目标）、`summary`（摘要）、`actions`（动作列表）、`filesChanged`（改动文件）、`completedAt`（完成时间）。
- 隐私模式下 runs 返回空数组，不暴露数据。

### 4. macOS 协议同步

| 文件 | 改动 |
|------|------|
| `Sources/AgentHUD/LinkModels.swift` | 新增 `LinkTaskRun` 结构体；`LinkMonitoringSession` 增加 `runs` 字段 |
| `Sources/AgentHUD/HUDViewModel.swift` | `monitoringSnapshot()` 将 `session.runs` 映射为 `LinkTaskRun` 后填充到快照 |

- 隐私模式下 runs 映射为空数组。

### 5. Windows 协议同步

| 文件 | 改动 |
|------|------|
| `Windows/src/AgentHUD.Link/MonitoringContracts.cs` | 新增 `MonitoringTaskRun` record；`MonitoringSessionSnapshot` 增加 `Runs` 字段 |
| `Windows/src/AgentHUD.Windows/ViewModels/MainViewModel.cs` | `GetMonitoringSnapshot()` 将 `session.Runs` 映射后传入快照 |

- Windows 代码为静态审阅，本机无 `dotnet`，未实际编译验证。

---

## 二、验证结果

| 验证项 | 结果 |
|--------|------|
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | ✅ 0 issue |
| `flutter test test/models_test.dart` | ✅ 4/4 通过 |
| `./scripts/test.sh` | ✅ 23/23 通过 |
| `./scripts/test-mobile-link.sh` | ✅ 1/1 通过 |
| `git diff --check` | ✅ 无空白错误 |

---

## 三、发布记录

| 版本 | 标签 | 状态 |
|------|------|------|
| `v0.1.0-beta.7+7` | `v0.1.0-beta.7` | ✅ 已推送，CI 构建中 |

- GitHub Actions 正在构建 APK。
- 前序版本：beta.6（IPv6 双栈）、beta.5（OpenCode 监控 + 跨平台 UI）、beta.4（手机同步优化）、beta.3（扫码修复）、beta.2（视觉动效）。

---

## 四、未验证项

- macOS `swift build` 因本地 C++ 头文件缺失未通过（与源码无关，需清理 DerivedData 或 SwiftPM 缓存后重试）。
- Windows 无 `dotnet`，未编译验证。
- 真机/模拟器运行、动画帧率、待办滑动手感、完成记录多端同步未验证。
- 隐藏模式触发入口（配对页面集成）需用户自行验证。

---

## 五、遗留问题 / 待办

- [ ] 真机验证：待办 CRUD、隐藏模式切换、完成记录展示。
- [ ] macOS 构建环境修复：清理 SwiftPM 缓存后重试 `swift build`。
- [ ] Windows 编译验证：在具备 `dotnet` 环境后编译验证。
- [ ] 待办多端同步（如需要）：当前为纯本地，暂不同步到电脑。

---

## 六、相关文件索引

```
mobile/
  lib/
    models.dart                  # AgentSession + TaskRun
    todo_store.dart              # TodoItem + TodoStore
    hidden_mode_store.dart       # HiddenModeStore
    theme.dart                   # 主题令牌（含待办紫色）
    pages/
      sessions_page.dart         # 筛选入口 + 隐藏模式按钮
      session_detail_page.dart   # 完成记录 _RunsList
      todos_page.dart            # 待办列表 UI

Sources/AgentHUD/
  LinkModels.swift              # LinkTaskRun + runs 字段
  HUDViewModel.swift            # monitoringSnapshot() runs 映射

Windows/
  src/AgentHUD.Link/
    MonitoringContracts.cs      # MonitoringTaskRun + Runs 字段
  src/AgentHUD.Windows/ViewModels/
    MainViewModel.cs            # GetMonitoringSnapshot() runs 映射
```
