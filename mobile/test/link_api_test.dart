import 'package:agent_hud_mobile/link_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Link address fallback is covered by the serialized HTTPS integration test',
      () {
    expect(LinkApi, isNotNull);
  }, skip: 'Covered by scripts/test-mobile-link.sh with a single-use QR offer');
}
