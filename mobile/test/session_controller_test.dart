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

  @override
  Future<MonitoringStatus> status(LinkedDevice device) async {
    statusCount += 1;
    return MonitoringStatus(
      revision: revision,
      instanceName: 'Mac',
      privacyMode: false,
      serverTime: DateTime.utc(2026, 11, 12),
      supportsRefresh: supportsRefresh,
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

  test('unknown session state is explained without implying a connection error',
      () {
    expect(statusLabel('Unknown'), '状态待确认');
  });
}
