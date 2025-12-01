import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitkaracompanion/screens/feed_screen.dart';

void main() {
  testWidgets('FeedScreen shows title', (WidgetTester tester) async {
    final clientDetails = {
      'client_name': 'Test University',
      'baseUrl': 'test.com',
      'client_abbr': 'test',
    };
    final userData = {
      'userId': '123',
      'roleId': '4',
      'sessionId': '18',
      'apiKey': 'key',
    };

    await tester.pumpWidget(MaterialApp(
      home: FeedScreen(clientDetails: clientDetails, userData: userData),
    ));
    
    // Initial state is loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    // We can't easily mock the API call here without dependency injection or mocking http,
    // so we'll just verify the initial UI state.
    // To verify the title "Announcements", we need to wait for the frame.
    await tester.pump();
    expect(find.text('Announcements'), findsOneWidget);
  });
}
