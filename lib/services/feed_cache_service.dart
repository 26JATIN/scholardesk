import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CachedFeed {
  final List<Map<String, dynamic>> items;
  final DateTime cachedAt;
  final String? oldestTimestamp;
  final String? newestTimestamp;
  final dynamic nextPage;
  final bool hasMore;

  CachedFeed({
    required this.items,
    required this.cachedAt,
    this.oldestTimestamp,
    this.newestTimestamp,
    this.nextPage,
    this.hasMore = true,
  });

  bool get isValid => items.isNotEmpty;

  String getCacheAgeString() {
    final now = DateTime.now();
    final difference = now.difference(cachedAt);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Map<String, dynamic> toJson() => {
        'items': items,
        'cachedAt': cachedAt.toIso8601String(),
        'oldestTimestamp': oldestTimestamp,
        'newestTimestamp': newestTimestamp,
        'nextPage': nextPage,
        'hasMore': hasMore,
      };

  factory CachedFeed.fromJson(Map<String, dynamic> json) {
    return CachedFeed(
      items: List<Map<String, dynamic>>.from(
        (json['items'] as List).map((e) => Map<String, dynamic>.from(e)),
      ),
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      oldestTimestamp: json['oldestTimestamp'] as String?,
      newestTimestamp: json['newestTimestamp'] as String?,
      nextPage: json['nextPage'],
      hasMore: json['hasMore'] as bool? ?? true,
    );
  }
}

class FeedCacheService {
  static const String _cachePrefix = 'feed_cache_';
  static const String _timestampPrefix = 'feed_timestamps_';
  static const String _lastCheckPrefix = 'feed_last_check_';

  static const Duration _minCheckInterval = Duration(minutes: 5);

  String _getCacheKey(String userId, String clientAbbr, String sessionId) =>
      '${_cachePrefix}${userId}_${clientAbbr}_$sessionId';

  String _getTimestampKey(String userId, String clientAbbr, String sessionId) =>
      '${_timestampPrefix}${userId}_${clientAbbr}_$sessionId';

  String _getLastCheckKey(String userId, String clientAbbr, String sessionId) =>
      '${_lastCheckPrefix}${userId}_${clientAbbr}_$sessionId';

  Future<CachedFeed?> getCachedFeed(
      String userId, String clientAbbr, String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);
      final cached = prefs.getString(cacheKey);

      if (cached != null) {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        return CachedFeed.fromJson(json);
      }
    } catch (e) {
      print('FeedCacheService: Error getting cached feed: $e');
    }
    return null;
  }

  Future<void> cacheFeed({
    required String userId,
    required String clientAbbr,
    required String sessionId,
    required List<dynamic> items,
    String? oldestTimestamp,
    String? newestTimestamp,
    dynamic nextPage,
    bool hasMore = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(userId, clientAbbr, sessionId);

      // Convert List<dynamic> to List<Map<String, dynamic>>
      final typedItems = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final cachedFeed = CachedFeed(
        items: typedItems,
        cachedAt: DateTime.now(),
        oldestTimestamp: oldestTimestamp,
        newestTimestamp: newestTimestamp,
        nextPage: nextPage,
        hasMore: hasMore,
      );

      await prefs.setString(cacheKey, jsonEncode(cachedFeed.toJson()));
      await _updateTimestampBounds(userId, clientAbbr, sessionId, typedItems);
    } catch (e) {
      print('FeedCacheService: Error caching feed: $e');
    }
  }

  /// Merge new items and return the merged list
  Future<List<Map<String, dynamic>>> mergeNewItems({
    required String userId,
    required String clientAbbr,
    required String sessionId,
    required List<dynamic> newItems,
    dynamic nextPage,
    bool hasMore = true,
  }) async {
    try {
      final existing = await getCachedFeed(userId, clientAbbr, sessionId);
      final typedNewItems = newItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      
      if (existing == null) {
        await cacheFeed(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          items: typedNewItems,
          nextPage: nextPage,
          hasMore: hasMore,
        );
        return typedNewItems;
      }

      final existingIds =
          existing.items.map((item) => item['itemId']?['N']?.toString()).toSet();
      final uniqueNewItems = typedNewItems
          .where((item) => !existingIds.contains(item['itemId']?['N']?.toString()))
          .toList();

      if (uniqueNewItems.isEmpty) return existing.items;

      final mergedItems = [...uniqueNewItems, ...existing.items];
      String? newestTimestamp = existing.newestTimestamp;
      if (uniqueNewItems.isNotEmpty) {
        newestTimestamp =
            uniqueNewItems.first['timeStamp']?['N']?.toString() ?? existing.newestTimestamp;
      }

      await cacheFeed(
        userId: userId,
        clientAbbr: clientAbbr,
        sessionId: sessionId,
        items: mergedItems,
        oldestTimestamp: existing.oldestTimestamp,
        newestTimestamp: newestTimestamp,
        nextPage: nextPage ?? existing.nextPage,
        hasMore: hasMore,
      );
      
      return mergedItems;
    } catch (e) {
      print('FeedCacheService: Error merging new items: $e');
      return [];
    }
  }

  Future<void> appendToCache({
    required String userId,
    required String clientAbbr,
    required String sessionId,
    required List<dynamic> newItems,
    String? newOldestTimestamp,
    dynamic nextPage,
    bool hasMore = true,
  }) async {
    try {
      final existing = await getCachedFeed(userId, clientAbbr, sessionId);
      final typedItems = newItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      
      if (existing == null) {
        await cacheFeed(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          items: typedItems,
          oldestTimestamp: newOldestTimestamp,
          nextPage: nextPage,
          hasMore: hasMore,
        );
        return;
      }

      final existingIds =
          existing.items.map((item) => item['itemId']?['N']?.toString()).toSet();
      final uniqueOlderItems = typedItems
          .where((item) => !existingIds.contains(item['itemId']?['N']?.toString()))
          .toList();

      if (uniqueOlderItems.isEmpty) return;

      final mergedItems = [...existing.items, ...uniqueOlderItems];

      await cacheFeed(
        userId: userId,
        clientAbbr: clientAbbr,
        sessionId: sessionId,
        items: mergedItems,
        oldestTimestamp: newOldestTimestamp ?? existing.oldestTimestamp,
        newestTimestamp: existing.newestTimestamp,
        nextPage: nextPage,
        hasMore: hasMore,
      );
    } catch (e) {
      print('FeedCacheService: Error appending to cache: $e');
    }
  }

  Future<void> _updateTimestampBounds(String userId, String clientAbbr,
      String sessionId, List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampKey = _getTimestampKey(userId, clientAbbr, sessionId);

      final existingJson = prefs.getString(timestampKey);
      Map<String, dynamic> timestamps = existingJson != null
          ? jsonDecode(existingJson) as Map<String, dynamic>
          : {};

      final firstTimestamp = items.first['timestamp'] as String?;
      final lastTimestamp = items.last['timestamp'] as String?;

      if (firstTimestamp != null) {
        timestamps['newest'] = firstTimestamp;
      }
      if (lastTimestamp != null) {
        timestamps['oldest'] = lastTimestamp;
      }

      await prefs.setString(timestampKey, jsonEncode(timestamps));
    } catch (e) {
      print('FeedCacheService: Error updating timestamp bounds: $e');
    }
  }

  Future<bool> shouldCheckForNewItems(
      String userId, String clientAbbr, String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckKey = _getLastCheckKey(userId, clientAbbr, sessionId);
      final lastCheckStr = prefs.getString(lastCheckKey);

      if (lastCheckStr == null) {
        await prefs.setString(lastCheckKey, DateTime.now().toIso8601String());
        return true;
      }

      final lastCheck = DateTime.parse(lastCheckStr);
      final now = DateTime.now();

      if (now.difference(lastCheck) >= _minCheckInterval) {
        await prefs.setString(lastCheckKey, now.toIso8601String());
        return true;
      }

      return false;
    } catch (e) {
      return true;
    }
  }

  Future<Map<String, dynamic>> getCacheStatus(
      String userId, String clientAbbr, String sessionId) async {
    final cached = await getCachedFeed(userId, clientAbbr, sessionId);
    return {
      'hasCachedData': cached != null,
      'itemCount': cached?.items.length ?? 0,
      'oldestTimestamp': cached?.oldestTimestamp,
      'newestTimestamp': cached?.newestTimestamp,
      'cachedAt': cached?.cachedAt.toIso8601String(),
      'cacheAge': cached?.getCacheAgeString(),
    };
  }

  Future<void> clearCache(
      String userId, String clientAbbr, String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getCacheKey(userId, clientAbbr, sessionId));
      await prefs.remove(_getTimestampKey(userId, clientAbbr, sessionId));
      await prefs.remove(_getLastCheckKey(userId, clientAbbr, sessionId));
    } catch (e) {
      print('FeedCacheService: Error clearing cache: $e');
    }
  }

  Future<String?> getCacheAgeString(
      String userId, String clientAbbr, String sessionId) async {
    final cached = await getCachedFeed(userId, clientAbbr, sessionId);
    return cached?.getCacheAgeString();
  }
}
