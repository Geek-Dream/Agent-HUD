import 'dart:convert';
import 'dart:io';

import 'package:agent_hud_mobile/link_api.dart';
import 'package:agent_hud_mobile/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart LinkApi pairs with macOS and monitors sessions', () async {
    final fixtureURL = Platform.environment['AGENTHUD_LINK_FIXTURE'];
    expect(fixtureURL, isNotNull,
        reason: 'Run through scripts/test-mobile-link.sh');
    final fixture = jsonDecode(await File(fixtureURL!).readAsString())
        as Map<String, dynamic>;
    final address = fixture['address'] as String;
    final port = fixture['port'] as int;
    final fingerprint = fixture['fingerprint'] as String;
    final offer = PairingOffer.fromQr(fixture['offer'] as String);
    expect(offer.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    expect(offer.fingerprint, fingerprint);

    final api = LinkApi();
    addTearDown(api.close);
    addTearDown(() => File('$fixtureURL.stop').writeAsString('stop\n'));
    var step = 'QR pairing';
    try {
      final device = await api.completeQr(offer, 'Dart integration phone');
      expect(device.fingerprint, fingerprint);
      expect(device.addresses, isNotEmpty);

      final localDevice = LinkedDevice(
        deviceId: device.deviceId,
        token: device.token,
        instanceId: device.instanceId,
        instanceName: device.instanceName,
        fingerprint: device.fingerprint,
        addresses: [address],
        port: port,
      );
      step = 'status';
      final status = await api.status(localDevice);
      expect(status.revision, 7);
      expect(status.privacyMode, isFalse);
      expect(status.supportsRefresh, isTrue);

      final initialResult = await api.sessions(localDevice);
      final sessionsEtag = initialResult.etag;
      expect(sessionsEtag, isNotNull);
      final sessions = initialResult.sessions!;
      final unchanged = await api.sessions(localDevice, etag: sessionsEtag);
      expect(unchanged.sessions, isNull);
      expect(unchanged.etag, sessionsEtag);
      expect(await api.refresh(localDevice), isTrue);
      final refreshedStatus = await api.status(localDevice);
      expect(refreshedStatus.revision, 8);
      final refreshedSessions =
          await api.sessions(localDevice, etag: sessionsEtag);
      expect(refreshedSessions.sessions, hasLength(1));
      expect(refreshedSessions.etag, isNot(sessionsEtag));

      expect(sessions, isNotNull);
      expect(sessions, hasLength(1));
      expect(sessions.single.id, fixture['expectedSessionId']);
      expect(sessions.single.status, 'WaitingUser');
      expect(sessions.single.isActive, isTrue);
      expect(statusLabel(sessions.single.status), '等待确认');
      expect(sessions.single.title, '等待手机测试');
      expect(sessions.single.summary, '局域网集成测试');
      final detail = await api.session(localDevice, sessions.single.id);
      expect(detail.id, sessions.single.id);

      step = 'QR reuse rejection';
      final secondOffer = PairingOffer.fromQr(fixture['offer'] as String);
      await expectLater(
        api.completeQr(secondOffer, 'Reused QR'),
        throwsA(isA<LinkApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)),
      );

      await File('$fixtureURL.request').writeAsString(jsonEncode({
        'request': 1,
        'deviceIdToRevoke': device.deviceId,
        'generateCode': true,
      }));
      for (var attempt = 0; attempt < 40; attempt++) {
        if (await File('$fixtureURL.codeReady').exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      step = 'verification-code pairing';
      final code = (jsonDecode(await File('$fixtureURL.code').readAsString())
          as Map<String, dynamic>)['code'] as String;
      final codeDevice = await api.completeCode(
        address: address,
        port: port,
        code: code,
        deviceName: 'Dart verification-code phone',
      );
      expect(codeDevice.token, isNotEmpty);
      final revokedDevice = LinkedDevice(
        deviceId: codeDevice.deviceId,
        token: codeDevice.token,
        instanceId: codeDevice.instanceId,
        instanceName: codeDevice.instanceName,
        fingerprint: codeDevice.fingerprint,
        addresses: [address],
        port: port,
      );
      await File('$fixtureURL.request').writeAsString(jsonEncode({
        'request': 2,
        'deviceIdToRevoke': codeDevice.deviceId,
      }));
      for (var attempt = 0; attempt < 100; attempt++) {
        if (await File('$fixtureURL.revoked').exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(await File('$fixtureURL.revoked').exists(), isTrue);
      await expectLater(
        api.status(revokedDevice),
        throwsA(isA<LinkApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)),
      );
      await File('$fixtureURL.stop').writeAsString('stop\n');
    } catch (error) {
      fail('$step failed: $error');
    }
  },
      timeout: const Timeout(Duration(seconds: 60)),
      skip: Platform.environment['AGENTHUD_LINK_FIXTURE'] == null);
}
