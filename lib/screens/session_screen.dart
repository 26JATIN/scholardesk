import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../services/session_cache_service.dart';
import 'home_screen.dart';
import '../theme/app_theme.dart';

class SessionScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const SessionScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final ApiService _apiService = ApiService();
  final SessionCacheService _cacheService = SessionCacheService();
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  List<dynamic> _sessions = [];
  String _cacheAge = '';
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadFromCacheAndFetch();
  }

  Future<void> _loadFromCacheAndFetch() async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    
    await _cacheService.init();
    
    final cached = await _cacheService.getCachedSessions(userId, clientAbbr);
    
    if (cached != null) {
      // Load cached data immediately
      setState(() {
        _sessions = cached.sessions.map((s) => {
          'sessionId': s.sessionId,
          'sessionName': s.sessionName,
          'startDate': s.startDate,
          'endDate': s.endDate,
        }).toList();
        _isLoading = false;
        _cacheAge = _cacheService.getCacheAgeString(userId, clientAbbr);
        _isOffline = false;
      });
      
      debugPrint('📦 Loaded ${_sessions.length} sessions from cache');
      
      // If cache is still valid, don't fetch from API
      if (cached.isValid) {
        debugPrint('✅ Cache is still valid, skipping API fetch');
        return;
      }
      
      // Cache expired, fetch fresh data in background
      debugPrint('⏰ Cache expired, fetching fresh data...');
      _fetchSessions(isBackground: true);
    } else {
      // No cache, fetch from API
      debugPrint('📭 No cache found, fetching from API');
      _fetchSessions();
    }
  }

  Future<void> _fetchSessions({bool isRefresh = false, bool isBackground = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    
    if (isRefresh) {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    } else if (!isBackground) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final baseUrl = widget.clientDetails['baseUrl'];

      final sessions = await _apiService.getAllSession(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
      );

      // Cache the sessions
      await _cacheService.cacheSessions(
        userId: userId,
        clientAbbr: clientAbbr,
        sessions: sessions,
      );

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoading = false;
          _isRefreshing = false;
          _isOffline = false;
          _cacheAge = 'Just now';
        });
        
        if (isRefresh) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Sessions updated'),
              backgroundColor: AppTheme.successColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // If we have cached data, show it with offline indicator
        if (_sessions.isNotEmpty) {
          setState(() {
            _isLoading = false;
            _isRefreshing = false;
            _isOffline = true;
          });
          
          if (isRefresh) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Could not refresh. Using cached data.'),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } else {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
            _isRefreshing = false;
          });
        }
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _fetchSessions(isRefresh: true);
  }

  Future<void> _changeSession(Map<String, dynamic> session) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Update local userData
      final newUserData = Map<String, dynamic>.from(widget.userData);
      newUserData['sessionId'] = session['sessionId'];
      newUserData['sessionName'] = session['sessionName']; // Optional, if used elsewhere

      // Persist changes
      await _apiService.saveSession(widget.clientDetails, newUserData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session changed to ${session['sessionName']}'),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        // Navigate to HomeScreen to reload everything with new session
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              clientDetails: widget.clientDetails,
              userData: newUserData,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to change session: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSessionId = widget.userData['sessionId'].toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Session: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: AppTheme.primaryColor,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverAppBar.large(
                expandedHeight: 140,
                floating: false,
                pinned: true,
                backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                surfaceTintColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                leading: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  'Select Session',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 100),
            ),
            actions: [
              if (_isRefreshing)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.white70 : AppTheme.primaryColor,
                    ),
                  ),
                ),
              if (_isOffline && !_isRefreshing)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Cached',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_cacheAge.isNotEmpty && !_isRefreshing)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.green.shade900 : Colors.green.shade50).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.save_rounded,
                        size: 14,
                        color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _cacheAge,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          _isLoading
              ? SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(
                    color: isDark ? Colors.white : AppTheme.primaryColor,
                  )),
                )
              : _errorMessage != null
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'Error: $_errorMessage',
                              style: GoogleFonts.inter(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final session = _sessions[index];
                            final isSelected = session['sessionId'].toString() == currentSessionId;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: isDark ? AppTheme.darkCardColor : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: isSelected
                                    ? Border.all(color: AppTheme.primaryColor, width: 2.5)
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected 
                                        ? AppTheme.primaryColor.withOpacity(0.2)
                                        : isDark 
                                            ? Colors.black.withOpacity(0.3)
                                            : Colors.black.withOpacity(0.06),
                                    blurRadius: isSelected ? 15 : 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  onTap: isSelected ? null : () => _changeSession(session),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? AppTheme.primaryColor
                                                : isDark
                                                    ? AppTheme.darkElevatedColor
                                                    : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(14),
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: AppTheme.primaryColor.withOpacity(0.3),
                                                      blurRadius: 8,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Icon(
                                            Icons.calendar_month_rounded,
                                            color: isSelected 
                                                ? Colors.white 
                                                : isDark 
                                                    ? Colors.grey.shade400
                                                    : Colors.grey.shade600,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                session['sessionName'] ?? 'Unknown Session',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 16,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  color: isSelected 
                                                      ? AppTheme.primaryColor 
                                                      : isDark 
                                                          ? Colors.white
                                                          : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.event_rounded,
                                                    size: 14,
                                                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      '${session['startDate']} - ${session['endDate']}',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.successColor,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.successColor.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ).animate().fadeIn(delay: (50 * index).ms, duration: 400.ms).slideY(begin: 0.2);
                          },
                          childCount: _sessions.length,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
