import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../services/subjects_cache_service.dart';
import '../theme/app_theme.dart';

class SubjectsScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const SubjectsScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  final ApiService _apiService = ApiService();
  final SubjectsCacheService _cacheService = SubjectsCacheService();
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _cacheAge = '';
  bool _isOffline = false;
  List<Subject> _subjects = [];
  String _semesterTitle = 'Subjects';
  String? _currentSemester;
  String? _currentGroup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromCacheAndFetch();
    });
  }

  /// Load cached data first, then fetch from API if needed
  Future<void> _loadFromCacheAndFetch() async {
    await _cacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first
    final cached = await _cacheService.getCachedSubjects(userId, clientAbbr, sessionId);
    
    if (cached != null && cached.subjects.isNotEmpty) {
      // Load cached items immediately
      _subjects = cached.subjects.map((s) => Subject(
        name: s.name,
        specialization: s.specialization,
        code: s.code,
        type: s.type,
        group: s.group,
        credits: s.credits,
        isOptional: s.isOptional,
      )).toList();
      _semesterTitle = cached.semesterTitle;
      _currentSemester = cached.currentSemester;
      _currentGroup = cached.currentGroup;
      
      setState(() {
        _isLoading = false;
        _cacheAge = _cacheService.getCacheAgeString(userId, clientAbbr, sessionId);
        _isOffline = false;
      });
      
      debugPrint('📦 Loaded ${cached.subjects.length} subjects from cache');
      
      // Check for updates in background if cache is old
      if (!cached.isValid) {
        debugPrint('🔍 Cache is stale, refreshing in background...');
        _fetchSubjects(isBackgroundRefresh: true);
      }
    } else {
      // No cache, fetch from API
      debugPrint('📭 No cache found, fetching from API');
      _fetchSubjects();
    }
  }

  Future<void> _fetchSubjects({bool isBackgroundRefresh = false, bool isRefresh = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    
    // Store existing data in case of refresh failure
    final existingSubjects = List<Subject>.from(_subjects);
    final existingSemesterTitle = _semesterTitle;
    final existingCurrentSemester = _currentSemester;
    final existingCurrentGroup = _currentGroup;
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

      final htmlContent = await _apiService.getSubjects(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
      );

      _parseSubjects(htmlContent);

      // Save semester and group info if extracted
      if (_currentSemester != null || _currentGroup != null) {
        await _apiService.saveSemesterInfo(
          semester: _currentSemester,
          group: _currentGroup,
        );
      }
      
      // Cache the results
      if (_subjects.isNotEmpty) {
        await _cacheService.cacheSubjects(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          subjects: _subjects.map((s) => CachedSubject(
            name: s.name,
            specialization: s.specialization,
            code: s.code,
            type: s.type,
            group: s.group,
            credits: s.credits,
            isOptional: s.isOptional,
          )).toList(),
          semesterTitle: _semesterTitle,
          currentSemester: _currentSemester,
          currentGroup: _currentGroup,
        );
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _isOffline = false;
          _cacheAge = 'Just now';
        });
        
        if (isRefresh && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Subjects updated'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Subjects Screen - Error: $e');
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
            _semesterTitle = existingSemesterTitle;
            _currentSemester = existingCurrentSemester;
            _currentGroup = existingCurrentGroup;
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
          final cached = await _cacheService.getCachedSubjects(userId, clientAbbr, sessionId);
          if (cached != null && cached.subjects.isNotEmpty) {
            _subjects = cached.subjects.map((s) => Subject(
              name: s.name,
              specialization: s.specialization,
              code: s.code,
              type: s.type,
              group: s.group,
              credits: s.credits,
              isOptional: s.isOptional,
            )).toList();
            _semesterTitle = cached.semesterTitle;
            _currentSemester = cached.currentSemester;
            _currentGroup = cached.currentGroup;
            
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
              _errorMessage = e.toString().replaceAll('Exception: ', '');
              _isLoading = false;
              _isRefreshing = false;
            });
          }
        }
      }
    }
  }
  
  /// Handle pull to refresh
  Future<void> _handleRefresh() async {
    await _fetchSubjects(isRefresh: true);
  }

  void _parseSubjects(String htmlContent) {
    // Clean the HTML
    String cleanHtml = htmlContent.replaceAll(r'\"', '"').replaceAll(r'\/', '/');
    if (cleanHtml.startsWith('"') && cleanHtml.endsWith('"')) {
      cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
    }

    final document = html_parser.parse(cleanHtml);

    // Get heading/semester info - e.g., "Subject(s) Details (5 SEM)"
    final heading = document.querySelector('.heading');
    if (heading != null) {
      _semesterTitle = heading.text.trim();
      
      // Extract semester number from heading
      _currentSemester = ApiService.parseSemesterFromText(_semesterTitle);
      debugPrint('Extracted semester from subjects: $_currentSemester');
    }

    // Parse each subject wrap
    final subjectWraps = document.querySelectorAll('.ui-subject-wrap');
    List<Subject> subjects = [];

    for (var wrap in subjectWraps) {
      final details = wrap.querySelectorAll('.ui-subject-detail');
      
      String? name;
      String? specialization;
      String? code;
      String? type;
      String? group;
      String? credits;
      bool isOptional = false;

      for (var detail in details) {
        final text = detail.text.trim();
        final html = detail.innerHtml;
        
        if (text.contains('Subject Name:')) {
          name = text.replaceFirst('Subject Name:', '').trim();
        } else if (text.contains('Specialization:')) {
          specialization = text.replaceFirst('Specialization:', '').trim();
        } else if (text.contains('Subject Code:')) {
          code = text.replaceFirst('Subject Code:', '').trim();
          // Check if optional
          if (html.toLowerCase().contains('optional')) {
            isOptional = true;
          }
        } else if (text.contains('Subject Type:')) {
          type = text.replaceFirst('Subject Type:', '').trim();
        } else if (text.contains('Group:')) {
          group = text.replaceFirst('Group:', '').trim();
        } else if (text.contains('Credits:')) {
          credits = text.replaceFirst('Credits:', '').trim();
          if (credits == '----') credits = null;
        }
      }

      if (name != null) {
        subjects.add(Subject(
          name: name,
          specialization: specialization,
          code: code,
          type: type,
          group: group,
          credits: credits,
          isOptional: isOptional,
        ));
        
        // Extract group from first subject (e.g., "CSE-G07")
        if (_currentGroup == null && group != null && group.isNotEmpty) {
          _currentGroup = group;
          debugPrint('Extracted group from subjects: $_currentGroup');
        }
      }
    }

    setState(() {
      _subjects = subjects;
    });
  }

  Color _getTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'theory':
        return AppTheme.primaryColor;
      case 'practical':
        return AppTheme.successColor;
      case 'universal':
        return AppTheme.warningColor;
      default:
        return AppTheme.secondaryColor;
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'theory':
        return Icons.menu_book_rounded;
      case 'practical':
        return Icons.computer_rounded;
      case 'universal':
        return Icons.public_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(
              color: isDark ? Colors.white : AppTheme.primaryColor,
            ))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: isDark ? Colors.red.shade400 : Colors.red.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading subjects',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _errorMessage = null;
                            });
                            _fetchSubjects();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: AppTheme.primaryColor,
                  backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    SliverAppBar.large(
                      expandedHeight: 120,
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
                      actions: [
                        if (_isRefreshing)
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDark ? Colors.white70 : AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else if (_cacheAge.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (_isOffline ? AppTheme.warningColor : AppTheme.successColor).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _isOffline ? 'Offline' : _cacheAge,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _isOffline ? AppTheme.warningColor : AppTheme.successColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        title: Text(
                          _semesterTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 80),
                      ),
                    ),
                    // Summary Card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: _buildSummaryCard(isDark)
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.2),
                      ),
                    ),
                    // Subjects List
                    SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildSubjectCard(_subjects[index], index, isDark);
                          },
                          childCount: _subjects.length,
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCard(bool isDark) {
    // Count subjects by type
    int theoryCount = _subjects.where((s) => s.type?.toLowerCase() == 'theory').length;
    int practicalCount = _subjects.where((s) => s.type?.toLowerCase() == 'practical').length;
    int universalCount = _subjects.where((s) => s.type?.toLowerCase() == 'universal').length;
    int optionalCount = _subjects.where((s) => s.isOptional).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Total Subjects',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (_currentSemester != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Sem $_currentSemester',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${_subjects.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem('Theory', theoryCount, Icons.menu_book_rounded),
              _buildSummaryItem('Practical', practicalCount, Icons.computer_rounded),
              _buildSummaryItem('Universal', universalCount, Icons.public_rounded),
              if (optionalCount > 0)
                _buildSummaryItem('Optional', optionalCount, Icons.star_outline_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectCard(Subject subject, int index, bool isDark) {
    final typeColor = _getTypeColor(subject.type);
    final typeIcon = _getTypeIcon(subject.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with type indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: typeColor.withOpacity(isDark ? 0.15 : 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subject.name ?? 'Unknown Subject',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (subject.isOptional)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(isDark ? 0.2 : 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Optional',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subject.code ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: typeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (subject.specialization != null)
                  _buildDetailRow(Icons.category_rounded, 'Specialization', subject.specialization!, isDark),
                _buildDetailRow(Icons.bookmark_rounded, 'Type', subject.type ?? 'N/A', isDark),
                _buildDetailRow(Icons.group_rounded, 'Group', subject.group ?? 'N/A', isDark),
                if (subject.credits != null)
                  _buildDetailRow(Icons.stars_rounded, 'Credits', subject.credits!, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class Subject {
  final String? name;
  final String? specialization;
  final String? code;
  final String? type;
  final String? group;
  final String? credits;
  final bool isOptional;

  Subject({
    this.name,
    this.specialization,
    this.code,
    this.type,
    this.group,
    this.credits,
    this.isOptional = false,
  });
}
