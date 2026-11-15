import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'device_store.dart';
import 'link_api.dart';
import 'models.dart';
import 'pages/devices_page.dart';
import 'pages/pairing_page.dart';
import 'pages/session_detail_page.dart';
import 'pages/sessions_page.dart';
import 'pages/todos_page.dart';
import 'session_controller.dart';
import 'theme.dart';

const _device = LinkedDevice(
  deviceId: 'device-preview',
  token: 'preview-token',
  instanceId: 'instance-preview',
  instanceName: 'MacBook Pro',
  fingerprint: 'AAAA',
  addresses: ['192.168.1.24'],
  port: 47825,
);

DateTime _ago(int minutes) =>
    DateTime.now().subtract(Duration(minutes: minutes));

final List<AgentSession> _sessions = <AgentSession>[
  AgentSession(
    id: 's1',
    provider: 'Claude',
    status: 'Working',
    confidence: 'High',
    title: '修复双端互通并验证配对流程',
    projectName: 'Agent-HUD',
    currentAction: '正在运行 flutter test 并在模拟器上做视觉验收',
    currentFiles: const [
      'mobile/lib/pages/sessions_page.dart',
      'mobile/lib/theme.dart',
    ],
    startedAt: _ago(42),
    lastActivityAt: _ago(1),
    completedAt: null,
    isLive: true,
    summary: null,
    gitBranch: 'main',
    gitChangedFiles: 14,
    gitInsertions: 386,
    gitDeletions: 122,
    isImportant: true,
    latestPrompt: PromptSnapshot(
      text: '手机版本的页面太丑了，优化一下，重构整体，搞的高级一点好看一点',
      sentAt: _ago(3),
      images: const [],
    ),
    conversation: const ConversationState(
      enabled: true,
      state: 'ready',
    ),
    runs: <TaskRun>[
      TaskRun(
        id: 'run-1',
        status: 'completed',
        objective: '重构手机端视觉层级',
        summary: '统一深色工作台配色，卡片改为低对比表面。',
        completedAt: _ago(20),
        actions: const ['重写 theme.dart', '收敛筛选样式'],
        filesChanged: const ['mobile/lib/theme.dart'],
      ),
    ],
  ),
  AgentSession(
    id: 's2',
    provider: 'Codex',
    status: 'WaitingUser',
    confidence: 'High',
    title: '合并前确认标题生成方案',
    projectName: 'dcm-web-v2',
    currentAction: '等待你确认是否按复用上一轮目标的方案执行',
    currentFiles: const [],
    startedAt: _ago(65),
    lastActivityAt: _ago(4),
    completedAt: null,
    isLive: true,
    summary: null,
    gitBranch: 'feature/title-ai',
    gitChangedFiles: 3,
    gitInsertions: 96,
    gitDeletions: 12,
    latestPrompt: PromptSnapshot(
      text: '但是这个标题命名还是有问题',
      sentAt: _ago(6),
      images: const [],
    ),
    conversation: const ConversationState(
      enabled: true,
      state: 'waitingUser',
    ),
  ),
  AgentSession(
    id: 's3',
    provider: 'OpenCode',
    status: 'Completed',
    confidence: 'Medium',
    title: '启动当前项目并检查端口 5182',
    projectName: 'dcm-web-v2',
    currentAction: '本轮处理已完成，可查看总结',
    currentFiles: const [],
    startedAt: _ago(120),
    lastActivityAt: _ago(26),
    completedAt: _ago(26),
    isLive: false,
    summary: '前端已在 5182 端口启动，接口代理与热更新正常。',
    gitBranch: 'main',
    gitChangedFiles: 0,
    gitInsertions: 0,
    gitDeletions: 0,
    latestPrompt: PromptSnapshot(
      text: '启动当前项目，端口为 5182 即可',
      sentAt: _ago(28),
      images: const [],
    ),
  ),
  AgentSession(
    id: 's4',
    provider: 'Pi',
    status: 'Failed',
    confidence: 'Low',
    title: '生成发布说明失败',
    projectName: 'Agent-HUD',
    currentAction: '上游返回 502，已停止重试',
    currentFiles: const [],
    startedAt: _ago(200),
    lastActivityAt: _ago(150),
    completedAt: _ago(150),
    isLive: false,
    summary: null,
    gitBranch: null,
    gitChangedFiles: null,
    gitInsertions: null,
    gitDeletions: null,
    latestPrompt: null,
  ),
];

class PreviewApi implements MonitoringApi {
  @override
  Future<MonitoringStatus> status(LinkedDevice device) async =>
      MonitoringStatus(
        revision: 3,
        instanceName: device.instanceName,
        privacyMode: false,
        serverTime: DateTime.now(),
        supportsRefresh: true,
        capabilities: const <String>{
          'write',
          'prompt',
          'images',
          'conversation',
        },
        addresses: device.addresses,
      );

  @override
  Future<SessionFetchResult> sessions(
    LinkedDevice device, {
    String? etag,
  }) async =>
      SessionFetchResult(etag: 'preview-etag', sessions: _sessions);

  @override
  Future<bool> refresh(LinkedDevice device) async => true;

  @override
  void close() {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeviceStore();
  await store.upsert(_device);
  final controller = SessionController(_device, api: PreviewApi());
  await controller.refresh(scan: true);
  runApp(
    ChangeNotifierProvider<DeviceStore>.value(
      value: store,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildHudTheme(),
        home: _PreviewShell(controller: controller),
      ),
    ),
  );
}

const String _previewPage = String.fromEnvironment(
  'PREVIEW_PAGE',
  defaultValue: 'sessions',
);

/// Preview shell: switches by `--dart-define=PREVIEW_PAGE=devices|todos|pairing`.
class _PreviewShell extends StatelessWidget {
  const _PreviewShell({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final Widget page = switch (_previewPage) {
      'devices' => const DevicesPage(),
      'todos' => const TodosPage(),
      'pairing' => const PairingPage(),
      'detail' => SessionDetailPage(
          controller: controller,
          session: controller.sessions.first,
        ),
      _ => SessionsPage(device: _device, controller: controller),
    };
    return page;
  }
}

/// Kept for direct detail-page preview via hot restart routes.
Widget previewDetail(SessionController controller, String id) =>
    SessionDetailPage(
      controller: controller,
      session: controller.sessions.firstWhere((s) => s.id == id),
    );
