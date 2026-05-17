import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'shared_prefs_service.dart';

/// Model class for GitHub Release information
class AppUpdate {
  final String version;
  final String tagName;
  final String releaseNotes;
  final String downloadUrl;
  final String htmlUrl;
  final DateTime publishedAt;
  final int downloadSize;
  final String assetName;

  AppUpdate({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.htmlUrl,
    required this.publishedAt,
    required this.downloadSize,
    required this.assetName,
  });

  factory AppUpdate.fromJson(Map<String, dynamic> json) {
    // Find the APK asset - prefer ScholarDesk named APK
    final assets = json['assets'] as List<dynamic>? ?? [];
    Map<String, dynamic>? apkAsset;
    
    for (var asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        // Prefer ScholarDesk named APK
        if (name.contains('scholardesk')) {
          apkAsset = asset as Map<String, dynamic>;
          break;
        }
        // Fallback to any APK if ScholarDesk not found
        apkAsset ??= asset as Map<String, dynamic>;
      }
    }

    final tagName = json['tag_name'] as String? ?? '';
    // Remove 'v' prefix if present for version comparison
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    return AppUpdate(
      version: version,
      tagName: tagName,
      releaseNotes: json['body'] as String? ?? 'No release notes available.',
      downloadUrl: apkAsset?['browser_download_url'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now(),
      downloadSize: apkAsset?['size'] as int? ?? 0,
      assetName: apkAsset?['name'] as String? ?? 'ScholarDesk.apk',
    );
  }

  /// Get formatted download size
  String get formattedSize {
    if (downloadSize < 1024) {
      return '$downloadSize B';
    } else if (downloadSize < 1024 * 1024) {
      return '${(downloadSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(downloadSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Get formatted date
  String get formattedDate {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${publishedAt.day} ${months[publishedAt.month - 1]} ${publishedAt.year}';
  }
}

/// Service to handle OTA updates from GitHub releases
class UpdateService {
  // TODO: Replace with your actual GitHub repository details
  static const String _owner = '26JATIN';
  static const String _repo = 'scholardesk-release';
  
  // Fallback version if package_info_plus fails
  static const String _fallbackVersion = '1.0.0';
  
  // Cached version info
  static String? _cachedVersion;
  static String? _cachedBuildNumber;
  
  // Keys to track pending APK that should be deleted after install
  static const String _prefPendingApkPath = 'pending_apk_path';
  static const String _prefPendingApkVersion = 'pending_apk_version';
  
  static const String _apiBaseUrl = 'https://api.github.com';
  static const String _prefKeySkippedVersion = 'skipped_update_version';

  /// Get the current app version (cached for performance)
  static String get currentVersion => _cachedVersion ?? _fallbackVersion;
  
  /// Get the current build number
  static String get buildNumber => _cachedBuildNumber ?? '1';
  
  /// Initialize the update service and cache version info
  Future<void> init() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedVersion = packageInfo.version;
      _cachedBuildNumber = packageInfo.buildNumber;

    } catch (e) {

      _cachedVersion = _fallbackVersion;
      _cachedBuildNumber = '1';
    }
    // Attempt to clean any APK left from a previous update once we know current version
    try {
      await cleanPendingApk();
    } catch (e) {

    }
  }

  /// Check for updates from GitHub releases
  Future<AppUpdate?> checkForUpdate({bool force = false}) async {
    try {
      final url = Uri.parse('$_apiBaseUrl/repos/$_owner/$_repo/releases/latest');
      
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'ScholarDesk-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final update = AppUpdate.fromJson(json);

        // Check if this version was skipped
        final prefs = await SharedPrefsService.instance;
        final skippedVersion = prefs.getString(_prefKeySkippedVersion);
        if (!force && skippedVersion == update.version) {

          return null;
        }

        // Compare versions
        if (_isNewerVersion(update.version, currentVersion)) {

          return update;
        } else {

        }
      } else if (response.statusCode == 404) {

      } else {

      }
    } catch (e) {

    }
    
