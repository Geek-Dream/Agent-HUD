import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class HiddenModeStore {
  HiddenModeStore._();

  static const _key = 'hud.hidden_mode.v1';
  static const _storage = FlutterSecureStorage();

  static Future<bool> isEnabled() async {
    try {
      final value = await _storage.read(key: _key);
      return value == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    await _storage.write(key: _key, value: value ? 'true' : 'false');
  }
}
