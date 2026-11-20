import 'package:agent_hud_mobile/session_controller.dart';
import 'package:agent_hud_mobile/session_display.dart';
import 'package:agent_hud_mobile/session_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_controller_test.dart';

class _Row {
  const _Row(this.id, this.at, {this.important = false});

  final String id;
  final DateTime at;
  final bool important;
}

List<_Row> _apply(Iterable<_Row> rows, SessionListLimit limit) =>
    visibleSessions(
      rows,
      limit,
      isImportant: (row) => row.important,
      lastActivityAt: (row) => row.at,
      id: (row) => row.id,
    );

void main() {
  test('default recent ten keeps starred rows and newest activity', () {
    final base = DateTime.utc(2026, 11, 12);
    final rows = List<_Row>.generate(
      25,
      (index) => _Row('s$index', base.add(Duration(minutes: index))),
    );
    final visible = _apply(rows, SessionListLimit.recent10);
    expect(visible, hasLength(10));
    expect(visible.first.id, 's24');
    expect(visible.map((row) => row.id), isNot(contains('s10')));

    final starred = _apply(
      [rows[0].copyWithImportant(), ...rows.skip(1)],
      SessionListLimit.recent10,
    );
    expect(starred, hasLength(11));
    expect(starred.first.id, 's0');
  });

  test('all and requested limits preserve empty and unbounded results', () {
    final rows = List<_Row>.generate(
      22,
      (index) =>
          _Row('s$index', DateTime.utc(2026, 1, 1).add(Duration(days: index))),
    );
    expect(_apply(rows, SessionListLimit.all), hasLength(22));
    expect(_apply(rows, SessionListLimit.recent3), hasLength(3));
    expect(_apply(rows, SessionListLimit.recent5), hasLength(5));
    expect(_apply(rows, SessionListLimit.recent15), hasLength(15));
    expect(_apply(rows, SessionListLimit.recent20), hasLength(20));
    expect(_apply(const [], SessionListLimit.recent10), isEmpty);
  });

  test('preferences persist recent limits and all', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final preferences = LocalSessionDisplayPreferences();
    await preferences.load();
    expect(preferences.listLimit, SessionListLimit.recent10);
    await preferences.setListLimit(SessionListLimit.recent3);
    expect(preferences.listLimit, SessionListLimit.recent3);
    await preferences.setListLimit(SessionListLimit.all);
    expect(preferences.listLimit, SessionListLimit.all);

    final restored = LocalSessionDisplayPreferences();
    await restored.load();
    expect(restored.listLimit, SessionListLimit.all);
  });

  test('controller loads stored limit without refreshing sessions', () async {
    final preferences = InMemorySessionDisplayPreferences(
      SessionListLimit.recent5,
    );
    final api = FakeMonitoringApi();
    final controller = SessionController(
      device,
      api: api,
      displayPreferences: preferences,
    );
    await controller.loadDisplayPreferences();
    expect(controller.preferencesLoaded, isTrue);
    expect(controller.listLimit, SessionListLimit.recent5);
    expect(api.sessionsCount, 0);
    controller.dispose();
  });
}

extension on _Row {
  _Row copyWithImportant() => _Row(id, at, important: true);
}
