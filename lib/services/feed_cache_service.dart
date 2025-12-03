import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smart caching service for feed data with offline support
/// Old feeds never change, so cache is permanent. Only new items are fetched.
class FeedCacheService {
  static const String _feedCacheKey = 'feed_cache';
  static const String _feedTimestampKey = 'feed_cache_timestamp';
  static const String _feedNextPageKey = 'feed_next_page';
  static const String _feedHasMoreKey = 'feed_has_more';
  static const String _allOldFeedsLoadedKey = 'feed_all_old_loaded'; // Tracks if we've loaded all historical feeds
  static const String _oldestTimestampKey = 'feed_oldest_timestamp'; // Oldest feed timestamp we have
  static const String _newestTimestampKey = 'feed_newest_timestamp'; // Newest feed timestamp we have
  
  // Cache is permanent - old feeds never change
  // Only check for NEW items periodically (5 min threshold for background check)
  static const Duration _newItemCheckThreshold = Duration(minutes: 5);
  
  SharedPreferences? _prefs;
  
  /// Initialize shared preferences
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Get cache key based on user
  String _getCacheKey(String userId, String clientAbbr) {
    return '${_feedCacheKey}_${clientAbbr}_$userId';
  }
  
  String _getTimestampKey(String userId, String clientAbbr) {
    return '${_feedTimestampKey}_${clientAbbr}_$userId';
  }
  
  String _getNextPageKey(String userId, String clientAbbr) {
    return '${_feedNextPageKey}_${clientAbbr}_$userId';
  }
  
  String _getHasMoreKey(String userId, String clientAbbr) {
    return '${_feedHasMoreKey}_${clientAbbr}_$userId';
  }
  
  String _getAllOldLoadedKey(String userId, String clientAbbr) {
    return '${_allOldFeedsLoadedKey}_${clientAbbr}_$userId';
  }
  
  String _getOldestTimestampKey(String userId, String clientAbbr) {
    return '${_oldestTimestampKey}_${clientAbbr}_$userId';
  }
  
  String _getNewestTimestampKey(String userId, String clientAbbr) {
    return '${_newestTimestampKey}_${clientAbbr}_$userId';
  }
  
  /// Check if all old feeds have been loaded (no more pagination needed)
  bool areAllOldFeedsLoaded(String userId, String clientAbbr) {
    if (_prefs == null) return false;
    return _prefs!.getBool(_getAllOldLoadedKey(userId, clientAbbr)) ?? false;
  }
  
  /// Mark that all old feeds have been loaded - never fetch old feeds again
  Future<void> markAllOldFeedsLoaded(String userId, String clientAbbr) async {
    await init();
    await _prefs!.setBool(_getAllOldLoadedKey(userId, clientAbbr), true);
    debugPrint('✅ Cache: Marked all old feeds as loaded - will never paginate again');
  }
  
  /// Get the newest timestamp from cached feeds
  int? getNewestTimestamp(String userId, String clientAbbr) {
    if (_prefs == null) return null;
    return _prefs!.getInt(_getNewestTimestampKey(userId, clientAbbr));
  }
  
  /// Get the oldest timestamp from cached feeds
  int? getOldestTimestamp(String userId, String clientAbbr) {
    if (_prefs == null) return null;
    return _prefs!.getInt(_getOldestTimestampKey(userId, clientAbbr));
  }
  
  /// Update timestamp bounds from items
  Future<void> _updateTimestampBounds(String userId, String clientAbbr, List<dynamic> items) async {
    if (items.isEmpty) return;
    
    int? minTimestamp;
    int? maxTimestamp;
    
    for (var item in items) {
      final timestamp = int.tryParse(item['timeStamp']?['N']?.toString() ?? '0');
      if (timestamp != null && timestamp > 0) {
        if (minTimestamp == null || timestamp < minTimestamp) {
          minTimestamp = timestamp;
        }
        if (maxTimestamp == null || timestamp > maxTimestamp) {
          maxTimestamp = timestamp;
        }
      }
    }
    
    if (minTimestamp != null) {
      final currentOldest = getOldestTimestamp(userId, clientAbbr);
      if (currentOldest == null || minTimestamp < currentOldest) {
        await _prefs!.setInt(_getOldestTimestampKey(userId, clientAbbr), minTimestamp);
      }
    }
    
    if (maxTimestamp != null) {
      final currentNewest = getNewestTimestamp(userId, clientAbbr);
      if (currentNewest == null || maxTimestamp > currentNewest) {
        await _prefs!.setInt(_getNewestTimestampKey(userId, clientAbbr), maxTimestamp);
      }
    }
  }
  
