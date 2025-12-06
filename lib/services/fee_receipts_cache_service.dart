import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache service for fee receipts data
/// Fee receipts don't change frequently, so cache has longer validity
class FeeReceiptsCacheService {
  static const String _receiptsCacheKey = 'fee_receipts_cache';
  static const String _receiptsTimestampKey = 'fee_receipts_cache_timestamp';
  
  // Cache is valid for 24 hours before checking for updates
  static const Duration _cacheValidDuration = Duration(hours: 24);
  
  SharedPreferences? _prefs;
  
  /// Initialize shared preferences
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Get cache key based on user
  String _getCacheKey(String userId, String clientAbbr) {
    return '${_receiptsCacheKey}_${clientAbbr}_$userId';
  }
  
  String _getTimestampKey(String userId, String clientAbbr) {
    return '${_receiptsTimestampKey}_${clientAbbr}_$userId';
  }
  
  /// Check if cache is valid
  bool isCacheValid(String userId, String clientAbbr) {
    if (_prefs == null) return false;
    
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    final cacheTimestamp = _prefs!.getInt(timestampKey);
    
    if (cacheTimestamp == null) return false;
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cacheTimestamp);
    final age = DateTime.now().difference(cachedAt);
    
    return age < _cacheValidDuration;
  }
  
  /// Get cached receipts data
  Future<FeeReceiptsCacheResult?> getCachedReceipts(String userId, String clientAbbr) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    
    final cachedData = _prefs!.getString(cacheKey);
    final cacheTimestamp = _prefs!.getInt(timestampKey);
    
    if (cachedData == null) return null;
    
    try {
      final Map<String, dynamic> data = jsonDecode(cachedData);
      final DateTime? cachedAt = cacheTimestamp != null 
          ? DateTime.fromMillisecondsSinceEpoch(cacheTimestamp)
          : null;
      
      // Parse receipts from JSON
      final List<dynamic> receiptsJson = data['receipts'] ?? [];
      final receipts = receiptsJson.map((r) => CachedFeeReceipt.fromJson(r)).toList();
      final totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? 0.0;
      
      debugPrint('📦 Fee Receipts Cache: Loaded ${receipts.length} receipts from cache');
      
      return FeeReceiptsCacheResult(
        receipts: receipts,
        totalPaid: totalPaid,
        cachedAt: cachedAt,
        isValid: isCacheValid(userId, clientAbbr),
      );
    } catch (e) {
      debugPrint('Error reading fee receipts cache: $e');
      return null;
    }
  }
  
  /// Save fee receipts data to cache
  Future<void> cacheReceipts({
    required String userId,
    required String clientAbbr,
    required List<CachedFeeReceipt> receipts,
    required double totalPaid,
  }) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    
    try {
      final data = {
        'receipts': receipts.map((r) => r.toJson()).toList(),
        'totalPaid': totalPaid,
      };
      
      await _prefs!.setString(cacheKey, jsonEncode(data));
      await _prefs!.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('💾 Fee Receipts Cache: Saved ${receipts.length} receipts to cache');
    } catch (e) {
      debugPrint('Error saving fee receipts cache: $e');
    }
  }
  
  /// Clear cache for a user
  Future<void> clearCache(String userId, String clientAbbr) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    
    await _prefs!.remove(cacheKey);
    await _prefs!.remove(timestampKey);
    
    debugPrint('🗑️ Fee Receipts Cache: Cleared cache');
  }
  
  /// Get cache age as human-readable string
  String getCacheAgeString(String userId, String clientAbbr) {
    if (_prefs == null) return '';
    
    final timestampKey = _getTimestampKey(userId, clientAbbr);
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

/// Cached fee receipt
class CachedFeeReceipt {
  final String receiptNo;
  final double amount;
  final String paidOnStr;
  final String cycle;
  final String? semester;
  final String? pdfUrl;
  final String? receiptId;

  CachedFeeReceipt({
    required this.receiptNo,
    required this.amount,
    required this.paidOnStr,
    required this.cycle,
    this.semester,
    this.pdfUrl,
    this.receiptId,
  });

  Map<String, dynamic> toJson() => {
    'receiptNo': receiptNo,
    'amount': amount,
    'paidOnStr': paidOnStr,
    'cycle': cycle,
    'semester': semester,
    'pdfUrl': pdfUrl,
    'receiptId': receiptId,
  };

  factory CachedFeeReceipt.fromJson(Map<String, dynamic> json) => CachedFeeReceipt(
    receiptNo: json['receiptNo'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    paidOnStr: json['paidOnStr'] as String? ?? '',
    cycle: json['cycle'] as String? ?? '',
    semester: json['semester'] as String?,
    pdfUrl: json['pdfUrl'] as String?,
    receiptId: json['receiptId'] as String?,
  );
}

/// Result of cache lookup
class FeeReceiptsCacheResult {
  final List<CachedFeeReceipt> receipts;
  final double totalPaid;
  final DateTime? cachedAt;
  final bool isValid;

  FeeReceiptsCacheResult({
    required this.receipts,
    required this.totalPaid,
    this.cachedAt,
    required this.isValid,
  });
}
