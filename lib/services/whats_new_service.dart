import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Service to track and show "What's New" dialogs after Shorebird patch updates
/// Also works on web using a version-based approach
class WhatsNewService {
  static final WhatsNewService _instance = WhatsNewService._internal();
  factory WhatsNewService() => _instance;
  WhatsNewService._internal();

  static const String _keyLastSeenPatch = 'whats_new_last_seen_patch';
  
  /// Current changelog version - increment this whenever you update WhatsNewContent
  /// This is used for web and as a fallback for mobile
  static const int changelogVersion = 2;
  
  final _updater = ShorebirdUpdater();
  
  /// Cached patch number for display
  int? _currentPatchNumber;
  
  /// Get the current patch number (for display)
  int? get currentPatchNumber => _currentPatchNumber;

  /// Current patch version identifier
  /// Format: "patch_<number>" or "base_<version>" or "web_<changelog_version>"
  Future<String> getCurrentPatchId() async {
    try {
      // On web, use changelog version
      if (kIsWeb) {
        _currentPatchNumber = changelogVersion;
        return 'web_$changelogVersion';
      }
      
      if (!_updater.isAvailable) {
        // In debug mode, use changelog version for testing
        _currentPatchNumber = changelogVersion;
        return 'debug_$changelogVersion';
      }
      
      final patch = await _updater.readCurrentPatch();
      if (patch != null) {
        _currentPatchNumber = patch.number;
        return 'patch_${patch.number}';
      }
      // Base release without patch - use changelog version
      _currentPatchNumber = changelogVersion;
      return 'base_$changelogVersion';
    } catch (e) {
      debugPrint('❌ Error getting patch ID: $e');
      _currentPatchNumber = changelogVersion;
      return 'error_$changelogVersion';
    }
  }

  /// Check if we should show What's New for the current patch
  Future<bool> shouldShowWhatsNew() async {
    try {
      final currentPatchId = await getCurrentPatchId();
      
      final prefs = await SharedPreferences.getInstance();
      final lastSeenPatch = prefs.getString(_keyLastSeenPatch);
      
      debugPrint('📰 What\'s New: Current=$currentPatchId, LastSeen=$lastSeenPatch');
      
      // Show if this is a new version we haven't seen
      if (lastSeenPatch != currentPatchId) {
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Error checking What\'s New status: $e');
      return false;
    }
  }

  /// Mark the current patch as seen (call after showing dialog)
  Future<void> markAsSeen() async {
    try {
      final currentPatchId = await getCurrentPatchId();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSeenPatch, currentPatchId);
      debugPrint('📰 What\'s New: Marked $currentPatchId as seen');
    } catch (e) {
      debugPrint('❌ Error marking What\'s New as seen: $e');
    }
  }

  /// Reset seen status (for testing)
  Future<void> resetSeenStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastSeenPatch);
    debugPrint('📰 What\'s New: Reset seen status');
  }
  
  /// Get formatted patch subtitle
  String getPatchSubtitle() {
    if (_currentPatchNumber != null) {
      return 'Patch $_currentPatchNumber';
    }
    return 'Latest Update';
  }
}

/// Model for a What's New feature
class WhatsNewFeature {
  final String title;
  final String description;
  final IconData icon;
  final Color? color;

  const WhatsNewFeature({
    required this.title,
    required this.description,
    required this.icon,
    this.color,
  });
}

/// Current patch features - Update this list with each Shorebird patch
class WhatsNewContent {
  /// The current patch/update title
  static const String updateTitle = "What's New! 🎉";
  
  /// List of new features in this patch
  static List<WhatsNewFeature> get features => [
    const WhatsNewFeature(
      title: 'Attendance Register',
      description: 'View your detailed attendance register with a beautiful calendar view. See lecture-wise attendance for each subject!',
      icon: Icons.calendar_month_rounded,
    ),
  ];
}
