import 'dart:typed_data';

import 'package:agent_hud_mobile/device_store.dart';
import 'package:agent_hud_mobile/link_api.dart';
import 'package:agent_hud_mobile/models.dart';
import 'package:agent_hud_mobile/pages/devices_page.dart';
import 'package:agent_hud_mobile/pages/pairing_page.dart';
import 'package:agent_hud_mobile/pages/session_detail_page.dart';
import 'package:agent_hud_mobile/pages/sessions_page.dart';
import 'package:agent_hud_mobile/pages/todos_page.dart';
import 'package:agent_hud_mobile/session_controller.dart';
import 'package:agent_hud_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 小屏 + 大字号下的布局回归测试。
///
/// 这些组合曾经真实溢出：会话详情页的超长 git 分支名会把胶囊行撑破
/// （320 宽、默认字号就溢出 246px），列表页底部状态行在 1.3 倍字号下溢出。
/// 断言方式是「渲染期间不允许出现 RenderFlex overflow」，比逐像素截图稳定。

const LinkedDevice device = LinkedDevice(
  deviceId: 'd1',
  token: 't1',
  instanceId: 'i1',
  instanceName: 'MacBook Pro 14 英寸',
  fingerprint: 'AB',
  addresses: ['192.168.1.24'],
  port: 47825,
);

AgentSession makeSession({
  String id = 's1',
  String provider = 'Claude',
  String status = 'Working',
  String title = '修复双端互通并验证配对流程',
  String action = '正在运行 flutter test 并在模拟器上做视觉验收',
  String? branch = 'main',
  int? changed = 14,
  ConversationState? conversation =
      const ConversationState(enabled: true, state: 'ready'),
  PromptSnapshot? prompt,
}) =>
    AgentSession(
      id: id,
      provider: provider,
      status: status,
      confidence: 'High',
      title: title,
      projectName: 'Agent-HUD',
      currentAction: action,
      currentFiles: const [],
      startedAt: DateTime.now().subtract(const Duration(minutes: 42)),
      lastActivityAt: DateTime.now().subtract(const Duration(minutes: 1)),
      completedAt: null,
      isLive: true,
      summary: null,
      gitBranch: branch,
      gitChangedFiles: changed,
      gitInsertions: 1,
      gitDeletions: 1,
      latestPrompt: prompt,
      conversation: conversation,
    );

class StubApi implements MonitoringApi, SessionActionsApi, DeviceHealthApi {
  StubApi(this.rows, {this.reachable = true});

  final List<AgentSession> rows;
  final bool reachable;
  int probeCount = 0;

  @override
  Future<MonitoringStatus> status(LinkedDevice d) async => MonitoringStatus(
        revision: 1,
        instanceName: d.instanceName,
        privacyMode: false,
        serverTime: DateTime.now(),
        supportsRefresh: true,
        capabilities: const {'write', 'prompt', 'images', 'conversation'},
        addresses: d.addresses,
      );

  @override
  Future<SessionFetchResult> sessions(LinkedDevice d, {String? etag}) async =>
      SessionFetchResult(etag: 'e', sessions: rows);

  @override
  Future<bool> refresh(LinkedDevice d) async => true;

  @override
  Future<bool> probe(LinkedDevice d, {Duration timeout = Duration.zero}) async {
    probeCount += 1;
    return reachable;
  }

  @override
  Future<String> setSessionTitle(LinkedDevice d, String id, String t) async => t;

  @override
  Future<bool> setSessionImportant(LinkedDevice d, String id, bool v) async => v;

  @override
  Future<Uint8List> promptImage(LinkedDevice d, String id, int i) async =>
      Uint8List(0);

  @override
  Future<MessageDelivery> sendMessage(
    LinkedDevice d,
    String id,
    String cid,
    String text,
  ) async =>
      MessageDelivery(
        deliveryId: 'x',
        clientMessageId: cid,
        status: 'accepted',
      );

  @override
  Future<MessageDelivery> deliveryStatus(LinkedDevice d, String id) async =>
      MessageDelivery(deliveryId: id, clientMessageId: '', status: 'delivered');

  @override
  void close() {}
}

/// 渲染 [child] 并把所有 RenderFlex overflow 断言为失败。
Future<void> expectNoOverflow(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required double scale,
}) async {
  final List<String> overflows = <String>[];
  final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String message = details.exceptionAsString();
    if (message.contains('overflowed') ||
        (details.context?.toString().contains('overflow') ?? false)) {
      final String creator =
          details.informationCollector?.call().firstOrNull?.toString() ?? '';
      overflows.add('$message $creator');
    }
  };
  addTearDown(() => FlutterError.onError = previous);

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(MaterialApp(theme: buildHudTheme(), home: child));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));

  FlutterError.onError = previous;
  expect(overflows, isEmpty, reason: '布局溢出：\n${overflows.join('\n')}');
}

