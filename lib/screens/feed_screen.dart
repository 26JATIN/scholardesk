import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/feed_cache_service.dart';
import '../theme/app_theme.dart';
import 'feed_detail_screen.dart';
import '../utils/string_extensions.dart';
import '../main.dart' show themeService;

class FeedScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const FeedScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ApiService _apiService = ApiService();
  final FeedCacheService _cacheService = FeedCacheService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isRefreshingInBackground = false;
  String? _errorMessage;
  List<dynamic> _feedItems = [];
  List<dynamic> _filteredFeedItems = [];
  String _searchQuery = '';
  dynamic _nextPageStart;
  bool _hasMoreData = true;
  final Set<String> _loadedItemIds = {}; // Track loaded items to prevent duplicates
  bool _isOffline = false;
  String _cacheAge = '';
  int _newItemsCount = 0; // Track new items fetched during refresh

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterFeed);
    _scrollController.addListener(_onScroll);
    // Load from cache first, then fetch new items
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromCacheAndFetch();
    });
  }

  /// Load cached data first, then fetch only new items
  Future<void> _loadFromCacheAndFetch() async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first
    final cached = await _cacheService.getCachedFeed(userId, clientAbbr, sessionId);
    
    if (cached != null && cached.items.isNotEmpty) {
      // Load cached items immediately - cache is permanent, always valid
      setState(() {
        _feedItems = List.from(cached.items);
        for (var item in _feedItems) {
          final itemId = item['itemId']?['N']?.toString() ?? '';
          final timestamp = item['timeStamp']?['N']?.toString() ?? '';
          _loadedItemIds.add('$itemId-$timestamp');
        }
        _applySearchFilter();
        _isLoading = false;
        _nextPageStart = cached.nextPage;
        _hasMoreData = cached.hasMore;
        _cacheAge = cached.getCacheAgeString();
        _isOffline = false;
      });
      
      debugPrint('📦 Loaded ${cached.items.length} items from cache');
      debugPrint('📊 hasMore: ${cached.hasMore}');
      
      // Only check for NEW items if enough time has passed (throttle API calls)
      final shouldCheck = await _cacheService.shouldCheckForNewItems(userId, clientAbbr, sessionId);
      if (shouldCheck) {
        debugPrint('🔍 Checking for new items...');
        _fetchNewItemsOnly();
      } else {
        debugPrint('⏰ Skipping new item check - too soon since last check');
      }
    } else {
      // No cache, fetch from API
      debugPrint('📭 No cache found, fetching from API');
      _fetchFeed();
    }
  }

  void _onScroll() {
    // Check if we're near the bottom (300 pixels before end)
    final isNearBottom = _scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 300;
    
    if (isNearBottom && !_isLoadingMore && _hasMoreData) {
      debugPrint('🔄 Triggering load more...');
      _loadMoreFeed();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Sort feed items by date (newest first)
  void _sortFeedByDate(List<dynamic> items) {
    items.sort((a, b) {
      // Try to parse dates for comparison
      final dateA = _parseDate(a['creDate']?['S'] ?? '');
      final dateB = _parseDate(b['creDate']?['S'] ?? '');
      
      if (dateA != null && dateB != null) {
        return dateB.compareTo(dateA); // Newest first
      }
      
      // Fallback to timestamp if available
      final timestampA = int.tryParse(a['timeStamp']?['N']?.toString() ?? '0') ?? 0;
      final timestampB = int.tryParse(b['timeStamp']?['N']?.toString() ?? '0') ?? 0;
      return timestampB.compareTo(timestampA); // Newest first
    });
  }

  // Parse date string to DateTime
  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    
    try {
      // Try common formats: "DD-MM-YYYY", "DD/MM/YYYY", "YYYY-MM-DD"
      final parts = dateStr.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        // Check if first part is year (YYYY-MM-DD)
        if (parts[0].length == 4) {
          return DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        }
        // DD-MM-YYYY or DD/MM/YYYY
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (e) {
      debugPrint('Date parse error: $e');
    }
    return null;
  }

  // Get formatted date label for grouping (e.g., "Today", "Yesterday", "Dec 3, 2025")
  String _getDateLabel(String dateStr) {
    final date = _parseDate(dateStr);
    if (date == null) return dateStr;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    if (dateOnly == today) {
      return 'Today, ${months[date.month - 1]} ${date.day}, ${date.year}';
    } else if (dateOnly == yesterday) {
      return 'Yesterday, ${months[date.month - 1]} ${date.day}, ${date.year}';
    } else if (now.difference(date).inDays < 7 && now.difference(date).inDays > 0) {
      // Within a week - show day name with date
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
    } else {
      // Show full date with year
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  // Build list of items with date headers
  List<dynamic> _buildGroupedFeedList() {
    if (_filteredFeedItems.isEmpty) return [];
    
    final List<dynamic> groupedList = [];
    String? currentDate;
    
    for (var item in _filteredFeedItems) {
      final itemDate = item['creDate']?['S'] ?? '';
      
      if (itemDate != currentDate && itemDate.isNotEmpty) {
        // Add date header
        groupedList.add({'_isDateHeader': true, '_date': itemDate});
        currentDate = itemDate;
      }
      
      groupedList.add(item);
    }
    
    return groupedList;
  }

  void _filterFeed() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applySearchFilter();
    });
  }

  // Apply search filter to feed items
  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredFeedItems = List.from(_feedItems);
    } else {
      _filteredFeedItems = _feedItems.where((item) {
        final title = (item['title']?['S'] ?? '').toLowerCase();
        final desc = (item['desc']?['S'] ?? '').toLowerCase();
        return title.contains(_searchQuery) || desc.contains(_searchQuery);
      }).toList();
    }
  }

  // Build text with highlighted search matches
  Widget _buildHighlightedText(String text, String query, TextStyle style, {int maxLines = 2}) {
    if (query.isEmpty || !text.toLowerCase().contains(query)) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<TextSpan> spans = [];
    final lowerText = text.toLowerCase();
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(query, start);
      if (index == -1) {
        // Add remaining text
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: style));
        }
        break;
      }

      // Add text before match
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: style.copyWith(
          backgroundColor: isDark 
              ? AppTheme.successColor.withOpacity(0.3) 
              : AppTheme.successColor.withOpacity(0.2),
          color: isDark ? Colors.white : AppTheme.successColor,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + query.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Fetch only new items since last cache (incremental update)
  Future<void> _fetchNewItemsOnly() async {
    if (_isRefreshingInBackground) return;
    
    setState(() {
      _isRefreshingInBackground = true;
      _newItemsCount = 0;
    });

    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
      final roleId = widget.userData['roleId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      // Fetch first page to get new items
      final response = await _apiService.getAppFeed(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        roleId: roleId,
        sessionId: sessionId,
        appKey: appKey,
        start: 0,
        limit: 20,
      );

      if (mounted) {
        final List<dynamic> newItems = response['feed'] ?? [];
        
        // Filter only truly new items
        final List<dynamic> trulyNewItems = [];
        for (var item in newItems) {
          final itemId = item['itemId']?['N']?.toString() ?? '';
          final timestamp = item['timeStamp']?['N']?.toString() ?? '';
          final uniqueKey = '$itemId-$timestamp';
          
          if (itemId.isNotEmpty && !_loadedItemIds.contains(uniqueKey)) {
            trulyNewItems.add(item);
            _loadedItemIds.add(uniqueKey);
          }
        }
        
        if (trulyNewItems.isNotEmpty) {
          // Merge with cache
          final mergedItems = await _cacheService.mergeNewItems(
            userId: userId,
            clientAbbr: clientAbbr,
            sessionId: sessionId,
            newItems: trulyNewItems,
            nextPage: _nextPageStart,
            hasMore: _hasMoreData,
          );
          
          setState(() {
            _feedItems = mergedItems;
            _applySearchFilter();
            _newItemsCount = trulyNewItems.length;
            _cacheAge = 'Just now';
          });
          
          debugPrint('🆕 Found ${trulyNewItems.length} new items');
          
          // Show snackbar for new items
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${trulyNewItems.length} new cicular${trulyNewItems.length > 1 ? 's' : ''}'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppTheme.successColor,
              ),
            );
          }
        } else {
          debugPrint('✅ No new items found');
          // Just update the cache timestamp
          await _cacheService.cacheFeed(
            userId: userId,
            clientAbbr: clientAbbr,
            sessionId: sessionId,
            items: _feedItems,
            nextPage: _nextPageStart,
            hasMore: _hasMoreData,
          );
          setState(() {
            _cacheAge = 'Just now';
          });
        }
        
        setState(() {
          _isRefreshingInBackground = false;
          _isOffline = false;
        });
      }
    } catch (e) {
      debugPrint('Background refresh error: $e');
      if (mounted) {
        setState(() {
          _isRefreshingInBackground = false;
          // Don't show error if we have cached data
          if (_feedItems.isEmpty) {
            _errorMessage = e.toString().replaceAll('Exception: ', '');
          }
        });
      }
    }
  }

  Future<void> _fetchFeed({dynamic start = 0, bool isRefresh = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    if (isRefresh) {
      // For refresh, try to load from cache first while fetching new
      final cached = await _cacheService.getCachedFeed(userId, clientAbbr, sessionId);
      
      setState(() {
        _isLoading = cached == null || cached.items.isEmpty;
        _isRefreshingInBackground = cached != null && cached.items.isNotEmpty;
        _errorMessage = null;
        if (cached == null || cached.items.isEmpty) {
          _feedItems = [];
          _filteredFeedItems = [];
          _loadedItemIds.clear();
        }
        _nextPageStart = null;
        _hasMoreData = true;
        _newItemsCount = 0;
      });
      
      // If we have cache, show it first
      if (cached != null && cached.items.isNotEmpty) {
        setState(() {
          _feedItems = List.from(cached.items);
          for (var item in _feedItems) {
            final itemId = item['itemId']?['N']?.toString() ?? '';
            final timestamp = item['timeStamp']?['N']?.toString() ?? '';
            _loadedItemIds.add('$itemId-$timestamp');
          }
          _applySearchFilter();
          _cacheAge = cached.getCacheAgeString();
        });
      }
    } else if (start == 0) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final roleId = widget.userData['roleId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final response = await _apiService.getAppFeed(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        roleId: roleId,
        sessionId: sessionId,
        appKey: appKey,
        start: isRefresh ? 0 : start,
        limit: 20, // Load 20 items per page for smooth scrolling
      );

      if (mounted) {
        final List<dynamic> newItems = response['feed'] ?? [];
        
        final List<dynamic> processedNewItems = [];
        final Set<String> currentBatchIds = {};
        
        for (var item in newItems) {
          final itemId = item['itemId']?['N']?.toString() ?? '';
          final timestamp = item['timeStamp']?['N']?.toString() ?? '';
          final uniqueKey = '$itemId-$timestamp';
          
          if (itemId.isEmpty) continue;
          if (currentBatchIds.contains(uniqueKey)) continue; // Skip duplicates within this batch
          
          currentBatchIds.add(uniqueKey);
          
          // For pagination (not refresh), skip items we already have
          if (!isRefresh && _loadedItemIds.contains(uniqueKey)) continue;
          
          processedNewItems.add(item);
          if (!isRefresh) _loadedItemIds.add(uniqueKey);
        }
        
        // Check if there's a next page
        final nextPage = response['next'];
        final hasNext = nextPage != null && nextPage is Map && nextPage.isNotEmpty;
        
        // Has more data if API says so - don't stop just because we got duplicates
        final bool actuallyHasMore = hasNext;
        
        if (isRefresh) {
          // Merge new items with existing cache
          // We pass processedNewItems (which includes overlap) so mergeNewItems can splice correctly
          if (processedNewItems.isNotEmpty) {
            final mergedItems = await _cacheService.mergeNewItems(
              userId: userId,
              clientAbbr: clientAbbr,
              sessionId: sessionId,
              newItems: processedNewItems,
              nextPage: actuallyHasMore ? nextPage : null,
              hasMore: actuallyHasMore,
            );
            
            setState(() {
              _feedItems = mergedItems;
              _newItemsCount = processedNewItems.length; // This might be misleading if we just refreshed content
              
              // Rebuild loaded IDs from the merged list
              _loadedItemIds.clear();
              for (var item in _feedItems) {
                final itemId = item['itemId']?['N']?.toString() ?? '';
                final timestamp = item['timeStamp']?['N']?.toString() ?? '';
                if (itemId.isNotEmpty) {
                  _loadedItemIds.add('$itemId-$timestamp');
                }
              }
            });
            
            // Show snackbar if we actually got new content (simple check)
            // Ideally we'd compare counts or something, but this is fine
            if (processedNewItems.isNotEmpty && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Feed updated'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppTheme.successColor,
                ),
              );
            }
          }
        } else {
          setState(() {
            if (start == 0) {
              _feedItems = processedNewItems;
            } else {
              _feedItems.addAll(processedNewItems);
            }
          });
        }
        
        // Sort by date (newest first)
        _sortFeedByDate(_feedItems);
        
        // Save to cache
        await _cacheService.cacheFeed(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          items: _feedItems,
          nextPage: actuallyHasMore ? nextPage : null,
          hasMore: actuallyHasMore,
        );
        
        setState(() {
          // Apply current search filter
          _applySearchFilter();
          _isLoading = false;
          _isRefreshingInBackground = false;
          _nextPageStart = actuallyHasMore ? nextPage : null;
          _hasMoreData = actuallyHasMore;
          _cacheAge = 'Just now';
          _isOffline = false;
        });
        
        debugPrint('📥 Feed: Loaded ${processedNewItems.length} unique items out of ${newItems.length} fetched. Total: ${_feedItems.length}');
        debugPrint('📍 Next page start: $_nextPageStart');
        debugPrint('✅ Has more data: $_hasMoreData');
      }
    } catch (e) {
      debugPrint('Feed Screen - Error: $e');
      if (mounted) {
        // If we have cached data, just show offline indicator
        if (_feedItems.isNotEmpty) {
          setState(() {
            _isLoading = false;
            _isRefreshingInBackground = false;
            _isOffline = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Offline - Showing cached data'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.warningColor,
            ),
          );
        } else {
          // Try to load from cache as fallback
          final cached = await _cacheService.getCachedFeed(userId, clientAbbr, sessionId);
          if (cached != null && cached.items.isNotEmpty) {
            setState(() {
              _feedItems = List.from(cached.items);
              for (var item in _feedItems) {
                final itemId = item['itemId']?['N']?.toString() ?? '';
                final timestamp = item['timeStamp']?['N']?.toString() ?? '';
                _loadedItemIds.add('$itemId-$timestamp');
              }
              _applySearchFilter();
              _isLoading = false;
              _isOffline = true;
              _cacheAge = cached.getCacheAgeString();
              _nextPageStart = cached.nextPage;
              _hasMoreData = cached.hasMore;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Offline - Showing cached data ($_cacheAge)'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppTheme.warningColor,
              ),
            );
          } else {
            // Check if it's a network error
            final isNetworkError = e.toString().toLowerCase().contains('socket') ||
                                   e.toString().toLowerCase().contains('connection') ||
                                   e.toString().toLowerCase().contains('network');

            setState(() {
              _errorMessage = isNetworkError ? 'No internet connection' : 'Data not available';
              _isLoading = false;
              _hasMoreData = false;
              _isOffline = true;
            });
                                   
            if (isNetworkError) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please check internet connection'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    }
  }

  Future<void> _loadMoreFeed() async {
    if (_isLoadingMore || !_hasMoreData || _nextPageStart == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
      final roleId = widget.userData['roleId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      // Convert the next page object to JSON string for the API
      final startParam = _nextPageStart is Map 
          ? jsonEncode(_nextPageStart) 
          : _nextPageStart;
      
      debugPrint('🔄 Loading more with start param: $startParam');

      final response = await _apiService.getAppFeed(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        roleId: roleId,
        sessionId: sessionId,
        appKey: appKey,
        start: startParam,
        limit: 20,
      );

      if (mounted) {
        final List<dynamic> newItems = response['feed'] ?? [];
        
        // If API returns empty list, show toast and stop loading
        if (newItems.isEmpty) {
          debugPrint('📭 API returned no more items');
          setState(() {
            _isLoadingMore = false;
            _hasMoreData = false;
            _nextPageStart = null;
          });
          
          final isDark = Theme.of(context).brightness == Brightness.dark;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'End of the list for older circulars',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: isDark ? AppTheme.darkCardColor : Colors.grey.shade200,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          return;
        }
        
        // Filter out duplicates
        final List<dynamic> uniqueNewItems = [];
        for (var item in newItems) {
          final itemId = item['itemId']?['N']?.toString() ?? '';
          final timestamp = item['timeStamp']?['N']?.toString() ?? '';
          final uniqueKey = '$itemId-$timestamp';
          
          if (itemId.isNotEmpty && !_loadedItemIds.contains(uniqueKey)) {
            uniqueNewItems.add(item);
            _loadedItemIds.add(uniqueKey);
          }
        }
        
        // If all items were duplicates, show toast
        if (uniqueNewItems.isEmpty) {
          debugPrint('🔄 All items were duplicates');
          setState(() {
            _isLoadingMore = false;
            _hasMoreData = false;
            _nextPageStart = null;
          });
          
          final isDark = Theme.of(context).brightness == Brightness.dark;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'End of the list for older circulars',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: isDark ? AppTheme.darkCardColor : Colors.grey.shade200,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          return;
        }
        
        final nextPage = response['next'];
        final hasNext = nextPage != null && nextPage is Map && nextPage.isNotEmpty;

        setState(() {
          _feedItems.addAll(uniqueNewItems);
          // Sort by date (newest first)
          _sortFeedByDate(_feedItems);
          // Apply current search filter to include new items
          _applySearchFilter();
          _isLoadingMore = false;
          _nextPageStart = hasNext ? nextPage : null;
          _hasMoreData = hasNext;
        });
        
        // Append to cache
        await _cacheService.appendToCache(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          newItems: uniqueNewItems,
          nextPage: hasNext ? nextPage : null,
          hasMore: hasNext,
        );
        
        debugPrint('Feed: Load more added ${uniqueNewItems.length} unique items. Total: ${_feedItems.length}');
      }
    } catch (e) {
      debugPrint('Feed Screen - Load more error: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          // Don't set hasMoreData to false on error - allow retry
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Feed: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
        body: RefreshIndicator(
          onRefresh: () => _fetchFeed(isRefresh: true),
          color: isDark ? Colors.white : Colors.black87,
          backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
          displacement: 20,
          strokeWidth: 2.5,
          triggerMode: RefreshIndicatorTriggerMode.anywhere,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            cacheExtent: 500, // Cache items 500px outside viewport
            slivers: [
              // Modern App Bar
              SliverAppBar.large(
                expandedHeight: 140,
                floating: false,
                pinned: true,
                backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_rounded, 
                    color: isDark ? Colors.white : Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
            flexibleSpace: FlexibleSpaceBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ciculars',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (_isRefreshingInBackground) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
              background: Container(
                color: isDark ? AppTheme.darkSurfaceColor : AppTheme.secondaryColor.withOpacity(0.1),
              ),
            ),
            actions: [
              // New items indicator
              if (_newItemsCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '+$_newItemsCount',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // Cache age indicator - more compact
              if (_cacheAge.isNotEmpty && !_isLoading && _newItemsCount == 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isOffline 
                          ? AppTheme.warningColor.withOpacity(0.15)
                          : (isDark ? AppTheme.darkCardColor : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isOffline) ...[
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 12,
                            color: AppTheme.warningColor,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _cacheAge,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _isOffline 
                                ? AppTheme.warningColor 
                                : (isDark ? Colors.white60 : Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () => themeService.toggleTheme(),
              ),
            ],
          ),

          // Search Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchBarDelegate(
              child: Builder(
                builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    color: isDark ? AppTheme.darkSurfaceColor : Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCardColor : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isDark ? null : [
                          BoxShadow(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search ciculars...',
                          hintStyle: GoogleFonts.inter(
                            color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded,
                                    color: isDark ? Colors.grey.shade500 : Colors.grey),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Content
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _errorMessage != null
                  ? SliverFillRemaining(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Builder(
                            builder: (context) {
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 64,
                                    color: AppTheme.errorColor,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      color: isDark ? Colors.grey.shade400 : Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton.icon(
                                    onPressed: () {
                                      _fetchFeed(isRefresh: true);
                                    },
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    )
                  : _filteredFeedItems.isEmpty
                      ? SliverFillRemaining(
                          child: Center(
                            child: Builder(
                              builder: (context) {
                                final isDark = Theme.of(context).brightness == Brightness.dark;
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _searchQuery.isEmpty
                                          ? Icons.inbox_outlined
                                          : Icons.search_off_rounded,
                                      size: 64,
                                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'No ciculars yet'
                                          : 'No results found for "$_searchQuery"',
                                      style: GoogleFonts.inter(
                                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                                        fontSize: 15,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (_searchQuery.isNotEmpty && _hasMoreData) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Searched ${_feedItems.length} ciculars',
                                        style: GoogleFonts.inter(
                                          color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        onPressed: _loadMoreFeed,
                                        icon: const Icon(Icons.search_rounded, size: 18),
                                        label: const Text('Load More & Search'),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final groupedList = _buildGroupedFeedList();
                                final item = groupedList[index];
                                
                                // Check if this is a date header
                                if (item['_isDateHeader'] == true) {
                                  return _buildDateHeader(item['_date']);
                                }
                                
                                return RepaintBoundary(
                                  child: _buildFeedCard(item),
                                );
                              },
                              childCount: _buildGroupedFeedList().length,
                              addRepaintBoundaries: false, // We add our own
                              addAutomaticKeepAlives: false,
                            ),
                          ),
                        ),
          
          // Loading indicator at bottom when loading more
          if (_isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty 
                                ? 'Loading more feeds to search...'
                                : 'Loading more...',
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Found ${_filteredFeedItems.length} matches so far',
                              style: GoogleFonts.inter(
                                color: AppTheme.successColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          
          // Load More button when there's more data
          if (!_isLoadingMore && _hasMoreData && _feedItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loadMoreFeed,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(_searchQuery.isNotEmpty 
                            ? 'Load More (Searching...)' 
                            : 'Load More'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final isDark = Theme.of(context).brightness == Brightness.dark;
                            return Text(
                              'Showing ${_filteredFeedItems.length} of ${_feedItems.length} loaded',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          
          // End of list indicator
          if (!_isLoadingMore && !_hasMoreData && _filteredFeedItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      
                      return Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All ${_feedItems.length} circulars loaded',
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeader(String dateStr) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = _getDateLabel(dateStr);
    
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: isDark 
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedCard(dynamic item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Safely extract values with null checks
    final title = (item['title'] != null && item['title']['S'] != null) 
        ? (item['title']['S'] as String).decodeHtml 
        : 'No Title';
    final desc = (item['desc'] != null && item['desc']['S'] != null)
        ? (item['desc']['S'] as String).decodeHtml
        : '';
    final timeStr = (item['creTime'] != null && item['creTime']['S'] != null)
        ? item['creTime']['S'] as String
        : '';
    final time = formatTime(timeStr);

    // Check if this item matches search query
    final bool isSearchMatch = _searchQuery.isNotEmpty && 
        (title.toLowerCase().contains(_searchQuery) || 
         desc.toLowerCase().contains(_searchQuery));

    // Use primary color, with highlight for search matches
    final accentColor = isSearchMatch 
        ? AppTheme.successColor  // Highlight matching items
        : AppTheme.primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: isDark 
            ? Border.all(color: Colors.white.withOpacity(0.06))
            : null,
        boxShadow: isDark ? null : const [
          BoxShadow(
            color: Color(0x0F000000), // Static color instead of withOpacity
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            final itemId = (item['itemId'] != null && item['itemId']['N'] != null)
                ? item['itemId']['N'] as String
                : '';
            final itemType = (item['itemType'] != null && item['itemType']['N'] != null)
                ? item['itemType']['N'] as String
                : '';
            
            if (itemId.isNotEmpty && itemType.isNotEmpty) {
              // Show offline warning if we're offline
              if (_isOffline) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You\'re offline. Some details may not load.',
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.warningColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
              
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FeedDetailScreen(
                    clientDetails: widget.clientDetails,
                    userData: widget.userData,
                    itemId: itemId,
                    itemType: itemType,
                    title: title,
                  ),
                ),
              );
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Solid color header
              Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.campaign_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildHighlightedText(
                            title,
                            _searchQuery,
                            GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 2,
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkElevatedColor : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: _buildHighlightedText(
                          desc,
                          _searchQuery,
                          GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? Colors.grey.shade300 : Colors.black87,
                            height: 1.5,
                          ),
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Search Bar Delegate for Sticky Header
class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _SearchBarDelegate({required this.child});

  @override
  double get minExtent => 80;

  @override
  double get maxExtent => 80;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: 80,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_SearchBarDelegate oldDelegate) {
    return false;
  }
}
