import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton service for SharedPreferences to avoid repeated initialization
class SharedPrefsService {
  static SharedPreferences? _instance;
  static bool _isInitializing = false;
  static final List<Completer<SharedPreferences>> _pendingCompleters = [];

  /// Maximum cache size for web (4MB to leave buffer for SharedPreferences overhead)
  static const int maxWebCacheSize = 4 * 1024 *  1024;

  /// Get the SharedPreferences instance (always the same)
  static Future<SharedPreferences> get instance async {
    if (_instance != null) return _instance!;

    // If already initializing, wait for it
    if (_isInitializing) {
      final completer = Completer<SharedPreferences>();
      _pendingCompleters.add(completer);
      return completer.future;
    }

    _isInitializing = true;
    try {
      _instance = await SharedPreferences.getInstance();

      // Resolve all pending completers
      for (final completer in _pendingCompleters) {
        completer.complete(_instance!);
      }
      _pendingCompleters.clear();

      return _instance!;
    } finally {
      _isInitializing = false;
    }
  }

  /// Check if we should cache (based on web limits)
  static bool shouldCacheData(String data) {
    if (kIsWeb && data.length > maxWebCacheSize) {
      debugPrint('Cache data too large (${data.length} bytes), skipping cache');
      return false;
    }
    return true;
  }

  /// Clear all cached data
  static Future<bool> clearAll() async {
    final prefs = await instance;
    return prefs.clear();
  }
}