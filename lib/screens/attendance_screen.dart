import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/attendance_cache_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' show themeService;

// Data models for Attendance Register
class SubjectAttendanceRegister {
  final String name;
  final String code;
  final List<LectureInfo> lectures;
  final List<String> attendanceData;
  final String total;
  final String percentage;

  SubjectAttendanceRegister({
    required this.name,
    required this.code,
    required this.lectures,
    required this.attendanceData,
    required this.total,
    required this.percentage,
  });
}

class LectureInfo {
  final String number;
  final String date;
  final String period;

  LectureInfo({
    required this.number,
    required this.date,
    required this.period,
  });
}

/// Represents a single lecture on a specific day for calendar grouping
class _DayLecture {
  final String lectureNumber;
  final String period;
  final String status;
  final String date;

  _DayLecture({
    required this.lectureNumber,
    required this.period,
    required this.status,
    required this.date,
  });
}

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
  
  // Attendance Register data
  List<SubjectAttendanceRegister> _registerSubjects = [];
  bool _isLoadingRegister = false;
  bool _registerLoaded = false;

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

  // ============ ATTENDANCE REGISTER METHODS ============
  
  /// Fetch detailed attendance register data
  Future<void> _fetchAttendanceRegister() async {
    if (_registerLoaded) return; // Already loaded
    
    setState(() {
      _isLoadingRegister = true;
    });

    try {
      final baseUrl = widget.clientDetails['baseUrl'] as String? ?? '';
      final clientAbbr = widget.clientDetails['clientAbbr'] as String? ?? 
                         widget.clientDetails['client_abbr'] as String? ?? '';
      final studentId = widget.userData['studentId']?.toString() ?? 
                        widget.userData['userId']?.toString() ?? '';
      final sessionId = widget.userData['sessionId']?.toString() ?? '18';
      final userId = widget.userData['userId']?.toString() ?? '';
      final roleId = widget.userData['roleId']?.toString() ?? '4';
      final apiKey = widget.userData['apiKey']?.toString() ?? '';

      if (baseUrl.isEmpty || clientAbbr.isEmpty || studentId.isEmpty) {
        throw Exception('Missing required details');
      }

      // Step 1: Initialize attendance session
      try {
        await _apiService.showAttendance(
          baseUrl: baseUrl,
          clientAbbr: clientAbbr,
          userId: userId,
          sessionId: sessionId,
          apiKey: apiKey,
          roleId: roleId,
          prevNext: '0',
          month: '',
        );
      } catch (e) {
        debugPrint('⚠️ showAttendance failed: $e');
      }

      // Step 2: Fetch the attendance register
      final response = await _apiService.getAttendanceRegister(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        studentId: studentId,
        sessionId: sessionId,
      );

      _parseAttendanceRegister(response);

      setState(() {
        _isLoadingRegister = false;
        _registerLoaded = true;
      });
    } catch (e) {
      debugPrint('❌ Error fetching attendance register: $e');
      setState(() {
        _isLoadingRegister = false;
      });
    }
  }

  void _parseAttendanceRegister(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final table = document.querySelector('table');
    if (table == null) return;

    final subjects = <SubjectAttendanceRegister>[];
    final theadElements = table.querySelectorAll('thead');
    final tbodyElements = table.querySelectorAll('tbody');

    for (int i = 0; i < theadElements.length && i < tbodyElements.length; i++) {
      try {
        final thead = theadElements[i];
        final tbody = tbodyElements[i];
        final theadRows = thead.querySelectorAll('tr');
        
        if (theadRows.length < 2) continue;

        final subjectRow = theadRows[1];
        final allHeaders = subjectRow.querySelectorAll('th');
        if (allHeaders.isEmpty) continue;

        // Parse subject name and code using innerHtml for <br> tags
        final subjectHtml = allHeaders[0].innerHtml;
        final subjectParts = subjectHtml.split(RegExp(r'<br\s*/?>', caseSensitive: false))
            .map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        
        String subjectName = subjectParts.isNotEmpty ? subjectParts[0] : 'Unknown';
        String subjectCode = subjectParts.length > 1 
            ? subjectParts[1].replaceAll('(', '').replaceAll(')', '').trim() 
            : '';

        // Parse lecture headers
        final lectures = <LectureInfo>[];
        for (int j = 1; j < allHeaders.length - 2; j++) {
          final headerHtml = allHeaders[j].innerHtml;
          final parts = headerHtml.split(RegExp(r'<br\s*/?>', caseSensitive: false))
              .map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          
          if (parts.length >= 3) {
            lectures.add(LectureInfo(
              number: parts[0],
              date: parts[1],
              period: parts[2],
            ));
          }
        }

        // Parse attendance data from tbody
        final dataRow = tbody.querySelector('tr');
        if (dataRow == null) continue;

        final cells = dataRow.querySelectorAll('td');
        final attendanceData = <String>[];
        
        for (int j = 1; j < cells.length - 2; j++) {
          attendanceData.add(cells[j].text.trim());
        }

        final totalCell = cells.length >= 2 ? cells[cells.length - 2].text.trim() : '0/0';
        final percentCell = cells.length >= 1 ? cells[cells.length - 1].text.trim() : '0%';

        subjects.add(SubjectAttendanceRegister(
          name: subjectName,
          code: subjectCode,
          lectures: lectures,
          attendanceData: attendanceData,
          total: totalCell,
          percentage: percentCell,
        ));
      } catch (e) {
        debugPrint('❌ Error parsing register subject $i: $e');
      }
    }

    _registerSubjects = subjects;
    debugPrint('✅ Parsed ${subjects.length} subjects from register');
  }

  /// Find register data for a specific subject
  SubjectAttendanceRegister? _findRegisterForSubject(AttendanceSubject subject) {
    if (_registerSubjects.isEmpty) return null;
    
    // Try to match by code first
    if (subject.code != null) {
      final match = _registerSubjects.where((r) => 
        r.code.toLowerCase() == subject.code!.toLowerCase() ||
        r.name.toLowerCase().contains(subject.code!.toLowerCase())
      ).firstOrNull;
      if (match != null) return match;
    }
    
    // Try to match by name
    if (subject.name != null) {
      final match = _registerSubjects.where((r) {
        final rName = r.name.toLowerCase();
        final sName = subject.name!.toLowerCase();
        return rName.contains(sName) || sName.contains(rName);
      }).firstOrNull;
      if (match != null) return match;
    }
    
    return null;
  }

  /// Show attendance register bottom sheet for a subject
  void _showAttendanceRegisterSheet(AttendanceSubject subject) {
    HapticFeedback.mediumImpact();
    
    // Show sheet immediately (with loading state if needed)
    _displayRegisterSheet(subject);
    
    // Fetch register if not loaded
    if (!_registerLoaded) {
      _fetchAttendanceRegister().then((_) {
        if (mounted) {
          // Close and reopen with data
          Navigator.pop(context);
          _displayRegisterSheet(subject);
        }
      });
    }
  }

  void _displayRegisterSheet(AttendanceSubject subject) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final registerData = _findRegisterForSubject(subject);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.calendar_month_rounded,
                            color: AppTheme.primaryColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Attendance Register',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              Text(
                                subject.name ?? 'Subject',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close_rounded,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Legend
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildLegendChip('P', 'Present', AppTheme.successColor, isDark),
                          const SizedBox(width: 8),
                          _buildLegendChip('A', 'Absent', AppTheme.errorColor, isDark),
                          const SizedBox(width: 8),
                          _buildLegendChip('DL', 'Duty Leave', Colors.blue, isDark),
                          const SizedBox(width: 8),
                          _buildLegendChip('ML', 'Medical Leave', Colors.orange, isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Divider(height: 1, color: isDark ? Colors.grey[800] : Colors.grey[200]),
              
              // Content
              Expanded(
                child: _isLoadingRegister
                    ? _buildLoadingIndicator(isDark)
                    : registerData == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.calendar_today_outlined, 
                                    size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text(
                                  'No register data found',
                                  style: GoogleFonts.inter(color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : _buildRegisterContent(registerData, scrollController, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendChip(String code, String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                code,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading attendance register...',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        ],
      ),
    ).animate(onPlay: (controller) => controller.repeat())
      .shimmer(duration: 1500.ms, color: AppTheme.primaryColor.withOpacity(0.3));
  }

  Widget _buildRegisterContent(SubjectAttendanceRegister register, 
      ScrollController scrollController, bool isDark) {
    // Group lectures by date for calendar view
    final dateAttendanceMap = _groupLecturesByDate(register);
    final monthsData = _organizeByMonths(dateAttendanceMap);
    
    final hasLectures = register.lectures.isNotEmpty;
    final itemCount = hasLectures 
        ? (register.lectures.length < register.attendanceData.length 
            ? register.lectures.length 
            : register.attendanceData.length)
        : register.attendanceData.length;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor.withOpacity(isDark ? 0.2 : 0.1),
                AppTheme.primaryColor.withOpacity(isDark ? 0.1 : 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSummaryItem('Total Classes', '$itemCount', Icons.school_rounded, isDark),
              Container(
                width: 1,
                height: 40,
                color: AppTheme.primaryColor.withOpacity(0.2),
              ),
              _buildSummaryItem('Attended', register.total.split('/').first, 
                  Icons.check_circle_outline, isDark),
              Container(
                width: 1,
                height: 40,
                color: AppTheme.primaryColor.withOpacity(0.2),
              ),
              _buildSummaryItem('Percentage', register.percentage, 
                  Icons.percent_rounded, isDark),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Calendar view by months
        ...monthsData.entries.map((monthEntry) => 
          _buildMonthCalendar(monthEntry.key, monthEntry.value, isDark)
        ),
        
        const SizedBox(height: 24),
      ],
    );
  }

  /// Groups lectures by date, stacking multiple lectures on the same day
  Map<String, List<_DayLecture>> _groupLecturesByDate(SubjectAttendanceRegister register) {
    final Map<String, List<_DayLecture>> dateMap = {};
    
    final hasLectures = register.lectures.isNotEmpty;
    final itemCount = hasLectures 
        ? (register.lectures.length < register.attendanceData.length 
            ? register.lectures.length 
            : register.attendanceData.length)
        : register.attendanceData.length;

    for (int i = 0; i < itemCount; i++) {
      final lecture = hasLectures 
          ? register.lectures[i] 
          : LectureInfo(number: '${i + 1}', date: '', period: '');
      final status = register.attendanceData[i];
      
      // Parse date - format is typically "DD-MM" or "DD-MM-YY"
      String dateKey = lecture.date.isNotEmpty ? lecture.date : 'unknown';
      
      if (!dateMap.containsKey(dateKey)) {
        dateMap[dateKey] = [];
      }
      
      dateMap[dateKey]!.add(_DayLecture(
        lectureNumber: lecture.number,
        period: lecture.period,
        status: status,
        date: lecture.date,
      ));
    }
    
    return dateMap;
  }

  /// Organize dates by month for calendar display
  Map<String, Map<int, List<_DayLecture>>> _organizeByMonths(
      Map<String, List<_DayLecture>> dateAttendanceMap) {
    final Map<String, Map<int, List<_DayLecture>>> monthsData = {};
    final currentYear = DateTime.now().year;
    
    for (final entry in dateAttendanceMap.entries) {
      final dateStr = entry.key;
      final lectures = entry.value;
      
      if (dateStr == 'unknown') continue;
      
      // Parse "DD-MM" or "DD-MM-YY" format
      final parts = dateStr.split('-');
      if (parts.length >= 2) {
        final day = int.tryParse(parts[0]) ?? 1;
        final month = int.tryParse(parts[1]) ?? 1;
        final year = parts.length > 2 ? (int.tryParse(parts[2]) ?? currentYear % 100) + 2000 : currentYear;
        
        final monthKey = _getMonthName(month, year);
        
        if (!monthsData.containsKey(monthKey)) {
          monthsData[monthKey] = {};
        }
        
        monthsData[monthKey]![day] = lectures;
      }
    }
    
    return monthsData;
  }

  String _getMonthName(int month, int year) {
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[month.clamp(1, 12)]} $year';
  }

  Widget _buildMonthCalendar(String monthName, Map<int, List<_DayLecture>> daysData, bool isDark) {
    // Extract month and year from monthName
    final parts = monthName.split(' ');
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
                        'July', 'August', 'September', 'October', 'November', 'December'];
    final monthIndex = monthNames.indexOf(parts[0]) + 1;
    final year = int.tryParse(parts[1]) ?? DateTime.now().year;
    
    final firstDayOfMonth = DateTime(year, monthIndex, 1);
    final daysInMonth = DateTime(year, monthIndex + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday; // 1 = Monday, 7 = Sunday
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900]?.withOpacity(0.5) : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                monthName,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${daysData.length} days',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) => 
              SizedBox(
                width: 36,
                child: Center(
                  child: Text(
                    day,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ).toList(),
          ),
          
          const SizedBox(height: 8),
          
          // Calendar grid
          _buildCalendarGrid(daysInMonth, startWeekday, daysData, isDark),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(int daysInMonth, int startWeekday, 
      Map<int, List<_DayLecture>> daysData, bool isDark) {
    final List<Widget> rows = [];
    int dayCounter = 1;
    
    // Calculate number of weeks needed
    final totalCells = (startWeekday - 1) + daysInMonth;
    final numRows = (totalCells / 7).ceil();
    
    for (int row = 0; row < numRows; row++) {
      final List<Widget> cells = [];
      
      for (int col = 0; col < 7; col++) {
        final cellIndex = row * 7 + col;
        
        if (cellIndex < startWeekday - 1 || dayCounter > daysInMonth) {
          // Empty cell
          cells.add(const SizedBox(width: 36, height: 44));
        } else {
          final day = dayCounter;
          final lectures = daysData[day];
          cells.add(_buildCalendarDay(day, lectures, isDark));
          dayCounter++;
        }
      }
      
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: cells,
          ),
        ),
      );
    }
    
    return Column(children: rows);
  }

  Widget _buildCalendarDay(int day, List<_DayLecture>? lectures, bool isDark) {
    final hasLectures = lectures != null && lectures.isNotEmpty;
    
    // Determine dominant status for the day
    Color? bgColor;
    Color? textColor;
    
    if (hasLectures) {
      final statuses = lectures.map((l) => _getStatusType(l.status)).toList();
      
      // Priority: if any absent, show concern; if all present, show success
      if (statuses.every((s) => s == 'present')) {
        bgColor = AppTheme.successColor;
        textColor = Colors.white;
      } else if (statuses.every((s) => s == 'absent')) {
        bgColor = AppTheme.errorColor;
        textColor = Colors.white;
      } else if (statuses.every((s) => s == 'duty' || s == 'medical')) {
        bgColor = statuses.first == 'duty' ? Colors.blue : Colors.orange;
        textColor = Colors.white;
      } else if (statuses.contains('absent')) {
        // Mixed with some absent - show warning style
        bgColor = Colors.orange;
        textColor = Colors.white;
      } else {
        bgColor = AppTheme.successColor;
        textColor = Colors.white;
      }
    }

    return GestureDetector(
      onTap: hasLectures ? () => _showDayDetails(day, lectures, isDark) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 44,
        decoration: BoxDecoration(
          color: bgColor?.withOpacity(isDark ? 0.8 : 0.9),
          borderRadius: BorderRadius.circular(10),
          border: hasLectures ? null : Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: hasLectures ? [
            BoxShadow(
              color: bgColor!.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: hasLectures ? FontWeight.w700 : FontWeight.w500,
              color: textColor ?? (isDark ? Colors.grey[600] : Colors.grey[400]),
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusType(String status) {
    if (status == 'X') return 'absent';
    if (status == 'DL') return 'duty';
    if (status == 'ML') return 'medical';
    if (int.tryParse(status) != null) return 'present';
    return 'unknown';
  }

  void _showDayDetails(int day, List<_DayLecture> lectures, bool isDark) {
    HapticFeedback.lightImpact();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.primaryColor.withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lectures.first.date.isNotEmpty 
                              ? _formatDateForDisplay(lectures.first.date)
                              : 'Day $day',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          '${lectures.length} lecture${lectures.length > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            Divider(height: 1, color: isDark ? Colors.grey[800] : Colors.grey[200]),
            
            // Lectures list
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: lectures.asMap().entries.map((entry) {
                    final index = entry.key;
                    final lecture = entry.value;
                    return _buildLectureDetailCard(lecture, index, isDark);
                  }).toList(),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
          ],
          ),
        ),
      ),
    );
  }

  String _formatDateForDisplay(String date) {
    final parts = date.split('-');
    if (parts.length >= 2) {
      final day = parts[0];
      final month = int.tryParse(parts[1]) ?? 1;
      const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '$day ${monthNames[month.clamp(1, 12)]}';
    }
    return date;
  }

  Widget _buildLectureDetailCard(_DayLecture lecture, int index, bool isDark) {
    final statusType = _getStatusType(lecture.status);
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    
    switch (statusType) {
      case 'present':
        statusColor = AppTheme.successColor;
        statusLabel = 'Present';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'absent':
        statusColor = AppTheme.errorColor;
        statusLabel = 'Absent';
        statusIcon = Icons.cancel_rounded;
        break;
      case 'duty':
        statusColor = Colors.blue;
        statusLabel = 'Duty Leave';
        statusIcon = Icons.work_rounded;
        break;
      case 'medical':
        statusColor = Colors.orange;
        statusLabel = 'Medical Leave';
        statusIcon = Icons.medical_services_rounded;
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = 'Unknown';
        statusIcon = Icons.help_rounded;
    }

    return Container(
      margin: EdgeInsets.only(bottom: index < 10 ? 10 : 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(isDark ? 0.3 : 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lecture ${lecture.lectureNumber}',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (lecture.period.isNotEmpty) ...[
                      Icon(Icons.schedule_rounded, 
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        'Period ${lecture.period}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, bool isDark) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
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
        
        // View Attendance Register Button
        InkWell(
          onTap: () => _showAttendanceRegisterSheet(subject),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7C3AED).withOpacity(isDark ? 0.25 : 0.15),
                  const Color(0xFF7C3AED).withOpacity(isDark ? 0.15 : 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF7C3AED).withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(isDark ? 0.3 : 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Color(0xFF7C3AED),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View Attendance Register',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'See class-wise attendance details',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: 150.ms).slideX(begin: 0.1, end: 0),
        
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
                            HapticFeedback.lightImpact();
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
                            HapticFeedback.lightImpact();
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
