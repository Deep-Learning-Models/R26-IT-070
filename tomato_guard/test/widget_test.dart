import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomato_guard/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    // Verify key UI elements render
    expect(find.text('Tomato Guard'), findsOneWidget);
    expect(find.text('LADA-Capture'), findsOneWidget);
    expect(find.text('Upload from Gallery'), findsOneWidget);
  });
}
