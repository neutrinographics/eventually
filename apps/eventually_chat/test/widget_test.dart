// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:eventually_chat/main.dart';

void main() {
  testWidgets('Eventually Chat smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EventuallyChatApp());

    // Verify that the name input screen is shown
    expect(find.text('Welcome to Eventually Chat'), findsOneWidget);
    expect(find.text('Your Name'), findsOneWidget);
  });
}