void main() {
  // DeviceStore 走 flutter_secure_storage 的平台通道；测试里没有宿主，
  // 不注入内存实现的话 upsert 会永远挂起。
  setUpAll(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  final List<Size> sizes = <Size>[
    const Size(320, 568),
    const Size(360, 640),
    const Size(412, 915),
  ];
  const List<double> scales = <double>[1.0, 1.3, 1.6];

  for (final Size size in sizes) {
    for (final double scale in scales) {
      final String tag = '${size.width.toInt()}x${size.height.toInt()}@$scale';

      testWidgets('会话列表 $tag 无溢出', (WidgetTester tester) async {
        final StubApi api = StubApi(<AgentSession>[
          makeSession(
            prompt: PromptSnapshot(
              text: '手机版本的页面太丑了，优化一下',
              sentAt: DateTime.now(),
              images: const [],
            ),
          ),
          makeSession(
            id: 's2',
            provider: 'OpenCode',
            status: 'WaitingUser',
            title: '合并前确认标题生成方案，顺便检查一下打包脚本是否会漏掉资源文件',
            action: '',
            branch: 'feature/a-very-long-branch-name-for-testing',
            changed: 128,
          ),
        ]);
        final SessionController controller =
            SessionController(device, api: api);
        addTearDown(controller.dispose);
        await controller.refresh(scan: true);

        await expectNoOverflow(
          tester,
          SessionsPage(device: device, controller: controller),
          size: size,
          scale: scale,
        );
      });

      testWidgets('会话详情 $tag 无溢出（含超长分支名）', (WidgetTester tester) async {
        final StubApi api = StubApi(<AgentSession>[
          makeSession(
            branch: 'feature/a-very-long-branch-name-for-testing',
            prompt: PromptSnapshot(
              text: '手机版本的页面太丑了，优化一下',
              sentAt: DateTime.now(),
              images: const [],
            ),
          ),
        ]);
        final SessionController controller =
            SessionController(device, api: api);
        addTearDown(controller.dispose);
        await controller.refresh(scan: true);

        await expectNoOverflow(
          tester,
          SessionDetailPage(
            controller: controller,
            session: controller.sessions.first,
          ),
          size: size,
          scale: scale,
        );
      });

      testWidgets('会话详情（不可发送）$tag 无溢出', (WidgetTester tester) async {
        final StubApi api = StubApi(<AgentSession>[makeSession()]);
        final SessionController controller =
            SessionController(device, api: api);
        addTearDown(controller.dispose);
        await controller.refresh(scan: true);

        await expectNoOverflow(
          tester,
          SessionDetailPage(
            controller: controller,
            session: makeSession(
              conversation: const ConversationState(
                enabled: false,
                state: 'unsupported',
                reason: '当前 Agent 没有可用的输入通道，请回到电脑上继续对话。',
              ),
            ),
          ),
          size: size,
          scale: scale,
        );
      });

      testWidgets('待办 $tag 无溢出', (WidgetTester tester) async {
        await expectNoOverflow(
          tester,
          const TodosPage(),
          size: size,
          scale: scale,
        );
      });

      testWidgets('设备列表 $tag 无溢出', (WidgetTester tester) async {
        final DeviceStore store = DeviceStore();
        await store.upsert(device);
        await expectNoOverflow(
          tester,
          ChangeNotifierProvider<DeviceStore>.value(
            value: store,
            child: DevicesPage(
              healthApi: StubApi(const <AgentSession>[]),
            ),
          ),
          size: size,
          scale: scale,
        );
      });

      testWidgets('配对页 $tag 无溢出', (WidgetTester tester) async {
        await expectNoOverflow(
          tester,
          const PairingPage(),
          size: size,
          scale: scale,
        );
      });
    }
  }

  testWidgets('设备卡片显示真实在线状态', (WidgetTester tester) async {
    final DeviceStore store = DeviceStore();
    await store.upsert(device);
    final StubApi online = StubApi(const <AgentSession>[]);
    await tester.pumpWidget(
      ChangeNotifierProvider<DeviceStore>.value(
        value: store,
        child: MaterialApp(
          theme: buildHudTheme(),
          home: DevicesPage(healthApi: online),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(online.probeCount, greaterThan(0));
    expect(find.text('在线'), findsOneWidget);
  });

  testWidgets('设备卡片离线时不再谎报在线', (WidgetTester tester) async {
    final DeviceStore store = DeviceStore();
    await store.upsert(device);
    final StubApi offline = StubApi(const <AgentSession>[], reachable: false);
    await tester.pumpWidget(
      ChangeNotifierProvider<DeviceStore>.value(
        value: store,
        child: MaterialApp(
          theme: buildHudTheme(),
          home: DevicesPage(healthApi: offline),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('连不上'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
  });
}
