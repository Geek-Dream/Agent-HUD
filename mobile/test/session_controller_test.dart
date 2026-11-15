import 'dart:typed_data';

import 'package:agent_hud_mobile/link_api.dart';
import 'package:agent_hud_mobile/models.dart';
import 'package:agent_hud_mobile/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonitoringApi implements MonitoringApi {
  int revision = 7;
  int refreshCount = 0;
  int statusCount = 0;
  int sessionsCount = 0;
  int closeCount = 0;
  bool supportsRefresh = true;
  bool supportsConditionalRequests = true;
  List<String> addresses = const [];

  @override
  Future<MonitoringStatus> status(LinkedDevice device) async {
    statusCount += 1;
    return MonitoringStatus(
      revision: revision,
      instanceName: 'Mac',
      privacyMode: false,
      serverTime: DateTime.utc(2026, 11, 12),
      supportsRefresh: supportsRefresh,
      addresses: addresses,
    );
  }

  @override
  Future<SessionFetchResult> sessions(
    LinkedDevice device, {
    String? etag,
  }) async {
    if (supportsConditionalRequests && etag == 'content-$revision') {
      return SessionFetchResult(etag: etag);
    }
    sessionsCount += 1;
    return SessionFetchResult(
      etag: supportsConditionalRequests ? 'content-$revision' : null,
      sessions: [
        AgentSession(
          id: 'session-one',
          provider: 'Codex',
          status: 'Working',
          confidence: 'High',
          title: '同步测试',
          projectName: 'Agent-HUD',
          currentAction: '工作中',
          currentFiles: const [],
          startedAt: DateTime.utc(2026, 11, 12),
          lastActivityAt: DateTime.utc(2026, 11, 12),
          completedAt: null,
          isLive: true,
          summary: null,
          gitBranch: 'main',
          gitChangedFiles: 1,
          gitInsertions: 2,
          gitDeletions: 0,
          isImportant: false,
          latestPrompt: null,
        ),
      ],
    );
  }

  @override
  Future<bool> refresh(LinkedDevice device) async {
    refreshCount += 1;
    if (!supportsRefresh) return false;
    revision += 1;
    return true;
  }

  @override
  void close() {
    closeCount += 1;
  }
}

/// 带对话能力的假实现：可模拟投递状态查询失败，并记录每次发送的幂等 ID。
class FakeConversationApi extends FakeMonitoringApi
    implements SessionActionsApi {
  bool failDeliveryStatus = false;
  final List<String> clientMessageIds = [];
  final List<String> deliveryIds = [];

  @override
  Future<MonitoringStatus> status(LinkedDevice device) async {
    statusCount += 1;
    return MonitoringStatus(
      revision: revision,
      instanceName: 'Mac',
      privacyMode: false,
      serverTime: DateTime.utc(2026, 11, 12),
      supportsRefresh: supportsRefresh,
      capabilities: const <String>{'conversation', 'write', 'prompt', 'images'},
      addresses: addresses,
    );
  }

  @override
  Future<SessionFetchResult> sessions(
    LinkedDevice device, {
    String? etag,
  }) async {
    if (supportsConditionalRequests && etag == 'content-$revision') {
      return SessionFetchResult(etag: etag);
    }
    sessionsCount += 1;
    return SessionFetchResult(
      etag: supportsConditionalRequests ? 'content-$revision' : null,
      sessions: [
        AgentSession(
          id: 'session-one',
          provider: 'Codex',
          status: 'Working',
          confidence: 'High',
          title: '同步测试',
          projectName: 'Agent-HUD',
          currentAction: '工作中',
          currentFiles: const [],
          startedAt: DateTime.utc(2026, 11, 12),
          lastActivityAt: DateTime.utc(2026, 11, 12),
          completedAt: null,
          isLive: true,
          summary: null,
          gitBranch: 'main',
          gitChangedFiles: 1,
          gitInsertions: 2,
          gitDeletions: 0,
          conversation: const ConversationState(
            enabled: true,
            state: 'ready',
          ),
        ),
      ],
    );
  }

  @override
  Future<MessageDelivery> sendMessage(
    LinkedDevice device,
    String id,
    String clientMessageId,
    String text,
  ) async {
    clientMessageIds.add(clientMessageId);
    final String deliveryId = 'delivery-${deliveryIds.length + 1}';
    deliveryIds.add(deliveryId);
    return MessageDelivery(
      deliveryId: deliveryId,
      clientMessageId: clientMessageId,
      status: 'accepted',
    );
  }

  @override
  Future<MessageDelivery> deliveryStatus(
    LinkedDevice device,
    String deliveryId,
  ) async {
    if (failDeliveryStatus) {
      throw const LinkApiException('电脑返回错误（503）。', statusCode: 503);
    }
    return MessageDelivery(
      deliveryId: deliveryId,
      clientMessageId: '',
      status: 'delivered',
    );
  }

  @override
  Future<String> setSessionTitle(
    LinkedDevice device,
    String id,
    String title,
  ) async =>
      title;

  @override
  Future<bool> setSessionImportant(
    LinkedDevice device,
    String id,
    bool important,
  ) async =>
      true;

  @override
  Future<Uint8List> promptImage(
    LinkedDevice device,
    String id,
    int index,
  ) async =>
      Uint8List(0);
}

