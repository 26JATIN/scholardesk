import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cached session data
class CachedSession {
  final String sessionId;
  final String sessionName;
  final String? startDate;
  final String? endDate;

  CachedSession({
    required this.sessionId,
    required this.sessionName,
    this.startDate,
    this.endDate,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'sessionName': sessionName,
    'startDate': startDate,
    'endDate': endDate,
  };

  factory CachedSession.fromJson(Map<String, dynamic> json) => CachedSession(
    sessionId: json['sessionId']?.toString() ?? '',
    sessionName: json['sessionName'] ?? '',
    startDate: json['startDate'],
    endDate: json['endDate'],
  );
}

class SessionsCacheResult {
  final List<CachedSession> sessions;
  final DateTime cachedAt;
  final bool isValid;

  SessionsCacheResult({
    required this.sessions,
    required this.cachedAt,
    required this.isValid,
  });
}

class SessionCacheService {
  static const String _cacheKeyPrefix = 'sessions_cache_';
  static const String _cacheTimeKeyPrefix = 'sessions_cache_time_';
  static const Duration _cacheValidity = Duration(hours: 24); // Sessions rarely change

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String _getCacheKey(String userId, String clientAbbr) {
    return '$_cacheKeyPrefix${userId}_$clientAbbr';
  }

  String _getCacheTimeKey(String userId, String clientAbbr) {
    return '$_cacheTimeKeyPrefix${userId}_$clientAbbr';
  }

  /// Cache sessions list
  Future<void> cacheSessions({
    required String userId,
    required String clientAbbr,
    required List<dynamic> sessions,
  }) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr);
    
    final cachedSessions = sessions.map((s) => CachedSession(
      sessionId: s['sessionId']?.toString() ?? '',
      sessionName: s['sessionName'] ?? '',
      startDate: s['startDate'],
      endDate: s['endDate'],
    ).toJson()).toList();
    
    await _prefs!.setString(cacheKey, jsonEncode(cachedSessions));
    await _prefs!.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    
    debugPrint('📦 Cached ${sessions.length} sessions for user $userId');
  }

  /// Get cached sessions
  Future<SessionsCacheResult?> getCachedSessions(String userId, String clientAbbr) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr);
    
    final cachedJson = _prefs!.getString(cacheKey);
    final cachedTime = _prefs!.getInt(cacheTimeKey);
    
    if (cachedJson == null || cachedTime == null) {
      return null;
    }
    
    try {
      final sessionsData = jsonDecode(cachedJson) as List;
      final sessions = sessionsData
          .map((s) => CachedSession.fromJson(s as Map<String, dynamic>))
          .toList();
      
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
      final isValid = DateTime.now().difference(cachedAt) < _cacheValidity;
      
      return SessionsCacheResult(
        sessions: sessions,
        cachedAt: cachedAt,
        isValid: isValid,
      );
    } catch (e) {
      debugPrint('❌ Error parsing sessions cache: $e');
      return null;
    }
  }

  /// Get cache age as human-readable string
  String getCacheAgeString(String userId, String clientAbbr) {
    final cacheTimeKey = _getCacheTimeKey(userId, clientAbbr);
    final cachedTime = _prefs?.getInt(cacheTimeKey);
    
    if (cachedTime == null) return '';
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
    final difference = DateTime.now().difference(cachedAt);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  /// Clear sessions cache
  Future<void> clearCache(String userId, String clientAbbr) async {
    await init();
    
    await _prefs!.remove(_getCacheKey(userId, clientAbbr));
    await _prefs!.remove(_getCacheTimeKey(userId, clientAbbr));
    
    debugPrint('🗑️ Cleared sessions cache for user $userId');
  }
}
