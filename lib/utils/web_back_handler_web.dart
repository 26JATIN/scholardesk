// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Global navigator key for accessing the navigator from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void setupWebBackButton() {
  if (!kIsWeb) return;

  // Disable swipe-back gestures on iOS Safari
  _disableSwipeGestures();

  // Handle browser back/forward
  html.window.onPopState.listen(_onBrowserBack);

  debugPrint('WebBackHandler: Initialized');
}

/// Disable iOS Safari swipe-to-go-back gesture
void _disableSwipeGestures() {
  // Inject CSS
  final style = html.StyleElement()
    ..id = 'disable-swipe-css'
    ..text = '''
    html, body, * {
      overscroll-behavior: none !important;
      -webkit-overflow-scrolling: auto !important;
    }
    body {
      touch-action: pan-y !important;
      -webkit-user-select: none !important;
      user-select: none !important;
    }
  ''';
  html.document.head?.append(style);

  // Inline styles as backup
  html.document.body?.style.setProperty('overscroll-behavior', 'none');
}

/// Handle browser back/forward button
void _onBrowserBack(html.PopStateEvent event) {
  // Prevent default (stops browser from actually navigating away)
  event.preventDefault();

  // Run after current frame to avoid conflicts
  Future.microtask(() {
    _processBackPress();
  });
}

/// Process back press - pop all routes or push state at root
void _processBackPress() async {
  final nav = navigatorKey.currentState;
  if (nav == null) {
    _syncHistory();
    return;
  }

  // Pop ALL available routes in sequence
  // This ensures we match the expected behavior
  while (nav.canPop()) {
    nav.pop();
    // Small delay to allow animation/completion
    await Future.delayed(const Duration(milliseconds: 80));
  }

  // At root - push state so back button is ready for next press
  _syncHistory();
}

/// Sync browser history with current app state
void _syncHistory() {
  html.window.history.pushState(null, '', html.window.location.href);
}

/// Call from screen initState to register new screen
void onScreenReady() {
  if (kIsWeb) {
    _syncHistory();
  }
}

/// Trigger back from custom button
Future<void> triggerWebBack() async {
  _processBackPress();
}