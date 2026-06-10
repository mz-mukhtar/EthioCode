// test/widget_test.dart
//
// Smoke test that verifies the app launches and renders its root widget
// without crashing. Updated to reference EthioCodeApp (the real app class
// in main.dart) instead of the default Flutter template's MyApp.

import 'package:flutter_test/flutter_test.dart';
import 'package:ethiocode/main.dart';

void main() {
  testWidgets('App smoke test — EthioCodeApp renders without crashing',
      (WidgetTester tester) async {
    // Build the app and trigger one frame.
    await tester.pumpWidget(const EthioCodeApp());

    // WorkspacePage should be present in the tree.
    // We just verify the widget tree builds without throwing.
    expect(tester.takeException(), isNull);
  });
}
