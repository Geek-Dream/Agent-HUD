import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TodoItem {
  const TodoItem({
    required this.id,
    required this.title,
    this.description = '',
    this.completed = false,
    required this.createdAt,
    this.dueAt,
  });

  final String id;
  final String title;
  final String description;
  final bool completed;
  final DateTime createdAt;
  final DateTime? dueAt;

  TodoItem copyWith({
    String? title,
    String? description,
    bool? completed,
    DateTime? dueAt,
  }) =>
      TodoItem(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        completed: completed ?? this.completed,
        createdAt: createdAt,
        dueAt: dueAt ?? this.dueAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        completed: json['completed'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String),
      );
}

class TodoStore {
  TodoStore._();

  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const _key = 'hud.todos.v1';

  static Future<List<TodoItem>> load() async {
    try {
      final String? raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const [];
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(TodoItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<TodoItem> items) async {
    final String encoded = jsonEncode(items.map((i) => i.toJson()).toList());
    await _storage.write(key: _key, value: encoded);
  }
}