  /// Check if we should check for new items (throttle API calls)
  bool shouldCheckForNewItems(String userId, String clientAbbr) {
    if (_prefs == null) return true;
    
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    final lastCheck = _prefs!.getInt(timestampKey);
    
    if (lastCheck == null) return true;
    
    final lastCheckTime = DateTime.fromMillisecondsSinceEpoch(lastCheck);
    final age = DateTime.now().difference(lastCheckTime);
    
    return age > _newItemCheckThreshold;
  }
  
  /// Check cache status - cache is always valid if it exists (permanent cache)
  CacheStatus getCacheStatus(String userId, String clientAbbr) {
    if (_prefs == null) return CacheStatus.empty;
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final cachedData = _prefs!.getString(cacheKey);
    
    if (cachedData == null) return CacheStatus.empty;
    
    // Cache is always fresh - old feeds never change
    // We only need to check for NEW items periodically
    return CacheStatus.fresh;
  }
  
  /// Get cached feed items
  Future<FeedCacheResult?> getCachedFeed(String userId, String clientAbbr) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    final nextPageKey = _getNextPageKey(userId, clientAbbr);
    final hasMoreKey = _getHasMoreKey(userId, clientAbbr);
    
    final cachedData = _prefs!.getString(cacheKey);
    final cacheTimestamp = _prefs!.getInt(timestampKey);
    final nextPageData = _prefs!.getString(nextPageKey);
    final hasMore = _prefs!.getBool(hasMoreKey) ?? true;
    final allOldLoaded = areAllOldFeedsLoaded(userId, clientAbbr);
    
    if (cachedData == null) return null;
    
