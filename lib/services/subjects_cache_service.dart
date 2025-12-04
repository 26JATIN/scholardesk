import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CachedSubject {
  final String? name;
  final String? specialization;
  final String? code;
  final String? type;
  final String? group;
  final String? credits;
  final bool isOptional;

  CachedSubject({
    this.name,
    this.specialization,
    this.code,
    this.type,
    this.group,
    this.credits,
    this.isOptional = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'specialization': specialization,
    'code': code,
    'type': type,
    'group': group,
    'credits': credits,
    'isOptional': isOptional,
  };

  factory CachedSubject.fromJson(Map<String, dynamic> json) => CachedSubject(
    name: json['name'],
    specialization: json['specialization'],
    code: json['code'],
    type: json['type'],
    group: json['group'],
    credits: json['credits'],
    isOptional: json['isOptional'] ?? false,
  );
}

class SubjectsCacheResult {
  final List<CachedSubject> subjects;
  final String semesterTitle;
  final String? currentSemester;
  final String? currentGroup;
  final DateTime cachedAt;
  final bool isValid;

  SubjectsCacheResult({
    required this.subjects,
    required this.semesterTitle,
    this.currentSemester,
    this.currentGroup,
    required this.cachedAt,
    required this.isValid,
  });
}

class SubjectsCacheService {
  static const String _cacheKeyPrefix = 'subjects_cache_';
  static const String _cacheTimeKeyPrefix = 'subjects_cache_time_';
  static const Duration _cacheValidity = Duration(hours: 24); // Subjects don't change often

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String _getCacheKey(String userId, String clientAbbr, String sessionId) {
    return '$_cacheKeyPrefix${userId}_${clientAbbr}_$sessionId';
  }

  String _getCacheTimeKey(String userId, String clientAbbr, String sessionId) {
    return '$_cacheTimeKeyPrefix${userId}_${clientAbbr}_$sessionId';
  }

  /// Cache subjects data
  Future<void> cacheSubjects({
    required String userId,
    required String clientAbbr,
    required String sessionId,
    required List<CachedSubject> subjects,
    required String semesterTitle,
    String? currentSemester,
    String? currentGroup,
  }) async {
    await init();
    
    final cacheData = {
      'subjects': subjects.map((s) => s.toJson()).toList(),
      'semesterTitle': semesterTitle,
      'currentSemester': currentSemester,
      'currentGroup': currentGroup,
    };
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr, sessionId);
    
    await _prefs!.setString(cacheKey, jsonEncode(cacheData));
    await _prefs!.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    
    debugPrint('📦 Cached ${subjects.length} subjects for user $userId');
  }

  /// Get cached subjects
  Future<SubjectsCacheResult?> getCachedSubjects(String userId, String clientAbbr, String sessionId) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr, sessionId);
    
    final cachedJson = _prefs!.getString(cacheKey);
    final cachedTime = _prefs!.getInt(cacheTimeKey);
    
    if (cachedJson == null || cachedTime == null) {
      return null;
    }
    
    try {
      final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
      final subjectsList = (cacheData['subjects'] as List)
          .map((json) => CachedSubject.fromJson(json as Map<String, dynamic>))
          .toList();
      
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
      final isValid = DateTime.now().difference(cachedAt) < _cacheValidity;
      
      return SubjectsCacheResult(
        subjects: subjectsList,
        semesterTitle: cacheData['semesterTitle'] ?? 'Subjects',
        currentSemester: cacheData['currentSemester'],
        currentGroup: cacheData['currentGroup'],
        cachedAt: cachedAt,
        isValid: isValid,
      );
    } catch (e) {
      debugPrint('❌ Error parsing subjects cache: $e');
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
    
    final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr, sessionId);
    
    await _prefs!.remove(cacheKey);
    await _prefs!.remove(cacheTimeKey);
    
    debugPrint('🗑️ Cleared subjects cache for user $userId');
  }
}
