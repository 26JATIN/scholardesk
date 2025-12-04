import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cached basic profile data (from menu)
class CachedProfileBasic {
  final String? name;
  final String? profileImageUrl;
  final String? details;
  final String? gender;
  final String? parsedSemester;
  final String? parsedGroup;
  final String? parsedBatch;
  final String? parsedRollNo;
  final List<String> menuItems;

  CachedProfileBasic({
    this.name,
    this.profileImageUrl,
    this.details,
    this.gender,
    this.parsedSemester,
    this.parsedGroup,
    this.parsedBatch,
    this.parsedRollNo,
    this.menuItems = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'profileImageUrl': profileImageUrl,
    'details': details,
    'gender': gender,
    'parsedSemester': parsedSemester,
    'parsedGroup': parsedGroup,
    'parsedBatch': parsedBatch,
    'parsedRollNo': parsedRollNo,
    'menuItems': menuItems,
  };

  factory CachedProfileBasic.fromJson(Map<String, dynamic> json) => CachedProfileBasic(
    name: json['name'],
    profileImageUrl: json['profileImageUrl'],
    details: json['details'],
    gender: json['gender'],
    parsedSemester: json['parsedSemester'],
    parsedGroup: json['parsedGroup'],
    parsedBatch: json['parsedBatch'],
    parsedRollNo: json['parsedRollNo'],
    menuItems: (json['menuItems'] as List?)?.cast<String>() ?? [],
  );
}

/// Cached detailed personal info (student, parents, address, etc.)
class CachedPersonalInfo {
  final Map<String, String> studentDetails;
  final Map<String, String> customFields;
  final Map<String, String> addressInfo;
  final String? gender;
  final String? fatherPhotoUrl;
  final Map<String, String> fatherDetails;
  final String? motherPhotoUrl;
  final Map<String, String> motherDetails;

  CachedPersonalInfo({
    this.studentDetails = const {},
    this.customFields = const {},
    this.addressInfo = const {},
    this.gender,
    this.fatherPhotoUrl,
    this.fatherDetails = const {},
    this.motherPhotoUrl,
    this.motherDetails = const {},
  });

  Map<String, dynamic> toJson() => {
    'studentDetails': studentDetails,
    'customFields': customFields,
    'addressInfo': addressInfo,
    'gender': gender,
    'fatherPhotoUrl': fatherPhotoUrl,
    'fatherDetails': fatherDetails,
    'motherPhotoUrl': motherPhotoUrl,
    'motherDetails': motherDetails,
  };

  factory CachedPersonalInfo.fromJson(Map<String, dynamic> json) => CachedPersonalInfo(
    studentDetails: Map<String, String>.from(json['studentDetails'] ?? {}),
    customFields: Map<String, String>.from(json['customFields'] ?? {}),
    addressInfo: Map<String, String>.from(json['addressInfo'] ?? {}),
    gender: json['gender'],
    fatherPhotoUrl: json['fatherPhotoUrl'],
    fatherDetails: Map<String, String>.from(json['fatherDetails'] ?? {}),
    motherPhotoUrl: json['motherPhotoUrl'],
    motherDetails: Map<String, String>.from(json['motherDetails'] ?? {}),
  );
}

class ProfileCacheResult {
  final CachedProfileBasic profile;
  final DateTime cachedAt;
  final bool isValid;

  ProfileCacheResult({
    required this.profile,
    required this.cachedAt,
    required this.isValid,
  });
}

class PersonalInfoCacheResult {
  final CachedPersonalInfo info;
  final DateTime cachedAt;
  final bool isValid; // Always true since it never expires

  PersonalInfoCacheResult({
    required this.info,
    required this.cachedAt,
    required this.isValid,
  });
}

class ProfileCacheService {
  // Basic profile cache keys
  static const String _profileCacheKeyPrefix = 'profile_basic_cache_';
  static const String _profileCacheTimeKeyPrefix = 'profile_basic_cache_time_';
  static const Duration _profileCacheValidity = Duration(hours: 6); // Basic profile can refresh

  // Detailed personal info cache keys (NEVER expires)
  static const String _personalInfoCacheKeyPrefix = 'personal_info_cache_';
  static const String _personalInfoCacheTimeKeyPrefix = 'personal_info_cache_time_';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // === Basic Profile Cache ===

  String _getProfileCacheKey(String userId, String clientAbbr) {
    return '$_profileCacheKeyPrefix${userId}_$clientAbbr';
  }

  String _getProfileCacheTimeKey(String userId, String clientAbbr) {
    return '$_profileCacheTimeKeyPrefix${userId}_$clientAbbr';
  }

  Future<void> cacheBasicProfile({
    required String userId,
    required String clientAbbr,
    required CachedProfileBasic profile,
  }) async {
    await init();
    
    final cacheKey = _getProfileCacheKey(userId, clientAbbr);
    final cacheTimeKey = _getProfileCacheTimeKey(userId, clientAbbr);
    
    await _prefs!.setString(cacheKey, jsonEncode(profile.toJson()));
    await _prefs!.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    
    debugPrint('📦 Cached basic profile for user $userId');
  }

