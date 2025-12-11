import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Service to track and show "What's New" dialogs after Shorebird patch updates
class WhatsNewService {
  static final WhatsNewService _instance = WhatsNewService._internal();
  factory WhatsNewService() => _instance;
  WhatsNewService._internal();

  static const String _keyLastSeenPatch = 'whats_new_last_seen_patch';
  
  final _updater = ShorebirdUpdater();

  /// Current patch version identifier
  /// Format: "patch_<number>" or "base_<version>"
  Future<String> getCurrentPatchId() async {
    try {
      if (!_updater.isAvailable) {
        // In debug mode, use a test identifier
        return 'debug_mode';
      }
      
      final patch = await _updater.readCurrentPatch();
      if (patch != null) {
        return 'patch_${patch.number}';
      }
      // Base release without patch
      return 'base_release';
    } catch (e) {
      debugPrint('❌ Error getting patch ID: $e');
      return 'unknown';
    }
  }

  /// Check if we should show What's New for the current patch
  Future<bool> shouldShowWhatsNew() async {
    try {
      final currentPatchId = await getCurrentPatchId();
      
      // Don't show in debug mode
      if (currentPatchId == 'debug_mode') {
        debugPrint('📰 What\'s New: Skipping in debug mode');
        return false;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final lastSeenPatch = prefs.getString(_keyLastSeenPatch);
      
      debugPrint('📰 What\'s New: Current=$currentPatchId, LastSeen=$lastSeenPatch');
      
      // Show if this is a new patch we haven't seen
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
  
  /// The version/patch description
  static const String updateSubtitle = "Latest Update";
  
  /// List of new features in this patch
  static List<WhatsNewFeature> get features => [
    const WhatsNewFeature(
      title: 'Attendance Register',
      description: 'View your detailed attendance register with a beautiful calendar view. See lecture-wise attendance for each subject!',
      icon: Icons.calendar_month_rounded,
    ),
  ];
}