    try {
      final List<dynamic> items = jsonDecode(cachedData);
      final DateTime? cachedAt = cacheTimestamp != null 
          ? DateTime.fromMillisecondsSinceEpoch(cacheTimestamp)
          : null;
      final dynamic nextPage = nextPageData != null ? jsonDecode(nextPageData) : null;
      
      debugPrint('📦 Cache: Loaded ${items.length} items from cache (allOldLoaded: $allOldLoaded)');
      
      return FeedCacheResult(
        items: items,
        cachedAt: cachedAt,
        nextPage: allOldLoaded ? null : nextPage, // No next page if all old feeds loaded
        hasMore: allOldLoaded ? false : hasMore,  // No more data if all old feeds loaded
        status: getCacheStatus(userId, clientAbbr),
        allOldFeedsLoaded: allOldLoaded,
      );
    } catch (e) {
      debugPrint('Error reading cache: $e');
      return null;
    }
  }
  
  /// Save feed items to cache
  Future<void> cacheFeed({
    required String userId,
    required String clientAbbr,
    required List<dynamic> items,
    dynamic nextPage,
    bool hasMore = true,
  }) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    final nextPageKey = _getNextPageKey(userId, clientAbbr);
    final hasMoreKey = _getHasMoreKey(userId, clientAbbr);
    
    try {
      await _prefs!.setString(cacheKey, jsonEncode(items));
      await _prefs!.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
      
      if (nextPage != null) {
        await _prefs!.setString(nextPageKey, jsonEncode(nextPage));
      } else {
        await _prefs!.remove(nextPageKey);
      }
      
      await _prefs!.setBool(hasMoreKey, hasMore);
      
      // Update timestamp bounds
      await _updateTimestampBounds(userId, clientAbbr, items);
      
      // If no more data, mark all old feeds as loaded permanently
      if (!hasMore) {
        await markAllOldFeedsLoaded(userId, clientAbbr);
      }
      
      debugPrint('💾 Cache: Saved ${items.length} items to cache (hasMore: $hasMore)');
    } catch (e) {
      debugPrint('Error saving cache: $e');
    }
  }
  
  /// Merge new items with cached items (for incremental updates)
  Future<List<dynamic>> mergeNewItems({
    required String userId,
    required String clientAbbr,
    required List<dynamic> newItems,
    dynamic nextPage,
    bool hasMore = true,
  }) async {
    await init();
    
    final cached = await getCachedFeed(userId, clientAbbr);
    final existingItems = cached?.items ?? [];
    
    // Create a set of existing item keys for deduplication
    final existingKeys = <String>{};
    for (var item in existingItems) {
      final itemId = item['itemId']?['N']?.toString() ?? '';
      final timestamp = item['timeStamp']?['N']?.toString() ?? '';
      existingKeys.add('$itemId-$timestamp');
    }
    
    // Filter truly new items
    final trulyNewItems = <dynamic>[];
    for (var item in newItems) {
      final itemId = item['itemId']?['N']?.toString() ?? '';
      final timestamp = item['timeStamp']?['N']?.toString() ?? '';
      final key = '$itemId-$timestamp';
      
      if (!existingKeys.contains(key)) {
        trulyNewItems.add(item);
        existingKeys.add(key);
      }
    }
    
    // Merge: new items first, then existing
    final mergedItems = [...trulyNewItems, ...existingItems];
    
    // Sort by timestamp (newest first)
    mergedItems.sort((a, b) {
      final timestampA = int.tryParse(a['timeStamp']?['N']?.toString() ?? '0') ?? 0;
      final timestampB = int.tryParse(b['timeStamp']?['N']?.toString() ?? '0') ?? 0;
      return timestampB.compareTo(timestampA);
    });
    
    // Save merged items to cache
    await cacheFeed(
      userId: userId,
      clientAbbr: clientAbbr,
      items: mergedItems,
      nextPage: nextPage,
      hasMore: hasMore,
    );
    
    debugPrint('🔄 Cache: Merged ${trulyNewItems.length} new items with ${existingItems.length} cached. Total: ${mergedItems.length}');
    
    return mergedItems;
  }
  
  /// Append more items to cache (for pagination)
  Future<void> appendToCache({
    required String userId,
    required String clientAbbr,
    required List<dynamic> newItems,
    dynamic nextPage,
    bool hasMore = true,
  }) async {
    await init();
    
    final cached = await getCachedFeed(userId, clientAbbr);
    final existingItems = cached?.items ?? [];
    
    // Create a set of existing item keys for deduplication
    final existingKeys = <String>{};
    for (var item in existingItems) {
      final itemId = item['itemId']?['N']?.toString() ?? '';
      final timestamp = item['timeStamp']?['N']?.toString() ?? '';
      existingKeys.add('$itemId-$timestamp');
    }
    
    // Filter duplicates
    final uniqueNewItems = <dynamic>[];
    for (var item in newItems) {
      final itemId = item['itemId']?['N']?.toString() ?? '';
      final timestamp = item['timeStamp']?['N']?.toString() ?? '';
      final key = '$itemId-$timestamp';
      
      if (!existingKeys.contains(key)) {
        uniqueNewItems.add(item);
        existingKeys.add(key);
      }
    }
    
    // Append to existing
    final allItems = [...existingItems, ...uniqueNewItems];
    
    // Sort by timestamp (newest first)
    allItems.sort((a, b) {
      final timestampA = int.tryParse(a['timeStamp']?['N']?.toString() ?? '0') ?? 0;
      final timestampB = int.tryParse(b['timeStamp']?['N']?.toString() ?? '0') ?? 0;
      return timestampB.compareTo(timestampA);
    });
    
    // Save to cache
    await cacheFeed(
      userId: userId,
      clientAbbr: clientAbbr,
      items: allItems,
      nextPage: nextPage,
      hasMore: hasMore,
    );
    
    debugPrint('📎 Cache: Appended ${uniqueNewItems.length} items. Total: ${allItems.length}');
  }
  
  /// Clear cache for a user
  Future<void> clearCache(String userId, String clientAbbr) async {
    await init();
    
    final cacheKey = _getCacheKey(userId, clientAbbr);
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    final nextPageKey = _getNextPageKey(userId, clientAbbr);
    final hasMoreKey = _getHasMoreKey(userId, clientAbbr);
    
    await _prefs!.remove(cacheKey);
    await _prefs!.remove(timestampKey);
    await _prefs!.remove(nextPageKey);
    await _prefs!.remove(hasMoreKey);
    
    debugPrint('🗑️ Cache: Cleared feed cache');
  }
  
  /// Get cache age as human-readable string
  String getCacheAgeString(String userId, String clientAbbr) {
    if (_prefs == null) return 'No cache';
    
    final timestampKey = _getTimestampKey(userId, clientAbbr);
    final cacheTimestamp = _prefs!.getInt(timestampKey);
    
    if (cacheTimestamp == null) return 'No cache';
    
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cacheTimestamp);
    final now = DateTime.now();
    final age = now.difference(cachedAt);
    
    if (age.inMinutes < 1) return 'Just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}

/// Cache status enum
enum CacheStatus {
  empty,    // No cache exists
  fresh,    // Cache exists and is valid (permanent - old feeds don't change)
  stale,    // Deprecated - kept for compatibility but cache is always fresh
  expired,  // Deprecated - kept for compatibility but cache never expires
}

/// Result from cache read
class FeedCacheResult {
  final List<dynamic> items;
  final DateTime? cachedAt;
  final dynamic nextPage;
  final bool hasMore;
  final CacheStatus status;
  final bool allOldFeedsLoaded; // True if we've loaded all historical feeds
  
  FeedCacheResult({
    required this.items,
    this.cachedAt,
    this.nextPage,
    this.hasMore = true,
    this.status = CacheStatus.empty,
    this.allOldFeedsLoaded = false,
  });
}
