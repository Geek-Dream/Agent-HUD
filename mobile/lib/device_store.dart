import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class DeviceStore extends ChangeNotifier {
  DeviceStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'agenthud.linkedDevices.v1';
  final FlutterSecureStorage _storage;
  final List<LinkedDevice> _devices = [];

  List<LinkedDevice> get devices => List.unmodifiable(_devices);
  bool get isEmpty => _devices.isEmpty;

  Future<void> load() async {
    final raw = await _storage.read(key: _key);
    if (raw != null && raw.isNotEmpty) {
      final values = jsonDecode(raw) as List;
      _devices
        ..clear()
        ..addAll(values.map((item) => LinkedDevice.fromJson(item as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> upsert(LinkedDevice device) async {
    _devices.removeWhere((item) => item.id == device.id || item.instanceId == device.instanceId);
    _devices.insert(0, device);
    await _save();
  }

  Future<void> remove(String id) async {
    _devices.removeWhere((item) => item.id == id);
    await _save();
  }

  Future<void> _save() async {
    await _storage.write(
      key: _key,
      value: jsonEncode(_devices.map((device) => device.toJson()).toList()),
    );
    notifyListeners();
  }
}