  Future<ProfileCacheResult?> getCachedBasicProfile(String userId, String clientAbbr) async {
    await init();
    
    final cacheKey = _getProfileCacheKey(userId, clientAbbr);
    final cacheTimeKey = _getProfileCacheTimeKey(userId, clientAbbr);
    
    final cachedJson = _prefs!.getString(cacheKey);
    final cachedTime = _prefs!.getInt(cacheTimeKey);
    
    if (cachedJson == null || cachedTime == null) {
      return null;
    }
    
    try {
      final profileData = jsonDecode(cachedJson) as Map<String, dynamic>;
      final profile = CachedProfileBasic.fromJson(profileData);
      
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
      final isValid = DateTime.now().difference(cachedAt) < _profileCacheValidity;
      
      return ProfileCacheResult(
        profile: profile,
        cachedAt: cachedAt,
        isValid: isValid,
      );
    } catch (e) {
      debugPrint('❌ Error parsing basic profile cache: $e');
      return null;
    }
  }

  String getProfileCacheAgeString(String userId, String clientAbbr) {
    final cacheTimeKey = _getProfileCacheTimeKey(userId, clientAbbr);
    final cachedTime = _prefs?.getInt(cacheTimeKey);
    
    if (cachedTime == null) return '';
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
    final difference = DateTime.now().difference(cachedAt);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  // === Detailed Personal Info Cache (NEVER EXPIRES) ===

  String _getPersonalInfoCacheKey(String userId, String clientAbbr) {
    return '$_personalInfoCacheKeyPrefix${userId}_$clientAbbr';
  }

  String _getPersonalInfoCacheTimeKey(String userId, String clientAbbr) {
    return '$_personalInfoCacheTimeKeyPrefix${userId}_$clientAbbr';
  }

  Future<void> cachePersonalInfo({
    required String userId,
    required String clientAbbr,
    required CachedPersonalInfo info,
  }) async {
    await init();
    
    final cacheKey = _getPersonalInfoCacheKey(userId, clientAbbr);
    final cacheTimeKey = _getPersonalInfoCacheTimeKey(userId, clientAbbr);
    
    await _prefs!.setString(cacheKey, jsonEncode(info.toJson()));
    await _prefs!.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    
    debugPrint('📦 Cached detailed personal info for user $userId (NEVER EXPIRES)');
  }

  Future<PersonalInfoCacheResult?> getCachedPersonalInfo(String userId, String clientAbbr) async {
    await init();
    
    final cacheKey = _getPersonalInfoCacheKey(userId, clientAbbr);
    final cacheTimeKey = _getPersonalInfoCacheTimeKey(userId, clientAbbr);
    
    final cachedJson = _prefs!.getString(cacheKey);
    final cachedTime = _prefs!.getInt(cacheTimeKey);
    
    if (cachedJson == null || cachedTime == null) {
      return null;
    }
    
    try {
      final infoData = jsonDecode(cachedJson) as Map<String, dynamic>;
      final info = CachedPersonalInfo.fromJson(infoData);
      
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
      
      // Personal info cache NEVER expires
      return PersonalInfoCacheResult(
        info: info,
        cachedAt: cachedAt,
        isValid: true, // Always valid - never expires
      );
    } catch (e) {
      debugPrint('❌ Error parsing personal info cache: $e');
      return null;
    }
  }

  String getPersonalInfoCacheAgeString(String userId, String clientAbbr) {
    final cacheTimeKey = _getPersonalInfoCacheTimeKey(userId, clientAbbr);
    final cachedTime = _prefs?.getInt(cacheTimeKey);
    
    if (cachedTime == null) return '';
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTime);
    final difference = DateTime.now().difference(cachedAt);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  // === Clear Cache ===

  Future<void> clearProfileCache(String userId, String clientAbbr) async {
    await init();
    
    await _prefs!.remove(_getProfileCacheKey(userId, clientAbbr));
    await _prefs!.remove(_getProfileCacheTimeKey(userId, clientAbbr));
    
    debugPrint('🗑️ Cleared basic profile cache for user $userId');
  }

  Future<void> clearPersonalInfoCache(String userId, String clientAbbr) async {
    await init();
    
    await _prefs!.remove(_getPersonalInfoCacheKey(userId, clientAbbr));
    await _prefs!.remove(_getPersonalInfoCacheTimeKey(userId, clientAbbr));
    
    debugPrint('🗑️ Cleared personal info cache for user $userId');
  }

  Future<void> clearAllCache(String userId, String clientAbbr) async {
    await clearProfileCache(userId, clientAbbr);
    await clearPersonalInfoCache(userId, clientAbbr);
  }
}
