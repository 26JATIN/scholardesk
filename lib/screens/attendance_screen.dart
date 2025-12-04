import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/attendance_cache_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' show themeService;

class AttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;
  final String? initialSubjectCode;

  const AttendanceScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
    this.initialSubjectCode,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final AttendanceCacheService _cacheService = AttendanceCacheService();
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _cacheAge = '';
  bool _isOffline = false;
  List<AttendanceSubject> _subjects = [];
  Map<int, int> _classesToMissMap = {}; // Track classes to miss per subject
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromCacheAndFetch();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }
  
  /// Safely update tab controller when subjects change
  void _updateTabController({int? preferredIndex}) {
    if (_subjects.isEmpty) {
      _tabController?.dispose();
      _tabController = null;
      return;
    }
    
    int initialIndex = preferredIndex ?? _tabController?.index ?? 0;
    
    // If we have an initial subject code, find its index
    if (widget.initialSubjectCode != null && preferredIndex == null && _tabController == null) {
      final index = _subjects.indexWhere((s) => 
        s.code?.toLowerCase() == widget.initialSubjectCode!.toLowerCase() ||
        (s.name?.toLowerCase().contains(widget.initialSubjectCode!.toLowerCase()) ?? false)
      );
      if (index != -1) {
        initialIndex = index;
      }
    }
    
    final newIndex = initialIndex.clamp(0, _subjects.length - 1);
    
    // Only recreate if length changed or controller doesn't exist
    if (_tabController == null || _tabController!.length != _subjects.length) {
      _tabController?.dispose();
      _tabController = TabController(
        length: _subjects.length, 
        vsync: this,
        initialIndex: newIndex,
      );
    } else if (_tabController!.index != newIndex) {
      _tabController!.animateTo(newIndex);
    }
  }

  /// Load cached data first, then fetch from API if needed
  Future<void> _loadFromCacheAndFetch() async {
    await _cacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first
    final cached = await _cacheService.getCachedAttendance(userId, clientAbbr, sessionId);
    
    if (cached != null && cached.subjects.isNotEmpty) {
      // Load cached items immediately
      _subjects = cached.subjects.map((s) => AttendanceSubject()
        ..name = s.name
        ..code = s.code
        ..teacher = s.teacher
        ..duration = s.duration
        ..fromDate = s.fromDate
        ..toDate = s.toDate
        ..delivered = s.delivered
        ..attended = s.attended
        ..absent = s.absent
        ..leaves = s.leaves
        ..percentage = s.percentage
        ..totalApprovedDL = s.totalApprovedDL
        ..totalApprovedML = s.totalApprovedML
      ).toList();
      
      _updateTabController();
      
      setState(() {
        _isLoading = false;
        _cacheAge = _cacheService.getCacheAgeString(userId, clientAbbr, sessionId);
        _isOffline = false;
      });
      
      debugPrint('📦 Loaded ${cached.subjects.length} subjects from cache');
      
      // Check for updates in background if cache is old
      if (!cached.isValid) {
        debugPrint('🔍 Cache is stale, refreshing in background...');
        _fetchAttendance(isBackgroundRefresh: true);
      }
    } else {
      // No cache, fetch from API
      debugPrint('📭 No cache found, fetching from API');
      _fetchAttendance();
    }
  }

  Future<void> _fetchAttendance({bool isBackgroundRefresh = false, bool isRefresh = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    
    // Store existing subjects in case of refresh failure
    final existingSubjects = List<AttendanceSubject>.from(_subjects);
    final existingCacheAge = _cacheAge;
    
    if (isRefresh) {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    } else if (!isBackgroundRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final roleId = widget.userData['roleId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final htmlContent = await _apiService.getCommonPage(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
      );

      _parseHtml(htmlContent);
      
      // Cache the results
      if (_subjects.isNotEmpty) {
        await _cacheService.cacheAttendance(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          subjects: _subjects.map((s) => CachedAttendanceSubject(
            name: s.name,
            code: s.code,
            teacher: s.teacher,
            duration: s.duration,
            fromDate: s.fromDate,
            toDate: s.toDate,
            delivered: s.delivered,
            attended: s.attended,
            absent: s.absent,
            leaves: s.leaves,
            percentage: s.percentage,
            totalApprovedDL: s.totalApprovedDL,
            totalApprovedML: s.totalApprovedML,
          )).toList(),
        );
      }
      
      if (mounted) {
        final currentIndex = _tabController?.index;
        _updateTabController(preferredIndex: currentIndex);
        
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _isOffline = false;
          _cacheAge = 'Just now';
        });
        
        if (isRefresh && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Attendance updated'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Attendance Screen - Error: $e');
      if (mounted) {
        // Check if it's a network error
        final errorStr = e.toString().toLowerCase();
        final isNetworkError = errorStr.contains('socket') || 
                               errorStr.contains('connection') || 
                               errorStr.contains('network') ||
                               errorStr.contains('timeout') ||
                               errorStr.contains('host');
        
        // If we had existing data (refresh case), restore it
        if (existingSubjects.isNotEmpty) {
          setState(() {
            _subjects = existingSubjects;
            _isLoading = false;
            _isRefreshing = false;
            _isOffline = isNetworkError;
            _cacheAge = existingCacheAge;
          });
          if (isRefresh) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isNetworkError 
                    ? 'No internet connection' 
                    : 'Failed to refresh: ${e.toString().replaceAll('Exception: ', '')}'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppTheme.warningColor,
              ),
            );
          }
        } else {
          // Try to load from cache as fallback
          final sessionId = widget.userData['sessionId'].toString();
          final cached = await _cacheService.getCachedAttendance(userId, clientAbbr, sessionId);
          if (cached != null && cached.subjects.isNotEmpty) {
            _subjects = cached.subjects.map((s) => AttendanceSubject()
              ..name = s.name
              ..code = s.code
              ..teacher = s.teacher
              ..duration = s.duration
              ..fromDate = s.fromDate
              ..toDate = s.toDate
              ..delivered = s.delivered
              ..attended = s.attended
              ..absent = s.absent
              ..leaves = s.leaves
              ..percentage = s.percentage
              ..totalApprovedDL = s.totalApprovedDL
              ..totalApprovedML = s.totalApprovedML
            ).toList();
            
            _updateTabController();
            
            setState(() {
              _isLoading = false;
              _isRefreshing = false;
              _isOffline = isNetworkError;
              _cacheAge = _cacheService.getCacheAgeString(userId, clientAbbr, sessionId);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isNetworkError 
                    ? 'No internet - Showing cached data ($_cacheAge)'
                    : 'Error - Showing cached data'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppTheme.warningColor,
              ),
            );
          } else {
            setState(() {
              _errorMessage = isNetworkError ? 'No internet connection' : 'Data not available';
              _isLoading = false;
              _isRefreshing = false;
              _isOffline = isNetworkError;
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
  
  /// Handle pull to refresh
  Future<void> _handleRefresh() async {
    await _fetchAttendance(isRefresh: true);
  }

  void _parseHtml(String htmlString) {
    debugPrint('Raw Attendance HTML: $htmlString');
    final document = html_parser.parse(htmlString);
    final subjectBoxes = document.querySelectorAll('.tt-box-new');
    
    _subjects = subjectBoxes.map((box) {
      final subject = AttendanceSubject();
      
      // Subject Name and Code
      final periodNumberDiv = box.querySelector('.tt-period-number');
      if (periodNumberDiv != null) {
        final spans = periodNumberDiv.querySelectorAll('span');
        if (spans.isNotEmpty) subject.name = spans[0].text.trim();
        if (spans.length > 1) subject.code = spans[1].text.trim();
      }

      // Details
      final detailsDivs = box.querySelectorAll('.tt-period-name');
      for (var div in detailsDivs) {
        String text = div.text.trim();
        // Normalize whitespace and special chars
        text = text.replaceAll(RegExp(r'[\u00A0\s]+'), ' ').trim(); // Replace &nbsp and multiple spaces
        
        if (text.toLowerCase().contains('teacher')) {
          // Extract teacher name - everything after "Teacher :" or "Teacher:"
          final teacherMatch = RegExp(r'Teacher\s*:?\s*(.+)', caseSensitive: false).firstMatch(text);
          if (teacherMatch != null) {
            subject.teacher = teacherMatch.group(1)?.trim();
          }
        } else if (text.toLowerCase().contains('from') && text.toLowerCase().contains('to')) {
          // Parse: "From : 01 Jul 2025    TO : 02 Dec 2025"
          // More robust regex that handles various formats
          
          // Try multiple patterns
          String normalizedText = text.replaceAll(RegExp(r'\s+'), ' ');
          
          // Pattern 1: "From : DATE TO : DATE" or "From: DATE TO: DATE"
          final datePattern = RegExp(
            r'From\s*:?\s*(\d{1,2}\s+\w+\s+\d{4})\s*(?:TO|To|to)\s*:?\s*(\d{1,2}\s+\w+\s+\d{4})',
            caseSensitive: false
          );
          final match = datePattern.firstMatch(normalizedText);
          
          if (match != null) {
            subject.fromDate = match.group(1)?.trim();
            subject.toDate = match.group(2)?.trim();
            subject.duration = '${subject.fromDate} - ${subject.toDate}';
          } else {
            // Fallback: try to extract any dates
            final allDates = RegExp(r'(\d{1,2}\s+\w{3,9}\s+\d{4})').allMatches(normalizedText).toList();
            if (allDates.length >= 2) {
              subject.fromDate = allDates[0].group(1)?.trim();
              subject.toDate = allDates[1].group(1)?.trim();
              subject.duration = '${subject.fromDate} - ${subject.toDate}';
            } else if (allDates.length == 1) {
              subject.fromDate = allDates[0].group(1)?.trim();
              subject.duration = subject.fromDate;
            } else {
              // Last fallback: store raw text
              subject.duration = normalizedText
                  .replaceAll(RegExp(r'From\s*:?\s*', caseSensitive: false), '')
                  .replaceAll(RegExp(r'TO\s*:?\s*', caseSensitive: false), ' - ')
                  .trim();
            }
          }
        } else if (text.toLowerCase().contains('delivered')) {
          final match = RegExp(r'Delivered\s*:?\s*(\d+)', caseSensitive: false).firstMatch(text);
          subject.delivered = match?.group(1)?.trim() ?? text.replaceAll(RegExp(r'Delivered\s*:?\s*', caseSensitive: false), '').trim();
        } else if (text.toLowerCase().contains('attended') && !text.toLowerCase().contains('percentage')) {
          final match = RegExp(r'Attended\s*:?\s*(\d+)', caseSensitive: false).firstMatch(text);
          subject.attended = match?.group(1)?.trim() ?? text.replaceAll(RegExp(r'Attended\s*:?\s*', caseSensitive: false), '').trim();
        } else if (text.toLowerCase().contains('absent')) {
          final match = RegExp(r'Absent\s*:?\s*(\d+)', caseSensitive: false).firstMatch(text);
          subject.absent = match?.group(1)?.trim() ?? text.replaceAll(RegExp(r'Absent\s*:?\s*', caseSensitive: false), '').trim();
        } else if (text.toLowerCase().contains('dl') && text.toLowerCase().contains('ml') && !text.toLowerCase().contains('approved')) {
          subject.leaves = text.trim();
        } else if (text.toLowerCase().contains('total percentage') || text.toLowerCase().contains('percentage')) {
          final match = RegExp(r'(\d+\.?\d*)\s*%?', caseSensitive: false).firstMatch(text);
          subject.percentage = match?.group(1)?.trim();
        } else if (text.toLowerCase().contains('approved dl') || text.toLowerCase().contains('total approved dl')) {
          final match = RegExp(r'(\d+)\s*$').firstMatch(text);
          subject.totalApprovedDL = match?.group(1)?.trim() ?? text.replaceAll(RegExp(r'Total\s*Approved\s*DL\s*:?\s*', caseSensitive: false), '').trim();
        } else if (text.toLowerCase().contains('approved ml') || text.toLowerCase().contains('total approved ml')) {
          final match = RegExp(r'(\d+)\s*$').firstMatch(text);
          subject.totalApprovedML = match?.group(1)?.trim() ?? text.replaceAll(RegExp(r'Total\s*Approved\s*ML\s*:?\s*', caseSensitive: false), '').trim();
        }
      }
      return subject;
    }).toList();
  }

  String _getShortName(String name) {
    if (name.length <= 12) return name;
    
    // Normalize hyphens: remove spaces around them
    // "Subject - 1" -> "Subject-1"
    String cleanName = name.replaceAll(RegExp(r'\s*-\s*'), '-');
    
    String processSinglePart(String part) {
      part = part.trim();
      if (part.isEmpty) return '';
      if (part.toLowerCase() == 'and' || part == '&') return '';
      
      if (RegExp(r'^[0-9IVX]+$').hasMatch(part)) {
         return part;
      } else {
         String s = part[0].toUpperCase();
         final digits = RegExp(r'[0-9]+').allMatches(part).map((m) => m.group(0)).join();
         if (digits.isNotEmpty) s += digits;
         return s;
      }
    }

    final words = cleanName.split(' ');
    if (words.length <= 1 && !cleanName.contains('-')) {
       return name.length > 6 ? '${name.substring(0, 6)}..' : name;
    }
    
    String res = '';
    for (var word in words) {
      word = word.trim();
      if (word.isEmpty) continue;
      
      if (word.contains('-')) {
        List<String> parts = word.split('-');
        String hyphenated = parts.map((p) => processSinglePart(p)).where((s) => s.isNotEmpty).join('-');
        res += hyphenated;
      } else {
        res += processSinglePart(word);
      }
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Attendance: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: AppTheme.errorColor),
                        const SizedBox(height: 16),
                        Text(
                          'Error: $_errorMessage',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: isDark ? Colors.grey.shade400 : Colors.black54),
                        ),
                      ],
                    ),
                  )
                : _subjects.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined, size: 64, color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'No attendance records found',
                              style: GoogleFonts.inter(color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                            ),
                          ],
                        ),
                      )
                    : NestedScrollView(
                        headerSliverBuilder: (context, innerBoxIsScrolled) {
                          return [
                            SliverAppBar(
                              expandedHeight: 100,
                              floating: false,
                              pinned: true,
                              backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
                              surfaceTintColor: Colors.transparent,
                              leading: IconButton(
                                icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : Colors.black87),
                                onPressed: () => Navigator.pop(context),
                              ),
                              actions: [
                                IconButton(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    themeService.toggleTheme();
                                  },
                                  icon: Icon(
                                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                    color: isDark ? AppTheme.warningColor : AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                              flexibleSpace: FlexibleSpaceBar(
                                title: Row(
                                  children: [
                                    Text(
                                      'Attendance',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    if (_isRefreshing) ...[
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            isDark ? Colors.white70 : AppTheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                    ] else if (_cacheAge.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (_isOffline ? AppTheme.warningColor : AppTheme.successColor).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _isOffline ? 'Offline' : _cacheAge,
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: _isOffline ? AppTheme.warningColor : AppTheme.successColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                              ),
                            ),
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _StickyTabBarDelegate(
                                TabBar(
                                  controller: _tabController,
                                  isScrollable: true,
                                  labelColor: AppTheme.primaryColor,
                                  unselectedLabelColor: isDark ? Colors.grey.shade500 : Colors.grey,
                                  indicatorColor: AppTheme.primaryColor,
                                  indicatorWeight: 3,
                                  labelStyle: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  unselectedLabelStyle: GoogleFonts.inter(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                  tabs: _subjects.map((subject) {
                                    return Tab(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(_getShortName(subject.name ?? subject.code ?? 'Sub')),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ];
                        },
                        body: TabBarView(
                          controller: _tabController,
                          children: _subjects.asMap().entries.map((entry) {
                            return _buildSubjectPage(entry.value, entry.key);
                          }).toList(),
                        ),
                      ),
      ),
    );
  }

  Widget _buildSubjectPage(AttendanceSubject subject, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double percentage = double.tryParse(subject.percentage ?? '0') ?? 0.0;
    Color progressColor = percentage >= 75 
        ? AppTheme.successColor 
        : (percentage >= 60 ? AppTheme.warningColor : AppTheme.errorColor);

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppTheme.primaryColor,
      backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
        // Subject Header Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                subject.name ?? 'Unknown Subject',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              if (subject.code != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: progressColor.withOpacity(isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subject.code!,
                    style: GoogleFonts.sourceCodePro(
                      fontSize: 13,
                      color: progressColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              
              // Circular Progress
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppTheme.darkElevatedColor : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: progressColor.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: percentage / 100,
                      strokeWidth: 10,
                      backgroundColor: progressColor.withOpacity(isDark ? 0.2 : 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: progressColor,
                            ),
                          ),
                          Text(
                            percentage >= 75 ? 'Safe' : 'Low',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Stats Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem('Attended', subject.attended ?? '0', AppTheme.successColor, isDark),
                  Container(width: 1, height: 30, color: isDark ? Colors.grey.shade700 : Colors.grey.shade200),
                  _buildStatItem('Delivered', subject.delivered ?? '0', AppTheme.primaryColor, isDark),
                  Container(width: 1, height: 30, color: isDark ? Colors.grey.shade700 : Colors.grey.shade200),
                  _buildStatItem('Absent', subject.absent ?? '0', AppTheme.errorColor, isDark),
                ],
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.1, end: 0),
        
        const SizedBox(height: 20),
        
        // Details Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Details',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              if (subject.teacher != null && subject.teacher!.isNotEmpty)
                _buildDetailRow(Icons.person_outline, 'Teacher', subject.teacher, isDark),
              if (subject.fromDate != null && subject.toDate != null)
                _buildDurationRow(subject.fromDate!, subject.toDate!, isDark),
              if (subject.leaves != null)
                _buildDetailRow(Icons.info_outline, 'Leaves', subject.leaves, isDark),
              if (subject.totalApprovedDL != null)
                _buildDetailRow(Icons.verified_outlined, 'Approved DL', subject.totalApprovedDL, isDark),
              if (subject.totalApprovedML != null)
                _buildDetailRow(Icons.medical_services_outlined, 'Approved ML', subject.totalApprovedML, isDark),
            ],
          ),
        ).animate().fadeIn(delay: 100.ms).slideX(begin: 0.1, end: 0),
        
        const SizedBox(height: 20),
        
        // Prediction Card
        _buildPredictionCard(subject, index).animate().fadeIn(delay: 200.ms).slideX(begin: 0.1, end: 0),
        
        const SizedBox(height: 40),
      ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String? value, bool isDark) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkElevatedColor : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationRow(String fromDate, String toDate, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkElevatedColor : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.date_range_rounded, size: 18, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Duration',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 12, color: AppTheme.successColor),
                          const SizedBox(width: 4),
                          Text(
                            fromDate,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.successColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 12, color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stop_rounded, size: 12, color: AppTheme.errorColor),
                          const SizedBox(width: 4),
                          Text(
                            toDate,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.errorColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionCard(AttendanceSubject subject, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final delivered = int.tryParse(subject.delivered ?? '0') ?? 0;
    final attended = int.tryParse(subject.attended ?? '0') ?? 0;
    final dl = subject.dl;
    final ml = subject.ml; // Leave section ML - counted as attendance by backend
    final approvedML = int.tryParse(subject.totalApprovedML ?? '0') ?? 0;
    
    if (delivered == 0) return const SizedBox.shrink();
    
    // Get or initialize classes to miss for this subject
    final classesToMiss = _classesToMissMap[index] ?? 1;
    
    // Base attendance: attended + DL (EXCLUDE leave section ML, even though backend counts it)
    // We exclude it to calculate "real" attendance for the 65-75% logic
    final baseAttended = attended + dl;
    
    // Current attendance shown (what backend shows - includes leave section ML)
    final currentAttendance = (attended + dl + ml) / delivered * 100;
    
    // Calculate if missing X classes (without any ML)
    final newDelivered = delivered + classesToMiss;
    final ifMissWithoutML = baseAttended / newDelivered * 100;
    
    // Count only the minimum approved ML needed to reach 75%
    double predictedAttendance;
    int approvedMLUsed = 0;
    
    if (ifMissWithoutML >= 75) {
      // Above 75% without ML - no need to count approved ML
      predictedAttendance = ifMissWithoutML;
      approvedMLUsed = 0;
    } else if (ifMissWithoutML >= 65 && ifMissWithoutML < 75 && approvedML > 0) {
      // Between 65-75% - count only the minimum approved ML needed to reach 75%
      // Formula: (baseAttended + X) / newDelivered = 0.75
      // X = (0.75 * newDelivered) - baseAttended
      final mlNeededFor75 = (0.75 * newDelivered) - baseAttended;
      approvedMLUsed = mlNeededFor75.ceil().clamp(0, approvedML);
      
      predictedAttendance = (baseAttended + approvedMLUsed) / newDelivered * 100;
    } else {
      // Below 65% - don't count approved ML
      predictedAttendance = ifMissWithoutML;
      approvedMLUsed = 0;
    }
    
    // Determine status
    String status;
    Color statusColor;
    IconData statusIcon;
    String message;
    
    if (ifMissWithoutML < 65) {
      status = "Don't Miss!";
      statusColor = AppTheme.errorColor;
      statusIcon = Icons.block;
      message = "Your attendance (without ML) is below 65%";
    } else if (predictedAttendance >= 75) {
      status = "Good to Go";
      statusColor = AppTheme.successColor;
      statusIcon = Icons.check_circle;
      message = approvedMLUsed > 0 
          ? "Safe with $approvedMLUsed approved ML counted"
          : "You'll stay above 75%";
    } else {
      status = "Risky";
      statusColor = AppTheme.warningColor;
      statusIcon = Icons.warning;
      message = "Predicted: ${predictedAttendance.toStringAsFixed(2)}%";
    }
    
    return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark 
                ? statusColor.withOpacity(0.15)
                : statusColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Attendance Predictor',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCardColor : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildPredictionRow(
                  'Current Attendance',
                  currentAttendance,
                  currentAttendance >= 75 ? AppTheme.successColor : AppTheme.warningColor,
                  isDark,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Classes to miss:',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: classesToMiss > 1
                        ? () {
                            setState(() {
                              _classesToMissMap[index] = classesToMiss - 1;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: statusColor,
                  ),
                  Expanded(
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCardColor : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        '$classesToMiss',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: classesToMiss < 100
                        ? () {
                            setState(() {
                              _classesToMissMap[index] = classesToMiss + 1;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Predicted:',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${predictedAttendance.toStringAsFixed(2)}%',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: predictedAttendance >= 75 ? AppTheme.successColor : 
                                   (predictedAttendance >= 65 ? AppTheme.warningColor : AppTheme.errorColor),
                          ),
                        ),
                      ],
                    ),
                    if (approvedMLUsed > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.medical_services, size: 14, color: Colors.blue),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '$approvedMLUsed approved ML counted',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
  }

  Widget _buildPredictionRow(String label, double percentage, Color color, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          '${percentage.toStringAsFixed(2)}%',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class AttendanceSubject {
  String? name;
  String? code;
  String? teacher;
  String? duration;
  String? fromDate;
  String? toDate;
  String? delivered;
  String? attended;
  String? absent;
  String? leaves;
  String? percentage;
  String? totalApprovedDL;
  String? totalApprovedML;
  
  // Parsed leave values
  int get dl {
    if (leaves == null) return 0;
    final match = RegExp(r'DL\s*:\s*(\d+)').firstMatch(leaves!);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }
  
  int get ml {
    if (leaves == null) return 0;
    final match = RegExp(r'ML\s*:\s*(\d+)').firstMatch(leaves!);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }
}

// Sticky TabBar Delegate
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _StickyTabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
