import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'models.dart';

class LinkApiException implements Exception {
  const LinkApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class LinkApi {
  static String get defaultDeviceName {
    final system = Platform.operatingSystem;
    final host = Platform.localHostname;
    return host.isEmpty ? system : '$system · $host';
  }

  Future<LinkedDevice> completeQr(PairingOffer offer, String deviceName) async {
    final value = await _postOnAllAddresses(
      offer.addresses,
      offer.port,
      '/v1/pair/complete',
      offer.fingerprint,
      {
        'sessionId': offer.sessionId,
        'secret': offer.secret,
        'deviceName': deviceName,
      },
    );
    return LinkedDevice.fromPairing(value);
  }

  Future<LinkedDevice> completeCode({
    required String address,
    required int port,
    required String code,
    required String deviceName,
  }) async {
    // The short-lived, attempt-limited code authenticates this first exchange.
    // The returned certificate fingerprint is pinned for every later request.
    final value = await _postOnAllAddresses(
      [address],
      port,
      '/v1/pair/verify-code',
      null,
      {'code': code, 'deviceName': deviceName},
    );
    return LinkedDevice.fromPairing(value);
  }

  Future<MonitoringStatus> status(LinkedDevice device) async {
    final value = await _getOnAllAddresses(device, '/v1/status');
    return MonitoringStatus.fromJson(value);
  }

  Future<List<AgentSession>> sessions(LinkedDevice device) async {
    final value = await _getOnAllAddresses(device, '/v1/sessions');
    return (value['sessions'] as List)
        .map((item) => AgentSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AgentSession> session(LinkedDevice device, String id) async {
    final value = await _getOnAllAddresses(device, '/v1/sessions/$id');
    return AgentSession.fromJson(value);
  }

  Future<Map<String, dynamic>> _postOnAllAddresses(
    List<String> addresses,
    int port,
    String path,
    String? fingerprint,
    Map<String, dynamic> body,
  ) {
    return _tryAddresses(addresses, port, path, fingerprint, (client, uri) async {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      return _readResponse(request);
    });
  }

  Future<Map<String, dynamic>> _getOnAllAddresses(LinkedDevice device, String path) {
    return _tryAddresses(device.addresses, device.port, path, device.fingerprint, (client, uri) async {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${device.authorization}');
      return _readResponse(request);
    });
  }

  Future<Map<String, dynamic>> _tryAddresses(
    List<String> addresses,
    int port,
    String path,
    String? fingerprint,
    Future<Map<String, dynamic>> Function(HttpClient client, Uri uri) action,
  ) async {
    Object? lastError;
    for (final address in addresses) {
      final client = _pinnedClient(fingerprint);
      try {
        return await action(client, Uri(scheme: 'https', host: address, port: port, path: path))
            .timeout(const Duration(seconds: 9));
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on HandshakeException catch (error) {
        lastError = error;
      } on HttpException catch (error) {
        lastError = error;
      } on LinkApiException {
        rethrow;
      } finally {
        client.close(force: true);
      }
    }
    throw LinkApiException('无法连接电脑，请确认手机和电脑位于同一局域网。${lastError ?? ''}');
  }

  Future<Map<String, dynamic>> _readResponse(HttpClientRequest request) async {
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const LinkApiException('配对信息或设备授权已失效，请重新关联。', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LinkApiException('电脑返回错误（${response.statusCode}）。', statusCode: response.statusCode);
    }
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('电脑返回了无效数据');
    }
    return value;
  }

  HttpClient _pinnedClient(String? fingerprint) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    if (fingerprint == null) {
      client.badCertificateCallback = (_, __, ___) => true;
    } else {
      client.badCertificateCallback = (certificate, _, __) {
        final actual = sha256.convert(certificate.der).toString().toUpperCase();
        return actual == fingerprint.toUpperCase();
      };
    }
    return client;
  }
}
