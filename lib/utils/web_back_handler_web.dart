// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Global navigator key for accessing the navigator from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Web-specific back button handling.
/// Uses the browser's History API and PopStateEvent to intercept back button presses.
/// Properly closes overlays/dialogs one at a time before navigating back.
void setupWebBackButton() {
  // Push an initial dummy state so there's always something to "go back" to
  html.window.history.pushState(null, '', html.window.location.href);
  debugPrint('WebBackHandler: Initial history state pushed');

  // Listen for popstate (browser back/forward)
  html.window.onPopState.listen((event) {
    // Re-push the state so that the next back press is also caught
    // This prevents the browser from actually navigating away
    html.window.history.pushState(null, '', html.window.location.href);

    // Now try to close overlays/dialogs in Flutter
    _handleWebBack();
  });
}

/// Handles the web back button by closing overlays one at a time
void _handleWebBack() {
  if (!kIsWeb) return;

  // Schedule the pop to run after the current frame
  // This ensures we don't conflict with Flutter's navigation
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _doBackNavigation();
  });
}

/// Performs the actual back navigation
Future<void> _doBackNavigation() async {
  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    debugPrint('WebBackHandler: Navigator not found');
    return;
  }

  // First check if we can pop using maybePop (respects PopScope)
  final didPop = await navigator.maybePop();

  if (didPop) {
    debugPrint('WebBackHandler: maybePop succeeded');
  } else {
    // maybePop failed - try direct pop as fallback for web
    // This handles the case where PopScope.canPop was false but we still want to pop
    debugPrint('WebBackHandler: maybePop failed, trying direct pop');
    navigator.pop();
  }
}