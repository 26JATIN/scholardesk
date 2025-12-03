import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scholardesk/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen has inputs and button', (WidgetTester tester) async {
    final clientDetails = {
      'client_name': 'Test University',
      'baseUrl': 'test.com',
      'client_abbr': 'test',
      'loginLogo': 'https://example.com/logo.png',
    };

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(clientDetails: clientDetails),
    ));
    await tester.pumpAndSettle();

    // Verify title
    expect(find.text('Test University'), findsOneWidget);

    // Verify inputs
    expect(find.byType(TextField), findsNWidgets(2)); // Username and Password

    // Verify button
    expect(find.text('Login'), findsOneWidget);
  });
}
