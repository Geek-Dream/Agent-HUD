import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 手机本地的列表偏好，独立于电脑；常驻会话沿用会话的星标状态。
class SessionDisplayStore {
  static const _key = 'hud.session_limit.v1';
  static const _storage = FlutterSecureStorage();
  static const options = <int>[0, 3, 5, 10, 15, 20];

  static Future<int> load() async {
    try {
      final value = int.tryParse(await _storage.read(key: _key) ?? '');
      return options.contains(value) ? value! : 10;
    } catch (_) {
      return 10;
    }
  }

  static Future<void> save(int limit) async {
    if (!options.contains(limit)) return;
    await _storage.write(key: _key, value: '$limit');
  }
}
