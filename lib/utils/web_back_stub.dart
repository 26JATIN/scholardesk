import 'package:flutter/material.dart';

/// Global navigator key for accessing the navigator from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Stub implementation for non-web platforms.
void setupWebBackButton() {
  // No-op on native platforms
}

/// Stub for screens to call in initState to sync navigation
void onScreenReady() {
  // No-op on native platforms
}
