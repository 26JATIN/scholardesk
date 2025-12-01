import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'feed_detail_screen.dart';

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
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  List<dynamic> _feedItems = [];
  List<dynamic> _filteredFeedItems = [];
  String _searchQuery = '';
  dynamic _nextPageStart;
  bool _hasMoreData = true;
  final Set<String> _loadedItemIds = {}; // Track loaded items to prevent duplicates

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterFeed);
    _scrollController.addListener(_onScroll);
    // Fetch feed after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchFeed();
    });
  }

  void _onScroll() {
    // Check if we're near the bottom (300 pixels before end)
    final isNearBottom = _scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 300;
    
    if (isNearBottom) {
      debugPrint('Near bottom! Loading: $_isLoadingMore, HasMore: $_hasMoreData, SearchEmpty: ${_searchQuery.isEmpty}');
      
      // When user scrolls near the bottom, load more
      if (!_isLoadingMore && _hasMoreData && _searchQuery.isEmpty) {
        debugPrint('🔄 Triggering load more...');
        _loadMoreFeed();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _filterFeed() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredFeedItems = _feedItems;
      } else {
        _filteredFeedItems = _feedItems.where((item) {
          final title = (item['title']?['S'] ?? '').toLowerCase();
          final desc = (item['desc']?['S'] ?? '').toLowerCase();
          return title.contains(_searchQuery) || desc.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _fetchFeed({dynamic start = 0, bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _feedItems = [];
        _filteredFeedItems = [];
        _nextPageStart = null;
        _hasMoreData = true;
        _loadedItemIds.clear(); // Clear duplicate tracking
      });
    } else if (start == 0) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
      final roleId = widget.userData['roleId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final response = await _apiService.getAppFeed(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        roleId: roleId,
        sessionId: sessionId,
        appKey: appKey,
        start: start,
        limit: 20, // Load 20 items per page for smooth scrolling
      );

      if (mounted) {
        final List<dynamic> newItems = response['feed'] ?? [];
        
        // Filter out duplicates based on itemId and timestamp
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
        
        // Check if there's a next page
        final nextPage = response['next'];
        final hasNext = nextPage != null && nextPage is Map && nextPage.isNotEmpty;
        
        // If we got no new unique items but API says there's more, we might be in a loop
        final bool actuallyHasMore = hasNext && uniqueNewItems.isNotEmpty;
        
        setState(() {
          if (isRefresh || start == 0) {
            _feedItems = uniqueNewItems;
          } else {
            _feedItems.addAll(uniqueNewItems);
          }
          _filteredFeedItems = List.from(_feedItems);
          _isLoading = false;
          _nextPageStart = actuallyHasMore ? nextPage : null;
          _hasMoreData = actuallyHasMore;
        });
        
        debugPrint('📥 Feed: Loaded ${uniqueNewItems.length} unique items out of ${newItems.length} fetched. Total: ${_feedItems.length}');
        debugPrint('📍 Next page start: $_nextPageStart');
        debugPrint('✅ Has more data: $_hasMoreData');
      }
    } catch (e) {
      debugPrint('Feed Screen - Error: $e');
      if (mounted) {
        setState(() {
          if (_feedItems.isEmpty) {
            _errorMessage = e.toString().replaceAll('Exception: ', '');
          }
          _isLoading = false;
          _hasMoreData = false;
        });
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
        
        final nextPage = response['next'];
        final hasNext = nextPage != null && nextPage is Map && nextPage.isNotEmpty;
        
        // Stop if we're getting duplicates (indicates loop)
        final bool actuallyHasMore = hasNext && uniqueNewItems.isNotEmpty;

        setState(() {
          _feedItems.addAll(uniqueNewItems);
          _filteredFeedItems = List.from(_feedItems);
          _isLoadingMore = false;
          _nextPageStart = actuallyHasMore ? nextPage : null;
          _hasMoreData = actuallyHasMore;
        });
        
        debugPrint('Feed: Load more added ${uniqueNewItems.length} unique items. Total: ${_feedItems.length}');
      }
    } catch (e) {
      debugPrint('Feed Screen - Load more error: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMoreData = false;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (bool didPop) {
        if (didPop) {
          debugPrint('✅ Feed: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Modern App Bar with gradient
            SliverAppBar.large(
              expandedHeight: 140,
              floating: false,
              pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Announcements',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.secondaryColor,
                      AppTheme.tertiaryColor,
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  _fetchFeed(isRefresh: true);
                },
              ),
            ],
          ),

          // Search Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchBarDelegate(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
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
                      hintText: 'Search announcements...',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.grey.shade400,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
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
                      color: Colors.black87,
                    ),
                  ),
                ),
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
                          child: Column(
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
                                style: GoogleFonts.inter(color: Colors.black54),
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
                          ),
                        ),
                      ),
                    )
                  : _filteredFeedItems.isEmpty
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.isEmpty
                                      ? Icons.inbox_outlined
                                      : Icons.search_off_rounded,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No announcements yet'
                                      : 'No results found for "$_searchQuery"',
                                  style: GoogleFonts.inter(
                                    color: Colors.grey.shade400,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                return _buildFeedCard(
                                  _filteredFeedItems[index],
                                  index,
                                );
                              },
                              childCount: _filteredFeedItems.length,
                            ),
                          ),
                        ),
          
          // Loading indicator at bottom when loading more
          if (_isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Loading more...',
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Load More button when there's more data
          if (!_isLoadingMore && _hasMoreData && _filteredFeedItems.isNotEmpty && _searchQuery.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: _loadMoreFeed,
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('Load More'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
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
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: Colors.grey.shade300,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No more announcements',
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedCard(dynamic item, int index) {
    // Safely extract values with null checks
    final title = (item['title'] != null && item['title']['S'] != null) 
        ? item['title']['S'] as String 
        : 'No Title';
    final desc = (item['desc'] != null && item['desc']['S'] != null)
        ? item['desc']['S'] as String
        : '';
    final date = (item['creDate'] != null && item['creDate']['S'] != null)
        ? item['creDate']['S'] as String
        : '';
    final time = (item['creTime'] != null && item['creTime']['S'] != null)
        ? item['creTime']['S'] as String
        : '';

    // Generate a color gradient based on index
    final gradients = [
      AppTheme.primaryGradient,
      AppTheme.accentGradient,
      AppTheme.successGradient,
      const LinearGradient(
        colors: [Color(0xFFF093FB), Color(0xFFF5576C)],
      ),
    ];
    final gradient = gradients[index % gradients.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
              // Gradient header
              Container(
                height: 8,
                decoration: BoxDecoration(
                  gradient: gradient,
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
                            gradient: gradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.campaign_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (date.isNotEmpty || time.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (date.isNotEmpty) ...[
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        size: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        date,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    if (date.isNotEmpty && time.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      Container(
                                        width: 3,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade400,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    if (time.isNotEmpty) ...[
                                      Icon(
                                        Icons.access_time_rounded,
                                        size: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        time,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          desc,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.5,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
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
    ).animate().fadeIn(delay: (60 * (index % 10)).ms).scale(
          delay: (60 * (index % 10)).ms,
          duration: 300.ms,
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
