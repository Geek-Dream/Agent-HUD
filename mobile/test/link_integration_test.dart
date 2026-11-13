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
    final ipv6Address = fixture['ipv6Address'] as String;
    expect(formatLinkAddress(ipv6Address, port), '[::1]:$port');
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
      expect(device.baseUri(ipv6Address).toString(), startsWith('https://[::1]:'));

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
      final ipv4Device = LinkedDevice(
        deviceId: localDevice.deviceId,
        token: localDevice.token,
        instanceId: localDevice.instanceId,
        instanceName: localDevice.instanceName,
        fingerprint: localDevice.fingerprint,
        addresses: ['127.0.0.1'],
        port: port,
      );
      expect((await api.status(ipv4Device)).revision, 7);
      final ipv6Device = LinkedDevice(
        deviceId: localDevice.deviceId,
        token: localDevice.token,
        instanceId: localDevice.instanceId,
        instanceName: localDevice.instanceName,
        fingerprint: localDevice.fingerprint,
        addresses: [ipv6Address],
        port: port,
      );
      expect((await api.status(ipv6Device)).revision, 7);
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

      if (fixture['conversation'] == true) {
        step = 'enable conversation';
        await File('$fixtureURL.request').writeAsString(jsonEncode({
          'request': 1,
          'enableConversation': true,
          'deviceId': device.deviceId,
        }));
        for (var attempt = 0; attempt < 40; attempt++) {
          if (await File('$fixtureURL.conversationReady').exists()) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(await File('$fixtureURL.conversationReady').exists(), isTrue);

        step = 'send message';
        final delivery = await api.sendMessage(
          localDevice,
          sessions.single.id,
          'dart-e2e-1',
          'HUD联调测试：请只回复 OK-E2E 四个字。',
        );
        expect(delivery.deliveryId, isNotEmpty);
        expect(delivery.status, anyOf('accepted', 'delivered'));

        step = 'delivery status';
        var finalDelivery = delivery;
        for (var attempt = 0; attempt < 100; attempt++) {
          if (finalDelivery.isFinal) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          finalDelivery =
              await api.deliveryStatus(localDevice, delivery.deliveryId);
        }
        expect(finalDelivery.status, 'delivered');
        await File('$fixtureURL.sent')
            .writeAsString(jsonEncode({'deliveryId': delivery.deliveryId}));
      }

      step = 'QR reuse rejection';
      final secondOffer = PairingOffer.fromQr(fixture['offer'] as String);
      await expectLater(
        api.completeQr(secondOffer, 'Reused QR'),
        throwsA(isA<LinkApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)),
      );

      await File('$fixtureURL.request').writeAsString(jsonEncode({
        'request': 2,
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
        'request': 3,
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
