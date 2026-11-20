import 'session_preferences.dart';

/// 三端共用的展示语义：星标常驻，其余按最近活动时间取 N 条。
List<T> visibleSessions<T>(
  Iterable<T> sessions,
  SessionListLimit limit, {
  required bool Function(T session) isImportant,
  required DateTime Function(T session) lastActivityAt,
  required String Function(T session) id,
}) {
  final items = sessions.toList()
    ..sort((a, b) {
      final byDate = lastActivityAt(b).compareTo(lastActivityAt(a));
      return byDate != 0 ? byDate : id(a).compareTo(id(b));
    });
  if (limit.count == null) return items;
  final starred = items.where(isImportant).toList();
  final ordinary = items.where((item) => !isImportant(item));
  return <T>[...starred, ...ordinary.take(limit.count!)];
}
