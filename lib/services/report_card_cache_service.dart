import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache service for report card data
/// Report card data changes infrequently (once per semester), so cache is long-lived
class ReportCardCacheService {
  static const String _reportCardCacheKey = 'report_card_cache';
  static const String _reportCardTimestampKey = 'report_card_cache_timestamp';
  
  // Cache is valid for 24 hours before checking for updates
  static const Duration _cacheValidDuration = Duration(hours: 24);
  
  SharedPreferences? _prefs;
  
  /// Initialize shared preferences
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Get cache key based on user and session
  String _getCacheKey(String userId, String clientAbbr, String sessionId) {
    return '${_reportCardCacheKey}_${clientAbbr}_${userId}_$sessionId';
  }
  
  String _getTimestampKey(String userId, String clientAbbr, String sessionId) {
    return '${_reportCardTimestampKey}_${clientAbbr}_${userId}_$sessionId';
  }
  
  /// Check if cache is valid
  bool isCacheValid(String userId, String clientAbbr, String sessionId) {
    if (_prefs == null) return false;
    
    final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);
    final cacheTimestamp = _prefs!.getInt(timestampKey);
    
    if (cacheTimestamp == null) return false;
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cacheTimestamp);
    final age = DateTime.now().difference(cachedAt);
    
    return age < _cacheValidDuration;
  }
  
  /// Get cached report card data
  Future<ReportCardCacheResult?> getCachedReportCard(String userId, String clientAbbr, String sessionId) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);
    
    final cachedData = _prefs!.getString(cacheKey);
    final cacheTimestamp = _prefs!.getInt(timestampKey);
    
    if (cachedData == null) return null;
    
    try {
      final Map<String, dynamic> data = jsonDecode(cachedData);
      final DateTime? cachedAt = cacheTimestamp != null 
          ? DateTime.fromMillisecondsSinceEpoch(cacheTimestamp)
          : null;
      
      // Parse semesters from JSON
      final List<dynamic> semestersJson = data['semesters'] ?? [];
      final semesters = semestersJson.map((s) => CachedSemesterResult.fromJson(s)).toList();
      
      debugPrint('📦 ReportCard Cache: Loaded ${semesters.length} semesters from cache');
      
      return ReportCardCacheResult(
        semesters: semesters,
        cachedAt: cachedAt,
        isValid: isCacheValid(userId, clientAbbr, sessionId),
      );
    } catch (e) {
      debugPrint('Error reading report card cache: $e');
      return null;
    }
  }
  
  /// Save report card data to cache
  Future<void> cacheReportCard({
    required String userId,
    required String clientAbbr,
    required String sessionId,
    required List<CachedSemesterResult> semesters,
  }) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);
    
    try {
      final data = {
        'semesters': semesters.map((s) => s.toJson()).toList(),
      };
      
      await _prefs!.setString(cacheKey, jsonEncode(data));
      await _prefs!.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('💾 ReportCard Cache: Saved ${semesters.length} semesters to cache');
    } catch (e) {
      debugPrint('Error saving report card cache: $e');
    }
  }
  
  /// Clear cache for a user
  Future<void> clearCache(String userId, String clientAbbr, String sessionId) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);
    
    await _prefs!.remove(cacheKey);
    await _prefs!.remove(timestampKey);
    
    debugPrint('🗑️ ReportCard Cache: Cleared cache');
  }
  
  /// Get cache age as human-readable string
  String getCacheAgeString(String userId, String clientAbbr, String sessionId) {
    if (_prefs == null) return '';
    
    final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);
    final cacheTimestamp = _prefs!.getInt(timestampKey);
    
    if (cacheTimestamp == null) return '';
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cacheTimestamp);
    final now = DateTime.now();
    final age = now.difference(cachedAt);
    
    if (age.inMinutes < 1) return 'Just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}

/// Cached semester result
class CachedSemesterResult {
  final String semesterName;
  final String sgpa;
  final String cgpa;
  final List<CachedSubjectResult> subjects;

  CachedSemesterResult({
    required this.semesterName,
    required this.sgpa,
    required this.cgpa,
    required this.subjects,
  });
  
  Map<String, dynamic> toJson() => {
    'semesterName': semesterName,
    'sgpa': sgpa,
    'cgpa': cgpa,
    'subjects': subjects.map((s) => s.toJson()).toList(),
  };
  
  factory CachedSemesterResult.fromJson(Map<String, dynamic> json) {
    return CachedSemesterResult(
      semesterName: json['semesterName'] ?? '',
      sgpa: json['sgpa'] ?? '',
      cgpa: json['cgpa'] ?? '',
      subjects: (json['subjects'] as List<dynamic>?)
          ?.map((s) => CachedSubjectResult.fromJson(s))
          .toList() ?? [],
    );
  }
}

/// Cached subject result
class CachedSubjectResult {
  final String serialNo;
  final String code;
  final String name;
  final String credits;
  final String grade;

  CachedSubjectResult({
    required this.serialNo,
    required this.code,
    required this.name,
    required this.credits,
    required this.grade,
  });
  
  Map<String, dynamic> toJson() => {
    'serialNo': serialNo,
    'code': code,
    'name': name,
    'credits': credits,
    'grade': grade,
  };
  
  factory CachedSubjectResult.fromJson(Map<String, dynamic> json) {
    return CachedSubjectResult(
      serialNo: json['serialNo'] ?? '',
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      credits: json['credits'] ?? '',
      grade: json['grade'] ?? '',
    );
  }
}

/// Result from cache read
class ReportCardCacheResult {
  final List<CachedSemesterResult> semesters;
  final DateTime? cachedAt;
  final bool isValid;
  
  ReportCardCacheResult({
    required this.semesters,
    this.cachedAt,
    this.isValid = false,
  });
}
