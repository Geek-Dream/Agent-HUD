import 'package:agent_hud_mobile/pages/session_settings_page.dart';
import 'package:agent_hud_mobile/session_controller.dart';
import 'package:agent_hud_mobile/session_preferences.dart';
import 'package:agent_hud_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test.dart' as layout show expectNoOverflow;
import 'session_controller_test.dart';

void main() {
  test('controller applies recent limit, starred exemption and filters',
      () async {
    final api = FakeMonitoringApi();
    final controller = SessionController(device, api: api);
    await controller.refresh(scan: true);
    expect(controller.listLimit, SessionListLimit.recent10);
    expect(controller.sessions, hasLength(1));
    expect(controller.visibleSummary, contains('显示 1'));

    await controller.setListLimit(SessionListLimit.recent3);
    expect(controller.listLimit, SessionListLimit.recent3);
    controller.setProviderFilter('Claude');
    expect(controller.sessions, isEmpty);
    controller.setProviderFilter('All');
    expect(controller.sessions, hasLength(1));
    controller.dispose();
  });

  testWidgets('session settings page changes controller limit',
      (WidgetTester tester) async {
    final controller = SessionController(
      device,
      api: FakeMonitoringApi(),
      displayPreferences: InMemorySessionDisplayPreferences(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildHudTheme(),
        home: SessionSettingsPage(controller: controller),
      ),
    );
    expect(find.text('会话显示设置'), findsOneWidget);
    await tester.tap(find.text('最近 5 条'));
    await tester.pump();
    expect(controller.listLimit, SessionListLimit.recent5);
    await tester.tap(find.text('全部'));
    await tester.pump();
    expect(controller.listLimit, SessionListLimit.all);
  });

  testWidgets('session settings page fits small screen with large text',
      (WidgetTester tester) async {
    final controller = SessionController(
      device,
      api: FakeMonitoringApi(),
      displayPreferences: InMemorySessionDisplayPreferences(),
    );
    addTearDown(controller.dispose);
    await layout.expectNoOverflow(
      tester,
      SessionSettingsPage(controller: controller),
      size: const Size(320, 568),
      scale: 1.6,
    );
  });
}
