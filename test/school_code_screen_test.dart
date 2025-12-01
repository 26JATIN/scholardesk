import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitkaracompanion/screens/school_code_screen.dart';

void main() {
  testWidgets('SchoolCodeScreen has input and button', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SchoolCodeScreen()));
    await tester.pumpAndSettle();

    // Verify that the title is present
    expect(find.text('Enter School Code'), findsOneWidget);

    // Verify that the input field is present
    expect(find.byType(TextField), findsOneWidget);

    // Verify that the button is present
    expect(find.text('Proceed'), findsOneWidget);
  });
}
