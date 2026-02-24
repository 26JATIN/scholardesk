import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Service to handle Shorebird code push updates
class ShorebirdService {
  static final ShorebirdService _instance = ShorebirdService._internal();
  factory ShorebirdService() => _instance;
  ShorebirdService._internal();

  static const String _keyLastKnownPatch = 'shorebird_last_known_patch';

  final _updater = ShorebirdUpdater();
  
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;

  /// Check if running with Shorebird
  bool get isShorebirdAvailable => _updater.isAvailable;

  /// Get current patch number (null if on base release)
  Future<int?> get currentPatchNumber async {
    try {
      final patch = await _updater.readCurrentPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('❌ Error getting patch number: $e');
      return null;
    }
  }

  /// Check if the patch version has changed since last launch.
  /// Returns true if caches should be invalidated (new patch detected).
  /// Updates the stored patch number after checking.
  Future<bool> hasPatchChanged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastKnownPatch = prefs.getInt(_keyLastKnownPatch);
      
      int currentPatch;
      if (isShorebirdAvailable) {
        final patch = await _updater.readCurrentPatch();
        currentPatch = patch?.number ?? 0;
      } else {
        // Debug/web builds - use 0 as base
        currentPatch = 0;
      }
      
      debugPrint('📦 Patch check: current=$currentPatch, lastKnown=$lastKnownPatch');
      
      // Store the current patch number
      await prefs.setInt(_keyLastKnownPatch, currentPatch);
      
      // First launch (no stored value) - don't invalidate
      if (lastKnownPatch == null) {
        debugPrint('📦 First launch, storing patch number: $currentPatch');
        return false;
      }
      
      // Patch changed!
      if (currentPatch != lastKnownPatch) {
        debugPrint('🔄 Patch changed from $lastKnownPatch to $currentPatch - invalidating caches!');
        return true;
      }
      
      debugPrint('📦 Same patch ($currentPatch), caches are fine');
      return false;
    } catch (e) {
      debugPrint('❌ Error checking patch change: $e');
      return false;
    }
  }

  /// Check if an update is available
  Future<bool> isUpdateAvailable() async {
    if (!isShorebirdAvailable) {
      debugPrint('📦 Shorebird not available (debug build?)');
      return false;
    }

    _isChecking = true;
    try {
      final status = await _updater.checkForUpdate();
      debugPrint('📦 Shorebird update status: $status');
      return status == UpdateStatus.outdated;
    } catch (e) {
      debugPrint('❌ Error checking Shorebird update: $e');
      return false;
    } finally {
      _isChecking = false;
    }
  }

  /// Download and install the update
  /// Returns true if update was downloaded successfully
  Future<bool> downloadUpdate({
    void Function(double progress)? onProgress,
  }) async {
    if (!isShorebirdAvailable) return false;

    _isDownloading = true;
    _downloadProgress = 0.0;

    try {
      await _updater.update();
      
      _downloadProgress = 1.0;
      onProgress?.call(1.0);
      debugPrint('✅ Shorebird update downloaded successfully');
      return true;
    } on UpdateException catch (e) {
      debugPrint('❌ Error downloading Shorebird update: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Error downloading Shorebird update: $e');
      return false;
    } finally {
      _isDownloading = false;
    }
  }

  /// Check and download update in background (silent update)
  Future<void> checkAndDownloadInBackground() async {
    if (!isShorebirdAvailable) {
      debugPrint('📦 Shorebird not available, skipping background update check');
      return;
    }

    try {
      final hasUpdate = await isUpdateAvailable();
      if (hasUpdate) {
        debugPrint('📦 Shorebird: Downloading update in background...');
        await downloadUpdate();
        debugPrint('📦 Shorebird: Update ready! Will apply on next restart.');
      } else {
        debugPrint('📦 Shorebird: App is up to date');
      }
    } catch (e) {
      debugPrint('❌ Shorebird background update error: $e');
    }
  }
}