    return null;
  }

  /// Get all releases (for changelog history)
  Future<List<AppUpdate>> getAllReleases({int limit = 10}) async {
    try {
      final url = Uri.parse('$_apiBaseUrl/repos/$_owner/$_repo/releases?per_page=$limit');
      
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'ScholarDesk-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .map((json) => AppUpdate.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {

    }
    
    return [];
  }

  /// Compare version strings (e.g., "1.2.3" vs "1.2.4")
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = newVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      
      // Ensure both lists have same length
      while (newParts.length < 3) newParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);
      
      for (int i = 0; i < 3; i++) {
        if (newParts[i] > currentParts[i]) return true;
        if (newParts[i] < currentParts[i]) return false;
      }
      
      return false; // Versions are equal
    } catch (e) {

      return false;
    }
  }

  /// Mark a version as skipped (user chose to skip this update)
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPrefsService.instance;
    await prefs.setString(_prefKeySkippedVersion, version);

  }

  /// Clear skipped version preference
  Future<void> clearSkippedVersion() async {
    final prefs = await SharedPrefsService.instance;
    await prefs.remove(_prefKeySkippedVersion);
  }

  /// Download update APK and return the file path
  Future<String?> downloadUpdate(
    AppUpdate update, {
    Function(double progress)? onProgress,
  }) async {
    if (update.downloadUrl.isEmpty) {

      return null;
    }

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(update.downloadUrl));
      request.headers['User-Agent'] = 'ScholarDesk-App';
      
      final response = await client.send(request);
      
      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? update.downloadSize;
        
        // Get download directory
        final directory = await getExternalStorageDirectory();
        if (directory == null) {

          return null;
        }
        
        final filePath = '${directory.path}/${update.assetName}';
        final file = File(filePath);
        
        // Delete existing file if present
        if (await file.exists()) {
          await file.delete();
        }
        
        final sink = file.openWrite();
        int downloaded = 0;
        
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;
          
          if (contentLength > 0) {
            final progress = downloaded / contentLength;
            onProgress?.call(progress);
          }
        }
        
        await sink.close();
        client.close();
        

        return filePath;
      } else {

      }
      
      client.close();
    } catch (e) {

    }
    
    return null;
  }

  /// Install APK from file path
  Future<bool> installApk(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {

        return false;
      }
      

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      

      // Mark this APK for deletion after install. Installer runs outside the app
      // so we can't reliably detect completion immediately. We store the pending
      // APK path and associated version and attempt cleanup on next start/resume.
      try {
        await _markPendingApkForDeletion(filePath, currentVersion);
      } catch (e) {

      }
      return result.type == ResultType.done;
    } catch (e) {

      return false;
    }
  }

  /// Mark an APK file path to be deleted once the app has been updated to
  /// [expectedVersion]. This is saved to SharedPreferences and cleaned up in
  /// [cleanPendingApk].
  Future<void> _markPendingApkForDeletion(String apkPath, String expectedVersion) async {
    try {
      final prefs = await SharedPrefsService.instance;
      await prefs.setString(_prefPendingApkPath, apkPath);
      await prefs.setString(_prefPendingApkVersion, expectedVersion);

    } catch (e) {

    }
  }

  /// Check for any pending APK that should be deleted. If the current installed
  /// app version is greater than or equal to the expected version, delete the
  /// APK file and clear the pending entries.
  Future<void> cleanPendingApk() async {
    try {
      final prefs = await SharedPrefsService.instance;
      final apkPath = prefs.getString(_prefPendingApkPath);
      final expectedVersion = prefs.getString(_prefPendingApkVersion);

      if (apkPath == null || expectedVersion == null) return;

      // Ensure we have current version info
      if (_cachedVersion == null) {
        try {
          final packageInfo = await PackageInfo.fromPlatform();
          _cachedVersion = packageInfo.version;
        } catch (e) {

        }
      }

      if (_cachedVersion == null) return;

      // If current version >= expectedVersion, remove the APK
      bool shouldDelete = false;
      try {
        shouldDelete = !_isNewerVersion(expectedVersion, _cachedVersion!);
        // If expectedVersion <= currentVersion then app updated
        if (_compareVersionStrings(_cachedVersion!, expectedVersion) >= 0) {
          shouldDelete = true;
        }
      } catch (_) {
        // Fallback: if versions can't be parsed, attempt deletion anyway
        shouldDelete = true;
      }

      if (shouldDelete) {
        final file = File(apkPath);
        if (await file.exists()) {
          try {
            await file.delete();

          } catch (e) {

          }
        }

        // Clear stored prefs
        await prefs.remove(_prefPendingApkPath);
        await prefs.remove(_prefPendingApkVersion);
      }
    } catch (e) {

    }
  }

  /// Helper to compare two semantic version strings. Returns 1 if a>b, 0 if equal, -1 if a<b
  int _compareVersionStrings(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < maxLen; i++) {
      final ai = i < aParts.length ? aParts[i] : 0;
      final bi = i < bParts.length ? bParts[i] : 0;
      if (ai > bi) return 1;
      if (ai < bi) return -1;
    }
    return 0;
  }

  /// Get the current app version string
  String getCurrentVersion() => currentVersion;
}
