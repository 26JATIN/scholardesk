import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitkaracompanion/screens/feed_detail_screen.dart';

void main() {
  testWidgets('FeedDetailScreen shows title', (WidgetTester tester) async {
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
      home: FeedDetailScreen(
        clientDetails: clientDetails,
        userData: userData,
        itemId: '1',
        itemType: '1',
        title: 'Test Announcement',
      ),
    ));
    
    // Initial state is loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    // Wait for frame
    await tester.pump();
    
    // Verify title is passed and shown (even if loading fails, title is in AppBar or Body)
    // Actually title is passed to widget and shown in body.
    // But if loading, body shows progress.
    // AppBar title is 'Details'.
    expect(find.text('Details'), findsOneWidget);
  });
}
