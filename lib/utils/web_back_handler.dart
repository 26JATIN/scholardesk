import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional import for web-specific back button handling
import 'web_back_stub.dart'
    if (dart.library.html) 'web_back_handler_web.dart';

export 'web_back_stub.dart' show navigatorKey, onScreenReady;

/// Prevents browser back button from leaving the site on web.
/// Call this in main() before runApp().
void setupWebBackButtonHandler() {
  if (kIsWeb) {
    setupWebBackButton();
  }
}

/// Call this in initState of screens to sync navigation state
void syncNavigationState() {
  if (kIsWeb) {
    onScreenReady();
  }
}