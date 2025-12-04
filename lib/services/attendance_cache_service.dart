import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache service for attendance data
/// Attendance data changes frequently, so cache has shorter validity
class AttendanceCacheService {
  static const String _attendanceCacheKey = 'attendance_cache';
  static const String _attendanceTimestampKey = 'attendance_cache_timestamp';
  
  // Cache is valid for 1 hour before checking for updates
  static const Duration _cacheValidDuration = Duration(hours: 1);
  
  SharedPreferences? _prefs;
  
  /// Initialize shared preferences
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Get cache key based on user and session
  String _getCacheKey(String userId, String clientAbbr, String sessionId) {
    return '${_attendanceCacheKey}_${clientAbbr}_${userId}_$sessionId';
  }
  
  String _getTimestampKey(String userId, String clientAbbr, String sessionId) {
    return '${_attendanceTimestampKey}_${clientAbbr}_${userId}_$sessionId';
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
  
  /// Get cached attendance data
  Future<AttendanceCacheResult?> getCachedAttendance(String userId, String clientAbbr, String sessionId) async {
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
      
      // Parse subjects from JSON
      final List<dynamic> subjectsJson = data['subjects'] ?? [];
      final subjects = subjectsJson.map((s) => CachedAttendanceSubject.fromJson(s)).toList();
      
      debugPrint('📦 Attendance Cache: Loaded ${subjects.length} subjects from cache');
      
      return AttendanceCacheResult(
        subjects: subjects,
        cachedAt: cachedAt,
        isValid: isCacheValid(userId, clientAbbr, sessionId),
      );
    } catch (e) {
      debugPrint('Error reading attendance cache: $e');
      return null;
    }
  }
  
  /// Save attendance data to cache
  Future<void> cacheAttendance({
    required String userId,
    required String clientAbbr,
    required String sessionId,
    required List<CachedAttendanceSubject> subjects,
  }) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);
    
    try {
      final data = {
        'subjects': subjects.map((s) => s.toJson()).toList(),
      };
      
      await _prefs!.setString(cacheKey, jsonEncode(data));
      await _prefs!.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('💾 Attendance Cache: Saved ${subjects.length} subjects to cache');
    } catch (e) {
      debugPrint('Error saving attendance cache: $e');
    }
  }
  
  /// Clear cache for a user
  Future<void> clearCache(String userId, String clientAbbr, String sessionId) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);
    
    await _prefs!.remove(cacheKey);
    await _prefs!.remove(timestampKey);
    
    debugPrint('🗑️ Attendance Cache: Cleared cache');
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

/// Cached attendance subject
class CachedAttendanceSubject {
  final String? name;
  final String? code;
  final String? teacher;
  final String? duration;
  final String? fromDate;
  final String? toDate;
  final String? delivered;
  final String? attended;
  final String? absent;
  final String? leaves;
  final String? percentage;
  final String? totalApprovedDL;
  final String? totalApprovedML;

  CachedAttendanceSubject({
    this.name,
    this.code,
    this.teacher,
    this.duration,
    this.fromDate,
    this.toDate,
    this.delivered,
    this.attended,
    this.absent,
    this.leaves,
    this.percentage,
    this.totalApprovedDL,
    this.totalApprovedML,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'code': code,
    'teacher': teacher,
    'duration': duration,
    'fromDate': fromDate,
    'toDate': toDate,
    'delivered': delivered,
    'attended': attended,
    'absent': absent,
    'leaves': leaves,
    'percentage': percentage,
    'totalApprovedDL': totalApprovedDL,
    'totalApprovedML': totalApprovedML,
  };
  
  factory CachedAttendanceSubject.fromJson(Map<String, dynamic> json) {
    return CachedAttendanceSubject(
      name: json['name'],
      code: json['code'],
      teacher: json['teacher'],
      duration: json['duration'],
      fromDate: json['fromDate'],
      toDate: json['toDate'],
      delivered: json['delivered'],
      attended: json['attended'],
      absent: json['absent'],
      leaves: json['leaves'],
      percentage: json['percentage'],
      totalApprovedDL: json['totalApprovedDL'],
      totalApprovedML: json['totalApprovedML'],
    );
  }
}

/// Result from cache read
class AttendanceCacheResult {
  final List<CachedAttendanceSubject> subjects;
  final DateTime? cachedAt;
  final bool isValid;
  
  AttendanceCacheResult({
    required this.subjects,
    this.cachedAt,
    this.isValid = false,
  });
}
