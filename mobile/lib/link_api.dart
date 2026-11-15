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
  const LinkApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;

  /// 服务端在非 2xx 响应里返回的 JSON 体。投递失败时里面带有 `deliveryId`
  /// 和 `status`，手机端需要它才能继续轮询投递状态。
  final Map<String, dynamic>? body;

  @override
  String toString() => message;
}

/// 轻量可达性探测：只回答「这台电脑现在能不能连上」，不做完整状态解析。
///
/// 设备列表页用它把「在线」从装饰性文案变成真实状态。
abstract interface class DeviceHealthApi {
  Future<bool> probe(
    LinkedDevice device, {
    Duration timeout = const Duration(seconds: 4),
  });

  void close();
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
  Future<MessageDelivery> sendMessage(
    LinkedDevice device,
    String id,
    String clientMessageId,
    String text,
  );
  Future<MessageDelivery> deliveryStatus(
    LinkedDevice device,
    String deliveryId,
  );
}

class LinkApi implements MonitoringApi, SessionActionsApi, DeviceHealthApi {
  final Map<String, HttpClient> _clients = {};

  /// 上次成功的地址（按 地址集合+端口+指纹 归档）。电脑会同时上报多个地址，
  /// 其中虚拟机/网桥地址在手机侧永远连不通；每次都从头重试会让每个请求都
  /// 先吃满一次连接超时，表现就是「能用但很卡」。
  final Map<String, String> _preferredAddress = {};
  bool _closed = false;
  static String get defaultDeviceName {
    final system = Platform.operatingSystem;
    final host = Platform.localHostname;
    return host.isEmpty ? system : '$system · $host';
  }

  Future<LinkedDevice> completeQr(
    PairingOffer offer,
    String deviceName, {
    void Function(String host, int port, int index, int total)? onAttempt,
  }) async {
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
      onAttempt: onAttempt,
    );
    return LinkedDevice.fromPairing(value);
  }

  Future<LinkedDevice> completeCode({
    required String address,
    required int port,
    required String code,
    required String deviceName,
    void Function(String host, int port, int index, int total)? onAttempt,
  }) async {
    // The short-lived, attempt-limited code authenticates this first exchange.
    // The returned certificate fingerprint is pinned for every later request.
    final value = await _postOnAllAddresses(
      [address],
      port,
      '/v1/pair/verify-code',
      null,
      {'code': code, 'deviceName': deviceName},
      onAttempt: onAttempt,
    );
    return LinkedDevice.fromPairing(value);
  }

  @override
  Future<bool> probe(
    LinkedDevice device, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      await _tryAddresses(
        device.addresses,
        device.port,
        '/v1/status',
        device.fingerprint,
        (client, uri) async {
          final request = await client.getUrl(uri);
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${device.authorization}',
          );
          return _readResponse(request);
        },
        timeout: timeout,
      );
      return true;
    } on LinkApiException catch (exception) {
      // 401 说明电脑在线、只是授权失效，仍然算「连得上」，让用户进会话页
      // 看到明确的「请重新关联」，而不是被误判成电脑关机。
      return exception.statusCode == 401;
    } catch (_) {
      return false;
    }
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

  @override
  Future<MessageDelivery> sendMessage(
    LinkedDevice device,
    String id,
    String clientMessageId,
    String text,
  ) async {
    try {
      final value = await _postOnAllAddresses(
        device.addresses,
        device.port,
        '/v1/sessions/${Uri.encodeComponent(id)}/messages',
        device.fingerprint,
        {
          'clientMessageId': clientMessageId,
          'text': text,
        },
        authorization: device.authorization,
      );
      return MessageDelivery.fromJson(value);
    } on LinkApiException catch (error) {
      // 投递失败时服务端用非 2xx 返回，但响应体仍是消息投递记录。
      // 有 deliveryId 就交给调用方继续轮询，错误码由 /v1/deliveries/{id} 提供。
      final body = error.body;
      final deliveryId = body?['deliveryId'];
      if (deliveryId is String && deliveryId.isNotEmpty) {
        return MessageDelivery.fromJson(body!);
      }
      rethrow;
    }
  }

  @override
  Future<MessageDelivery> deliveryStatus(
    LinkedDevice device,
    String deliveryId,
  ) async {
    final value = await _getOnAllAddresses(
      device,
      '/v1/deliveries/${Uri.encodeComponent(deliveryId)}',
    );
    return MessageDelivery.fromJson(value.body!);
  }

  Future<Map<String, dynamic>> _postOnAllAddresses(
    List<String> addresses,
    int port,
    String path,
    String? fingerprint,
    Map<String, dynamic> body, {
    String? authorization,
    void Function(String host, int port, int index, int total)? onAttempt,
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
      onAttempt: onAttempt,
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
    void Function(String host, int port, int index, int total)? onAttempt,
  }) async {
    Object? lastError;
    final preferredKey = '${addresses.join(',')}|$port|${fingerprint ?? 'pairing'}';
    final ordered = _orderedAddresses(addresses, preferredKey);
    final attempted = <String>[];
    for (var index = 0; index < ordered.length; index += 1) {
      final address = ordered[index];
      final key = '$address:$port:${fingerprint ?? 'pairing'}';
      final client =
          _clients.putIfAbsent(key, () => _pinnedClient(fingerprint));
      attempted.add(formatLinkAddress(address, port));
      onAttempt?.call(address, port, index + 1, ordered.length);
      try {
        if (_closed) throw const LinkApiException('连接已关闭');
        final result = await action(client,
                Uri(scheme: 'https', host: address, port: port, path: path))
            .timeout(timeout);
        _preferredAddress[preferredKey] = address;
        return result;
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
    throw LinkApiException(
        '连不上电脑（已尝试 ${attempted.join('、')}）。'
        '请确认手机和电脑在同一个局域网，或改用电脑上显示的地址与端口重试。'
        '${lastError == null ? '' : '\n$lastError'}');
  }

  List<String> _orderedAddresses(List<String> addresses, String preferredKey) {
    final normalized = addresses.map(normalizeLinkAddress).toList();
    final preferred = _preferredAddress[preferredKey];
    if (preferred == null || normalized.length < 2) return normalized;
    if (!normalized.contains(preferred)) return normalized;
    return [preferred, ...normalized.where((item) => item != preferred)];
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
      throw LinkApiException(
        _errorMessage(response.statusCode, body),
        statusCode: response.statusCode,
        body: _decodeJsonMap(body),
      );
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

  /// 非 2xx 响应体解析成 Map；不是 JSON 对象时返回 null，不让解析失败掩盖原始错误。
  static Map<String, dynamic>? _decodeJsonMap(String body) {
    if (body.isEmpty) return null;
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// 优先使用服务端返回的错误码，没有时回退到状态码文案。
  static String _errorMessage(int statusCode, String body) {
    final error = _decodeJsonMap(body)?['error'];
    if (error is String && error.isNotEmpty) {
      return '电脑返回错误：$error（$statusCode）。';
    }
    return '电脑返回错误（$statusCode）。';
  }
}
