import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SessionListLimit {
  all(0, '全部'),
  recent3(3, '最近 3 条'),
  recent5(5, '最近 5 条'),
  recent10(10, '最近 10 条'),
  recent15(15, '最近 15 条'),
  recent20(20, '最近 20 条');

  const SessionListLimit(this.storedCount, this.label);

  static const defaultLimit = recent10;

  final int storedCount;
  final String label;

  int? get count => this == SessionListLimit.all ? null : storedCount;

  static SessionListLimit fromCount(int? count) => values.firstWhere(
        (limit) => limit.storedCount == count,
        orElse: () => defaultLimit,
      );
}

abstract interface class SessionDisplayPreferences {
  Future<void> load();
  SessionListLimit get listLimit;
  Future<void> setListLimit(SessionListLimit limit);
}

class LocalSessionDisplayPreferences implements SessionDisplayPreferences {
  LocalSessionDisplayPreferences({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _limitKey = 'hud.session_limit.v1';
  final FlutterSecureStorage _storage;
  SessionListLimit _listLimit = SessionListLimit.defaultLimit;

  @override
  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _limitKey);
      _listLimit = SessionListLimit.fromCount(int.tryParse(raw ?? ''));
    } catch (_) {
      _listLimit = SessionListLimit.defaultLimit;
    }
  }

  @override
  SessionListLimit get listLimit => _listLimit;

  @override
  Future<void> setListLimit(SessionListLimit limit) async {
    await _storage.write(key: _limitKey, value: '${limit.storedCount}');
    _listLimit = limit;
  }
}

class InMemorySessionDisplayPreferences implements SessionDisplayPreferences {
  InMemorySessionDisplayPreferences([
    this.listLimit = SessionListLimit.defaultLimit,
  ]);

  @override
  SessionListLimit listLimit;

  @override
  Future<void> load() async {}

  @override
  Future<void> setListLimit(SessionListLimit limit) async {
    listLimit = limit;
  }
}