const device = LinkedDevice(
  deviceId: 'device-one',
  token: 'test-token',
  instanceId: 'instance-one',
  instanceName: 'Mac',
  fingerprint: 'ABC123',
  addresses: ['192.168.1.5'],
  port: 47653,
);

void main() {
  test('unchanged content does not download sessions again', () async {
    final api = FakeMonitoringApi();
    final controller = SessionController(device, api: api);
    await controller.refresh(scan: true);
    expect(api.refreshCount, 1);
    expect(api.statusCount, 2);
    expect(api.sessionsCount, 1);
    expect(controller.sessions.single.title, '同步测试');

    await controller.refresh();
    expect(api.statusCount, 3);
    expect(api.sessionsCount, 1);
    expect(api.refreshCount, 1);

    api.revision = 9;
    await controller.refresh();
    expect(api.sessionsCount, 2);
    controller.dispose();
    expect(api.closeCount, 1);
  });

  test('legacy server falls back to full session downloads', () async {
    final api = FakeMonitoringApi()
      ..supportsRefresh = false
      ..supportsConditionalRequests = false;
    final controller = SessionController(device, api: api);
    await controller.refresh(scan: true);
    await controller.refresh(scan: true);
    expect(api.refreshCount, 0);
    expect(api.sessionsCount, 2);
    expect(controller.sessions, hasLength(1));
    controller.dispose();
  });

  test('server reported addresses replace stale ones', () async {
    final api = FakeMonitoringApi()..addresses = ['192.168.9.9'];
    LinkedDevice? updated;
    final controller = SessionController(
      device,
      api: api,
      onDeviceUpdated: (value) => updated = value,
    );

    await controller.refresh(scan: true);
    expect(controller.device.addresses, ['192.168.9.9']);
    expect(updated?.addresses, ['192.168.9.9']);

    updated = null;
    await controller.refresh();
    expect(updated, isNull);

    controller.dispose();
  });

  test('unknown session state is explained without implying a connection error',
      () {
    expect(statusLabel('Unknown'), '状态待确认');
  });

  test('delivery polling failure is surfaced instead of silently dropped',
      () async {
    final api = FakeConversationApi();
    final controller = SessionController(device, api: api);
    await controller.refresh(scan: true);

    final MessageDelivery? delivery = await controller.sendMessage(
      controller.sessions.single,
      'client-1',
      '你好',
    );
    expect(delivery, isNotNull);

    api.failDeliveryStatus = true;
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(controller.deliveryError(delivery!.deliveryId), isNotNull);
    expect(controller.deliveryError(delivery.deliveryId), contains('投递状态查询失败'));
    controller.dispose();
  });

  test('each send uses a fresh client message id', () async {
    final api = FakeConversationApi();
    final controller = SessionController(device, api: api);
    await controller.refresh(scan: true);
    final AgentSession session = controller.sessions.single;

    await controller.sendMessage(session, 'client-1', '第一条');
    await controller.sendMessage(session, 'client-2', '第二条');

    expect(api.clientMessageIds, ['client-1', 'client-2']);
    expect(api.deliveryIds.toSet(), hasLength(2));
    controller.dispose();
  });
}
