import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'models.dart';

class _ApiResponse {
  const _ApiResponse(this.body, this.etag);

  final Map<String, dynamic>? body;
  final String? etag;
}

class LinkApiException implements Exception {
  const LinkApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class MonitoringApi {
  Future<MonitoringStatus> status(LinkedDevice device);
  Future<SessionFetchResult> sessions(LinkedDevice device, {String? etag});
  Future<bool> refresh(LinkedDevice device);
  void close();
}

class SessionFetchResult {
  const SessionFetchResult({this.sessions, this.etag});

  final List<AgentSession>? sessions;
  final String? etag;
}

abstract interface class SessionActionsApi {
  Future<String> setSessionTitle(
    LinkedDevice device,
    String id,
    String title,
  );
  Future<bool> setSessionImportant(
    LinkedDevice device,
    String id,
    bool important,
  );
  Future<Uint8List> promptImage(
    LinkedDevice device,
    String id,
    int index,
  );
}

class LinkApi implements MonitoringApi, SessionActionsApi {
  final Map<String, HttpClient> _clients = {};
  bool _closed = false;
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

  @override
  Future<MonitoringStatus> status(LinkedDevice device) async {
    final value = await _getOnAllAddresses(device, '/v1/status');
    return MonitoringStatus.fromJson(value.body!);
  }

  @override
  Future<SessionFetchResult> sessions(
    LinkedDevice device, {
    String? etag,
  }) async {
    final result = await _getOnAllAddresses(
      device,
      '/v1/sessions',
      ifNoneMatch: etag,
    );
    if (result.body == null) {
      return SessionFetchResult(etag: result.etag ?? etag);
    }
    return SessionFetchResult(
      sessions: (result.body!['sessions'] as List)
          .map((item) => AgentSession.fromJson(item as Map<String, dynamic>))
          .toList(),
      etag: result.etag,
    );
  }

  @override
  Future<bool> refresh(LinkedDevice device) async {
    try {
      await _postOnAllAddresses(
        device.addresses,
        device.port,
        '/v1/refresh',
        device.fingerprint,
        const {},
        authorization: device.authorization,
      );
      return true;
    } on LinkApiException catch (error) {
      if (error.statusCode == HttpStatus.notFound ||
          error.statusCode == HttpStatus.methodNotAllowed) {
        return false;
      }
      rethrow;
    }
  }

  Future<AgentSession> session(LinkedDevice device, String id) async {
    final value = await _getOnAllAddresses(device, '/v1/sessions/$id');
    return AgentSession.fromJson(value.body!);
  }

  @override
  Future<String> setSessionTitle(
    LinkedDevice device,
    String id,
    String title,
  ) async {
    final value = await _postOnAllAddresses(
      device.addresses,
      device.port,
      '/v1/sessions/${Uri.encodeComponent(id)}/title',
      device.fingerprint,
      {'title': title},
      authorization: device.authorization,
    );
    return value['title'] as String? ?? title;
  }

  @override
  Future<bool> setSessionImportant(
    LinkedDevice device,
    String id,
    bool important,
  ) async {
    final value = await _postOnAllAddresses(
      device.addresses,
      device.port,
      '/v1/sessions/${Uri.encodeComponent(id)}/important',
      device.fingerprint,
      {'important': important},
      authorization: device.authorization,
    );
    return value['isImportant'] as bool? ?? important;
  }

  @override
  Future<Uint8List> promptImage(
    LinkedDevice device,
    String id,
    int index,
  ) async {
    final value = await _tryAddresses<Uint8List>(
      device.addresses,
      device.port,
      '/v1/sessions/${Uri.encodeComponent(id)}/images/$index',
      device.fingerprint,
      (client, uri) async {
        final request = await client.getUrl(uri);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${device.authorization}',
        );
        return _readBytes(request);
      },
      timeout: const Duration(seconds: 20),
    );
    return value!;
  }

  Future<Map<String, dynamic>> _postOnAllAddresses(
    List<String> addresses,
    int port,
    String path,
    String? fingerprint,
    Map<String, dynamic> body, {
    String? authorization,
  }) async {
    return (await _tryAddresses<_ApiResponse>(
      addresses,
      port,
      path,
      fingerprint,
      (client, uri) async {
        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        if (authorization != null) {
          request.headers
              .set(HttpHeaders.authorizationHeader, 'Bearer $authorization');
        }
        request.write(jsonEncode(body));
        return _readResponse(request);
      },
    ))!
        .body!;
  }

  Future<_ApiResponse> _getOnAllAddresses(
    LinkedDevice device,
    String path, {
    String? ifNoneMatch,
  }) async {
    return (await _tryAddresses(
        device.addresses, device.port, path, device.fingerprint,
        (client, uri) async {
      final request = await client.getUrl(uri);
      request.headers.set(
          HttpHeaders.authorizationHeader, 'Bearer ${device.authorization}');
      if (ifNoneMatch != null) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, ifNoneMatch);
      }
      return _readResponse(request);
    }))!;
  }

  Future<T?> _tryAddresses<T>(
    List<String> addresses,
    int port,
    String path,
    String? fingerprint,
    Future<T?> Function(HttpClient client, Uri uri) action, {
    Duration timeout = const Duration(seconds: 9),
  }) async {
    Object? lastError;
    for (final address in addresses) {
      final key = '$address:$port:${fingerprint ?? 'pairing'}';
      final client =
          _clients.putIfAbsent(key, () => _pinnedClient(fingerprint));
      try {
        if (_closed) throw const LinkApiException('连接已关闭');
        return await action(client,
                Uri(scheme: 'https', host: address, port: port, path: path))
            .timeout(timeout);
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
      }
      _clients.remove(key)?.close(force: true);
    }
    throw LinkApiException('无法连接电脑，请确认手机和电脑位于同一局域网。${lastError ?? ''}');
  }

  Future<_ApiResponse> _readResponse(HttpClientRequest request) async {
    final response = await request.close();
    final etag = response.headers.value(HttpHeaders.etagHeader);
    if (response.statusCode == HttpStatus.notModified) {
      await response.drain<void>();
      return _ApiResponse(null, etag);
    }
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == HttpStatus.unauthorized) {
      throw const LinkApiException('配对信息或设备授权已失效，请重新关联。', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LinkApiException('电脑返回错误（${response.statusCode}）。',
          statusCode: response.statusCode);
    }
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('电脑返回了无效数据');
    }
    return _ApiResponse(value, etag);
  }

  Future<Uint8List> _readBytes(HttpClientRequest request) async {
    final response = await request.close();
    if (response.statusCode == HttpStatus.unauthorized) {
      await response.drain<void>();
      throw const LinkApiException('配对信息或设备授权已失效，请重新关联。', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw LinkApiException(
        response.statusCode == HttpStatus.notFound
            ? '图片已不可用。'
            : '电脑返回错误（${response.statusCode}）。',
        statusCode: response.statusCode,
      );
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final client in _clients.values) {
      client.close(force: true);
    }
    _clients.clear();
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
