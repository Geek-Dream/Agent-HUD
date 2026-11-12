import 'package:agent_hud_mobile/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses version 1 QR pairing payload', () {
    const payload = '''
      {
        "v": 1,
        "instanceId": "instance-one",
        "instanceName": "Test PC",
        "addresses": ["192.168.1.5"],
        "port": 61051,
        "fingerprint": "ABC123",
        "sessionId": "session-one",
        "secret": "one-time-secret",
        "expiresAt": "2026-11-12T01:00:00+08:00"
      }
    ''';

    final offer = PairingOffer.fromQr(payload);

    expect(offer.instanceId, 'instance-one');
    expect(offer.addresses, ['192.168.1.5']);
    expect(offer.port, 61051);
    expect(offer.secret, 'one-time-secret');
  });

  test('combines optional IPv6 addresses and formats endpoints', () {
    const payload = '''
      {
        "v": 1,
        "instanceId": "instance-one",
        "addresses": ["192.168.1.5"],
        "ipv6Addresses": ["2409:8900::1234"],
        "port": 47653,
        "fingerprint": "ABC123",
        "sessionId": "session-one",
        "secret": "one-time-secret",
        "expiresAt": "2027-11-12T01:00:00Z"
      }
    ''';
    final offer = PairingOffer.fromQr(payload);
    expect(offer.addresses, ['192.168.1.5', '2409:8900::1234']);
    expect(formatLinkAddress(offer.addresses.last, offer.port),
        '[2409:8900::1234]:47653');
    expect(normalizeLinkAddress('[2409:8900::1234]'), '2409:8900::1234');
    const device = LinkedDevice(
      deviceId: 'device-one',
      token: 'secret-token',
      instanceId: 'instance-one',
      instanceName: 'Test PC',
      fingerprint: 'ABC123',
      addresses: ['2409:8900::1234'],
      port: 47653,
    );
    expect(device.baseUri(device.addresses.first).toString(),
        'https://[2409:8900::1234]:47653');
  });

  test('maps monitoring session without requiring optional fields', () {
    final session = AgentSession.fromJson({
      'id': 'public-id',
      'provider': 'Codex',
      'status': 'Working',
      'title': 'Task',
      'projectName': 'Demo',
      'currentAction': 'Testing',
      'startedAt': '2026-11-12T00:00:00Z',
      'lastActivityAt': '2026-11-12T00:01:00Z',
    });

    expect(session.id, 'public-id');
    expect(session.currentFiles, isEmpty);
    expect(session.completedAt, isNull);
    expect(session.isActive, isTrue);
    expect(statusLabel(session.status), '工作中');
  });

  test('device authorization uses device id and token', () {
    const device = LinkedDevice(
      deviceId: 'device-one',
      token: 'secret-token',
      instanceId: 'instance-one',
      instanceName: 'Test PC',
      fingerprint: 'ABC123',
      addresses: ['192.168.1.5'],
      port: 61051,
    );

    expect(device.authorization, 'device-one.secret-token');
    expect(device.baseUri(device.addresses.first).toString(),
        'https://192.168.1.5:61051');
  });
}
