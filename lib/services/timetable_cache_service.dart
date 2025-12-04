import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimetableCacheResult {
  final Map<String, List<Map<String, String>>> timetable;
  final Map<String, String> subjectNames;
  final DateTime cachedAt;
  final bool isValid;

  TimetableCacheResult({
    required this.timetable,
    required this.subjectNames,
    required this.cachedAt,
    required this.isValid,
  });
}

class TimetableCacheService {
  static const String _timetableCacheKeyPrefix = 'timetable_cache_';
  static const String _subjectNamesCacheKeyPrefix = 'timetable_subjects_cache_';
  static const String _cacheTimeKeyPrefix = 'timetable_cache_time_';
  static const Duration _cacheValidity = Duration(hours: 12); // Timetable may change occasionally

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String _getTimetableCacheKey(String userId, String clientAbbr, String sessionId) {
    return '$_timetableCacheKeyPrefix${userId}_${clientAbbr}_$sessionId';
  }

  String _getSubjectNamesCacheKey(String userId, String clientAbbr, String sessionId) {
    return '$_subjectNamesCacheKeyPrefix${userId}_${clientAbbr}_$sessionId';
  }

  String _getCacheTimeKey(String userId, String clientAbbr, String sessionId) {
    return '$_cacheTimeKeyPrefix${userId}_${clientAbbr}_$sessionId';
  }

  /// Cache timetable data
  Future<void> cacheTimetable({
    required String userId,
    required String clientAbbr,
    required String sessionId,
    required Map<String, List<Map<String, String>>> timetable,
    Map<String, String>? subjectNames, // Make optional
  }) async {
    await init();
    
    final timetableCacheKey = _getTimetableCacheKey(userId, clientAbbr, sessionId);
    final subjectNamesCacheKey = _getSubjectNamesCacheKey(userId, clientAbbr, sessionId);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr, sessionId);
    
    // Convert timetable map to JSON-safe format
    final timetableJson = timetable.map((key, value) => 
      MapEntry(key, value.map((period) => period).toList())
    );
    
    await _prefs!.setString(timetableCacheKey, jsonEncode(timetableJson));
    
    // Only update subject names if provided, otherwise preserve existing or set empty
    if (subjectNames != null) {
      await _prefs!.setString(subjectNamesCacheKey, jsonEncode(subjectNames));
    }
    
    await _prefs!.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    
    int totalPeriods = timetable.values.fold(0, (sum, periods) => sum + periods.length);
    debugPrint('📦 Cached timetable with $totalPeriods periods and ${subjectNames?.length ?? "preserved"} subject names');
  }

  /// Get cached timetable
  Future<TimetableCacheResult?> getCachedTimetable(String userId, String clientAbbr, String sessionId) async {
    await init();
    
    final timetableCacheKey = _getTimetableCacheKey(userId, clientAbbr, sessionId);
    final subjectNamesCacheKey = _getSubjectNamesCacheKey(userId, clientAbbr, sessionId);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr, sessionId);
    
    final timetableJson = _prefs!.getString(timetableCacheKey);
    final subjectNamesJson = _prefs!.getString(subjectNamesCacheKey);
    final cachedTime = _prefs!.getInt(cacheTimeKey);
    
    if (timetableJson == null || cachedTime == null) {
      return null;
    }
    
    try {
      final timetableData = jsonDecode(timetableJson) as Map<String, dynamic>;
      final timetable = timetableData.map((key, value) => 
        MapEntry(key, (value as List).map((period) => 
          Map<String, String>.from(period as Map)
        ).toList())
      );
      
      Map<String, String> subjectNames = {};
      if (subjectNamesJson != null) {
        final subjectNamesData = jsonDecode(subjectNamesJson) as Map<String, dynamic>;
        subjectNames = Map<String, String>.from(subjectNamesData);
      }
      
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
      final isValid = DateTime.now().difference(cachedAt) < _cacheValidity;
      
      return TimetableCacheResult(
        timetable: timetable,
        subjectNames: subjectNames,
        cachedAt: cachedAt,
        isValid: isValid,
      );
    } catch (e) {
      debugPrint('❌ Error parsing timetable cache: $e');
      return null;
    }
  }

  /// Get cache age as human-readable string
  String getCacheAgeString(String userId, String clientAbbr, String sessionId) {
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr, sessionId);
    final cachedTime = _prefs?.getInt(cacheTimeKey);
    
    if (cachedTime == null) return '';
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
    final difference = DateTime.now().difference(cachedAt);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  /// Clear cache for a user
  Future<void> clearCache(String userId, String clientAbbr, String sessionId) async {
    await init();
    
    final timetableCacheKey = _getTimetableCacheKey(userId, clientAbbr, sessionId);
    final subjectNamesCacheKey = _getSubjectNamesCacheKey(userId, clientAbbr, sessionId);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr, sessionId);
    
    await _prefs!.remove(timetableCacheKey);
    await _prefs!.remove(subjectNamesCacheKey);
    await _prefs!.remove(cacheTimeKey);
    
    debugPrint('🗑️ Cleared timetable cache for user $userId');
  }
}
