import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:html/parser.dart' as html_parser;
import '../services/api_service.dart';
import '../services/feed_cache_service.dart';
import '../services/timetable_cache_service.dart';
import '../services/attendance_cache_service.dart';
import '../services/subjects_cache_service.dart';
import '../services/update_service.dart';
import '../services/shorebird_service.dart';
import '../services/whats_new_service.dart';
import '../theme/app_theme.dart';
import '../utils/string_extensions.dart';
import '../utils/responsive_helper.dart';
import '../widgets/update_dialog.dart';
import '../widgets/whats_new_dialog.dart';
import '../main.dart' show themeService;
import 'feed_screen.dart';
import 'feed_detail_screen.dart';
import 'attendance_screen.dart';
import 'timetable_screen.dart';
import 'profile_screen.dart';
import 'subjects_screen.dart';
import 'medical_leave_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const HomeScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  final ApiService _apiService = ApiService();
  final FeedCacheService _feedCacheService = FeedCacheService();
  final TimetableCacheService _timetableCacheService = TimetableCacheService();
  final AttendanceCacheService _attendanceCacheService = AttendanceCacheService();
  final SubjectsCacheService _subjectsCacheService = SubjectsCacheService();
  final UpdateService _updateService = UpdateService();
  final ShorebirdService _shorebirdService = ShorebirdService();
  final WhatsNewService _whatsNewService = WhatsNewService();
  late PageController _pageController;
  late PageController _classPageController;
  int _lastClassPage = 0; // Track for haptic feedback
  
  // Data holders
  List<dynamic> _feedItems = [];
  Map<String, List<Map<String, String>>> _timetable = {};
  List<AttendanceSubject> _subjects = [];
  List<Subject> _subjectDetails = []; // Subject details from subjects screen
  
  // Loading states
  bool _isLoadingFeed = true;
  bool _isLoadingTimetable = true;
  bool _isLoadingSubjects = true;
  
  // Cache state
  
  String? _userName;
  String? _sessionPeriod; // e.g. "Jan - Jun" or "Jul - Dec"

  @override
  bool get wantKeepAlive => true; // Keep state alive for smooth transitions

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: 0,
      viewportFraction: 1.0, // Full page view
    );
    _classPageController = PageController(viewportFraction: 0.92);
    _fetchAllData();
    
    // Check for Shorebird code push updates (silent, in background) - only on mobile
    if (!kIsWeb) {
      _shorebirdService.checkAndDownloadInBackground();
    }
    
    // Check for app updates after a short delay - only on mobile (for APK updates)
    if (!kIsWeb) {
      Future.delayed(const Duration(seconds: 2), () {
        _checkForUpdates();
      });
    }
    
    // Check for What's New dialog (show after patch updates) - works on both platforms
    Future.delayed(const Duration(seconds: 1), () {
      _checkForWhatsNew();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _classPageController.dispose();
    super.dispose();
  }

  /// Check if we should show What's New dialog
  Future<void> _checkForWhatsNew() async {
    if (!mounted) return;
    
    try {
      final shouldShow = await _whatsNewService.shouldShowWhatsNew();
      
      if (shouldShow && mounted) {
        debugPrint('📰 Showing What\'s New dialog');
        await WhatsNewDialog.show(context);
      }
    } catch (e) {
      debugPrint('❌ Error checking What\'s New: $e');
    }
  }

  /// Check for app updates from GitHub releases
  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    
    try {
      // Initialize the update service to get current version
      await _updateService.init();
      
      final update = await _updateService.checkForUpdate();
      
      if (update != null && mounted) {
        // Show the update dialog
        await UpdateDialog.show(
          context,
          update,
          onSkip: () {
            debugPrint('📦 User skipped update ${update.version}');
          },
          onDismiss: () {
            debugPrint('📦 User dismissed update dialog');
          },
        );
      }
    } catch (e) {
      debugPrint('❌ Error checking for updates: $e');
    }
  }

  Future<void> _fetchAllData() async {
    _userName = widget.userData['name'] ?? 'Student';
    
    // Ensure cookies are loaded before making API calls
    await _apiService.ensureCookiesLoaded();
    
    // First load cached semester info for instant display
    _loadSemesterInfo();
    
    // Check if Shorebird patch changed - invalidate all caches if so
    bool shouldForceRefresh = false;
    if (!kIsWeb) {
      shouldForceRefresh = await _shorebirdService.hasPatchChanged();
      if (shouldForceRefresh) {
        debugPrint('🔄 Patch update detected! Invalidating all caches...');
        await _invalidateAllCaches();
      }
    }
    
    // Fetch all data in parallel for faster loading
    await Future.wait([
      _fetchFeed(forceRefresh: shouldForceRefresh),
      _fetchTimetable(forceRefresh: shouldForceRefresh),
      _fetchAttendance(forceRefresh: shouldForceRefresh),
      _fetchSubjectsData(), // Fetch subjects to get group
      _fetchSubjectDetails(forceRefresh: shouldForceRefresh),
    ]);
    
    // Load session period (e.g. "Jan - Jun")
    _loadSessionPeriod();
  }

  /// Invalidate all caches for the current user (after patch update)
  Future<void> _invalidateAllCaches() async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    await Future.wait([
      _timetableCacheService.init().then((_) =>
        _timetableCacheService.clearCache(userId, clientAbbr, sessionId)),
      _attendanceCacheService.init().then((_) =>
        _attendanceCacheService.clearCache(userId, clientAbbr, sessionId)),
      _subjectsCacheService.init().then((_) =>
        _subjectsCacheService.clearCache(userId, clientAbbr, sessionId)),
      _feedCacheService.clearCache(userId, clientAbbr, sessionId),
    ]);
    
    debugPrint('🗑️ All caches invalidated for user $userId');
  }

  Future<void> _loadSemesterInfo() async {
    // No longer needed - we only use session period now
  }
  
  void _loadSessionPeriod() {
    // Extract session period from session name (e.g. "Jul - Dec 2024" -> "Jul - Dec")
    String? sessionName = widget.userData['sessionName'];
    
    if (sessionName != null && sessionName.isNotEmpty) {
      // Try to extract month range (e.g. "Jan - Jun" or "Jul - Dec")
      // Common formats: "Jul - Dec 2024", "Jan 2024 - Jun 2024", "2024-25"
      final parts = sessionName.split(' ');
      
      if (parts.length >= 3 && parts[1] == '-') {
        // Format: "Jul - Dec 2024" or "Jan - Jun 2025"
        _sessionPeriod = '${parts[0]} - ${parts[2]}';
      } else if (sessionName.contains('-')) {
        // Format: "2024-25" or other
        _sessionPeriod = sessionName;
      } else {
        _sessionPeriod = sessionName;
      }
      
      debugPrint('📅 Session Period: $_sessionPeriod');
      
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _fetchSubjectsData() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final roleId = widget.userData['roleId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final htmlContent = await _apiService.getSubjects(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
      );

      // Parse group from subjects (semester is now from session period)
      _parseSubjectsForInfo(htmlContent);
    } catch (e) {
      debugPrint('Error fetching subjects: $e');
    }
  }



  void _parseSubjectsForInfo(String htmlContent) {
    // Clean the HTML
    String cleanHtml = htmlContent.replaceAll(r'\"', '"').replaceAll(r'\/', '/');
    if (cleanHtml.startsWith('"') && cleanHtml.endsWith('"')) {
      cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
    }

    final document = html_parser.parse(cleanHtml);

    // We no longer parse semester or group from subjects
  }

  Future<void> _fetchSubjectDetails({bool forceRefresh = false}) async {
    await _subjectsCacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first
    final cached = await _subjectsCacheService.getCachedSubjects(userId, clientAbbr, sessionId);
    
    if (cached != null && cached.subjects.isNotEmpty) {
      if (mounted) {
        setState(() {
          _subjectDetails = cached.subjects.map((s) => Subject(
            name: s.name,
            specialization: s.specialization,
            code: s.code,
            type: s.type,
            group: s.group,
            credits: s.credits,
            isOptional: s.isOptional,
          )).toList();
          _isLoadingSubjects = false;
        });
      }
      
      // If cache is valid and not forced, skip API call
      if (!forceRefresh && cached.isValid) {
        debugPrint('📦 Using valid subjects cache');
        return;
      }
      debugPrint(forceRefresh ? '🔄 Forcing subjects refresh...' : '🔍 Subjects cache is stale, refreshing in background...');
    }
    
    // Fetch from API
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final roleId = widget.userData['roleId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final htmlContent = await _apiService.getSubjects(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
      );

      _parseSubjectDetails(htmlContent);
      
      // Cache the subjects
      await _subjectsCacheService.cacheSubjects(
        userId: userId,
        clientAbbr: clientAbbr,
        sessionId: sessionId,
        semesterTitle: 'Subjects',
        subjects: _subjectDetails.map((s) => CachedSubject(
          name: s.name,
          specialization: s.specialization,
          code: s.code,
          type: s.type,
          group: s.group,
          credits: s.credits,
          isOptional: s.isOptional,
        )).toList(),
      );
      
      // OPTIMIZATION: Update timetable cache with subject names found in subjects section
      // This prevents TimetableScreen from needing to fetch names separately
      if (_subjectDetails.isNotEmpty) {
        _updateTimetableSubjectNames();
      }
      
      if (mounted) {
        setState(() {
        });
      }
    } catch (e) {
      debugPrint('Error fetching subject details: $e');
      final isNetworkError = e.toString().toLowerCase().contains('socket') ||
                             e.toString().toLowerCase().contains('connection') ||
                             e.toString().toLowerCase().contains('network');

      if (mounted) {
        setState(() {
          _isLoadingSubjects = false;
        });
        
        if (_subjectDetails.isEmpty && isNetworkError) {
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

  void _parseSubjectDetails(String htmlContent) {
    // Clean the HTML
    String cleanHtml = htmlContent.replaceAll(r'\"', '"').replaceAll(r'\/', '/');
    if (cleanHtml.startsWith('"') && cleanHtml.endsWith('"')) {
      cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
    }

    final document = html_parser.parse(cleanHtml);
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
      }
    }

    if (mounted) {
      setState(() {
        _subjectDetails = subjects;
        _isLoadingSubjects = false;
      });
    }
  }

  Future<void> _fetchFeed({bool forceRefresh = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first
    final cached = await _feedCacheService.getCachedFeed(userId, clientAbbr, sessionId);
    bool hasCachedData = false;
    
    if (cached != null && cached.items.isNotEmpty) {
      hasCachedData = true;
      if (mounted) {
        setState(() {
          _feedItems = cached.items;
          _isLoadingFeed = false;
        });
      }
      
      // If not forced, check if we should refresh in background
      if (!forceRefresh) {
        final shouldCheck = await _feedCacheService.shouldCheckForNewItems(userId, clientAbbr, sessionId);
        if (!shouldCheck) {
          debugPrint('📦 Using valid feed cache (skipping background check)');
          return;
        }
        debugPrint('🔍 Checking for new feed items in background...');
      } else {
        debugPrint('🔄 Forcing feed refresh...');
      }
    }
    
    // Fetch from API
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
        start: 0,
        limit: 20,
      );

      // Cache the response
      final nextPage = response['next'];
      final hasNext = nextPage != null && nextPage is Map && nextPage.isNotEmpty;
      
      final newItems = response['feed'] ?? [];

      if (hasCachedData) {
        // Cache exists, merge new items but PRESERVE existing pagination
        // passing nextPage: null will cause mergeNewItems to use existing.nextPage
        await _feedCacheService.mergeNewItems(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          newItems: newItems,
          nextPage: null, 
        );
      } else {
        // No cache, save everything including nextPage
        await _feedCacheService.cacheFeed(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          items: newItems,
          nextPage: hasNext ? nextPage : null,
          hasMore: hasNext,
        );
      }
      
      // Reload from cache to get the merged/sorted list
      final updatedCache = await _feedCacheService.getCachedFeed(userId, clientAbbr, sessionId);

      if (mounted && updatedCache != null) {
        setState(() {
          _feedItems = updatedCache.items;
          _isLoadingFeed = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching feed: $e');
      final isNetworkError = e.toString().toLowerCase().contains('socket') ||
                             e.toString().toLowerCase().contains('connection') ||
                             e.toString().toLowerCase().contains('network');
      
      if (mounted) {
        setState(() {
          _isLoadingFeed = false;
        });
        
        // Only show error if we have NO data
        if (_feedItems.isEmpty && isNetworkError) {
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

  Future<void> _fetchTimetable({bool forceRefresh = false}) async {
    await _timetableCacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first
    final cached = await _timetableCacheService.getCachedTimetable(userId, clientAbbr, sessionId);
    
    if (cached != null && cached.timetable.isNotEmpty) {
      if (mounted) {
        setState(() {
          _timetable = cached.timetable;
          _isLoadingTimetable = false;
        });
      }
      
      // If cache is valid and not forced, we can skip API call
      if (!forceRefresh && cached.isValid) {
        debugPrint('📦 Using valid timetable cache');
        return;
      }
      debugPrint(forceRefresh ? '🔄 Forcing timetable refresh...' : '🔍 Timetable cache is stale, refreshing in background...');
    }
    
    // Fetch from API
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final roleId = widget.userData['roleId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final htmlContent = await _apiService.getCommonPage(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
        commonPageId: '85',
      );

      _parseTimetable(htmlContent);
      
      // Cache the timetable
      await _timetableCacheService.cacheTimetable(
        userId: userId,
        clientAbbr: clientAbbr,
        sessionId: sessionId,
        timetable: _timetable,
        subjectNames: null, // Preserve existing subject names
      );

      if (mounted) {
        setState(() {
          _isLoadingTimetable = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching timetable: $e');
      final isNetworkError = e.toString().toLowerCase().contains('socket') ||
                             e.toString().toLowerCase().contains('connection') ||
                             e.toString().toLowerCase().contains('network');
                             
      if (mounted) {
        setState(() {
          _isLoadingTimetable = false;
        });
        
        // Only show error if we have NO data
        if (_timetable.isEmpty && isNetworkError) {
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

  void _parseTimetable(String html) {
    final document = html_parser.parse(html);
    final mobileContainer = document.querySelector('.timetable-mobile');
    
    if (mobileContainer == null) return;

    final dayCards = mobileContainer.querySelectorAll('.day-card');
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    
    for (var dayCard in dayCards) {
      final dayHeader = dayCard.querySelector('.day-header .fw-bold')?.text.trim() ?? '';
      String dayName = dayHeader.split(' ').first;
      if (!days.contains(dayName)) continue;

      final periods = <Map<String, String>>[];
      final periodCards = dayCard.querySelectorAll('.period-card');

      for (var periodCard in periodCards) {
        final timeText = periodCard.querySelector('.small.text-muted')?.text.trim() ?? '';
        final timeRange = timeText.split('|').first.trim();
        
        final detailsDiv = periodCard.querySelector('.period-details');
        if (detailsDiv != null) {
           if (detailsDiv.text.contains('-- No Lecture --')) {
             continue;
           }

           String subject = '';
           String location = '';
           String teacher = '';

           for (var div in detailsDiv.children) {
             final text = div.text;
             if (text.contains('Subject:')) {
               subject = text.replaceAll('Subject:', '').trim();
             } else if (text.contains('Location:')) {
               location = text.replaceAll('Location:', '').trim();
             } else if (text.contains('Teacher:')) {
               teacher = text.replaceAll('Teacher:', '').trim();
             }
           }

           if (subject.isNotEmpty) {
             periods.add({
               'time': timeRange,
               'subject': subject,
               'location': location,
               'teacher': teacher,
             });
           }
        }
      }
      _timetable[dayName] = periods;
    }
  }

  Future<void> _fetchAttendance({bool forceRefresh = false}) async {
    await _attendanceCacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first
    final cached = await _attendanceCacheService.getCachedAttendance(userId, clientAbbr, sessionId);
    
    if (cached != null && cached.subjects.isNotEmpty) {
      if (mounted) {
        setState(() {
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
          _isLoadingSubjects = false;
          
          _isLoadingSubjects = false;
        });
      }
      
      // If cache is valid and not forced, we can skip API call
      if (!forceRefresh && cached.isValid) {
        debugPrint('📦 Using valid attendance cache');
        return;
      }
      debugPrint(forceRefresh ? '🔄 Forcing attendance refresh...' : '🔍 Attendance cache is stale, refreshing in background...');
    }
    
    // Fetch from API
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final roleId = widget.userData['roleId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final htmlContent = await _apiService.getCommonPage(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
      );

      _parseAttendance(htmlContent);
      
      // Cache the attendance
      if (_subjects.isNotEmpty) {
        await _attendanceCacheService.cacheAttendance(
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
        setState(() {
          _isLoadingSubjects = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching attendance: $e');
      final isNetworkError = e.toString().toLowerCase().contains('socket') ||
                             e.toString().toLowerCase().contains('connection') ||
                             e.toString().toLowerCase().contains('network');

      if (mounted) {
        setState(() {
          _isLoadingSubjects = false;
        });
        if (_subjects.isEmpty && isNetworkError) {
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

  Future<void> _updateTimetableSubjectNames() async {
    try {
      final userId = widget.userData['userId'].toString();
      final clientAbbr = widget.clientDetails['client_abbr'];
      final sessionId = widget.userData['sessionId'].toString();
      
      // Create map of code -> name
      final Map<String, String> subjectNames = {};
      
      // Use _subjectDetails (from Subjects section) instead of _subjects (from Attendance)
      for (var subject in _subjectDetails) {
        if (subject.code != null && subject.name != null) {
          subjectNames[subject.code!] = subject.name!;
        }
      }
      
      if (subjectNames.isEmpty) return;
      
      // Get existing timetable cache to preserve the grid
      final cached = await _timetableCacheService.getCachedTimetable(userId, clientAbbr, sessionId);
      
      if (cached != null && cached.timetable.isNotEmpty) {
        // Update cache with new subject names
        await _timetableCacheService.cacheTimetable(
          userId: userId,
          clientAbbr: clientAbbr,
          sessionId: sessionId,
          timetable: cached.timetable,
          subjectNames: subjectNames,
        );
        debugPrint('🔄 Updated timetable cache with ${subjectNames.length} subject names from Attendance');
      }
    } catch (e) {
      debugPrint('Error updating timetable subjects: $e');
    }
  }

  void _parseAttendance(String htmlString) {
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

  List<Map<String, String>> _getUpcomingClasses() {
    final now = DateTime.now();
    if (now.weekday > 6) return []; // Sunday
    
    final currentDay = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][now.weekday - 1];
    final todayClasses = _timetable[currentDay] ?? [];
    
    debugPrint('📅 Current day: $currentDay');
    debugPrint('📚 Today classes: ${todayClasses.length}');
    
    final currentTime = TimeOfDay.now();
    debugPrint('⏰ Current time: ${currentTime.hour}:${currentTime.minute}');
    
    List<Map<String, String>> upcomingClasses = [];
    
    for (var classData in todayClasses) {
      final timeStr = classData['time'] ?? '';
      if (timeStr.isEmpty) {
        debugPrint('⚠️ Empty time string for class');
        continue;
      }
      
      debugPrint('🔍 Checking class: ${classData['subject']} at $timeStr');
      
      final startTimeStr = timeStr.split('-').first.trim();
      try {
        final startTime = _parseTime(startTimeStr);
        if (startTime != null) {
          debugPrint('   Parsed start time: ${startTime.hour}:${startTime.minute}');
          if (_isAfter(startTime, currentTime)) {
            debugPrint('✅ Found upcoming class: ${classData['subject']}');
            debugPrint('   Details: $classData');
            upcomingClasses.add(classData);
          } else {
            debugPrint('   ⏭️ Class already passed');
          }
        } else {
          debugPrint('   ❌ Could not parse time: $startTimeStr');
        }
      } catch (e) {
        debugPrint('   ❌ Error parsing time: $e');
      }
    }
    
    debugPrint('📋 Total upcoming classes: ${upcomingClasses.length}');
    return upcomingClasses;
  }

  TimeOfDay? _parseTime(String timeStr) {
    try {
      // Remove extra spaces and handle formats like "04:10 PM" or "4:10 PM"
      timeStr = timeStr.trim();
      
      // Try multiple formats
      final formats = [
        DateFormat('hh:mm a'), // 04:10 PM
        DateFormat('h:mm a'),  // 4:10 PM
        DateFormat.jm(),       // Default format
      ];
      
      for (var format in formats) {
        try {
          final dateTime = format.parse(timeStr);
          return TimeOfDay(hour: dateTime.hour, minute: dateTime.minute);
        } catch (e) {
          continue;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Time parsing error: $e');
      return null;
    }
  }

  bool _isAfter(TimeOfDay time1, TimeOfDay time2) {
    if (time1.hour > time2.hour) return true;
    if (time1.hour == time2.hour && time1.minute > time2.minute) return true;
    return false;
  }

  String _getSubjectNameByCode(String code) {
    // Try to find the subject in subjects data by code
    for (var subject in _subjectDetails) {
      if (subject.code == code) {
        return subject.name ?? code;
      }
    }
    
    // If not found in subjects, return the code as is
    return code;
  }



  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Get current page for PopScope - use rounded value
    int currentPage = 0;
    if (_pageController.hasClients && _pageController.position.hasContentDimensions) {
      currentPage = _pageController.page?.round() ?? 0;
    }
    
    return PopScope(
      canPop: currentPage == 0,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          HapticFeedback.lightImpact();
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Scaffold(
        extendBody: true,
        body: PageView(
          controller: _pageController,
          physics: const ClampingScrollPhysics(),
          onPageChanged: (index) {
            HapticFeedback.selectionClick();
          },
          children: [
            RepaintBoundary(
              key: const ValueKey('home_page'),
              child: _buildHomeContent(),
            ),
            RepaintBoundary(
              key: const ValueKey('medical_leave_page'),
              child: _buildMedicalLeaveContent(),
            ),
            RepaintBoundary(
              key: const ValueKey('profile_page'),
              child: _buildProfileContent(),
            ),
          ],
        ),
        bottomNavigationBar: AnimatedBuilder(
          animation: _pageController,
          builder: (context, child) {
            double page = 0;
            if (_pageController.hasClients && _pageController.position.hasContentDimensions) {
              page = _pageController.page ?? 0;
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).padding.bottom + 8,
              ),
              child: SizedBox(
                height: 72,
                child: Stack(
                  children: [
                    // Main dock container
                    // Main dock container - Glass Effect
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent, // Transparent for shadow only
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark 
                                  ? const Color(0xFF1A1A1A).withOpacity(0.15)
                                  : Colors.white.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(40),
                              border: Border.all(
                                color: isDark 
                                    ? Colors.white.withOpacity(0.12)
                                    : Colors.white.withOpacity(0.4),
                                width: 1.0,
                              ),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final itemWidth = constraints.maxWidth / 3;
                                return Stack(
                                  children: [
                                    // Animated sliding pill indicator
                                    AnimatedPositioned(
                                      duration: const Duration(milliseconds: 350),
                                      curve: Curves.fastLinearToSlowEaseIn, // Smoother "liquid" curve
                                      left: (page * itemWidth) + 8,
                                      top: 8,
                                      bottom: 8,
                                      width: itemWidth - 16,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              AppTheme.primaryColor.withOpacity(0.9),
                                              AppTheme.primaryColor,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(32),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.primaryColor.withOpacity(0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Nav items row
                                    Row(
                                      children: [
                                        _buildDockNavItem(0, Icons.home_rounded, 'Home', page),
                                        _buildDockNavItem(1, Icons.event_note_rounded, 'Leave', page),
                                        _buildDockNavItem(2, Icons.person_rounded, 'Profile', page),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDockNavItem(int index, IconData icon, String label, double currentPage) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Calculate smooth interpolation based on page position
    final distance = (currentPage - index).abs();
    final scale = (1 - distance.clamp(0.0, 1.0));
    final isSelected = scale > 0.5;
    
    // Color transition from grey to white when selected (icon sits on blue pill)
    final iconColor = Color.lerp(
      isDark ? Colors.grey.shade500 : Colors.grey.shade600,
      Colors.white,
      scale,
    )!;
    
    final labelColor = Color.lerp(
      isDark ? Colors.grey.shade600 : Colors.grey.shade500,
      Colors.white,
      scale,
    )!;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (index != currentPage.round() && mounted) {
            HapticFeedback.lightImpact();
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated icon with scale
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                tween: Tween(begin: 1.0, end: isSelected ? 1.1 : 1.0),
                curve: Curves.easeOutCubic,
                builder: (context, iconScale, child) {
                  return Transform.scale(
                    scale: iconScale,
                    child: Icon(
                      icon,
                      size: 26,
                      color: iconColor,
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              // Label with fade animation
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: labelColor,
                  letterSpacing: 0.1,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    // Reset loading states
    setState(() {
      _isLoadingFeed = true;
      _isLoadingTimetable = true;
      _isLoadingSubjects = true;
    });
    
    // Fetch all data fresh (cache will be updated)
    await Future.wait([
      _fetchFeed(forceRefresh: true),
      _fetchTimetable(forceRefresh: true),
      _fetchAttendance(forceRefresh: true),
      _fetchSubjectsData(),
      _fetchSubjectDetails(forceRefresh: true),
    ]);
  }

  Widget _buildHomeContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final responsive = context.responsive;
    
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppTheme.primaryColor,
      backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: responsive.maxContentWidth),
          child: CustomScrollView(
            key: const PageStorageKey('home_scroll'),
            slivers: [
        SliverAppBar(
          expandedHeight: 120,
          floating: false,
          pinned: true,
          backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
          surfaceTintColor: Colors.transparent,
          actions: [
            // Theme Toggle
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  themeService.toggleTheme();
                },
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return RotationTransition(
                      turns: Tween(begin: 0.5, end: 1.0).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    key: ValueKey(isDark),
                    color: isDark ? AppTheme.warningColor : AppTheme.primaryColor,
                  ),
                ),
                tooltip: isDark ? 'Light mode' : 'Dark mode',
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
            title: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${_userName?.split(' ').first ?? 'Student'}! 👋',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: textColor,
                  ),
                ),
                if (_sessionPeriod != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _sessionPeriod!,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Upcoming Class Card
              _buildUpcomingClassCard(),
              const SizedBox(height: 16),
              
              // Quick Stats Row - wrapped in AnimatedBuilder to update when page changes
              AnimatedBuilder(
                animation: _classPageController,
                builder: (context, child) => _buildQuickStats(),
              ),
              const SizedBox(height: 24),
              
              // Recent Ciculars
              _buildSectionHeader('Recent Ciculars', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FeedScreen(
                      clientDetails: widget.clientDetails,
                      userData: widget.userData,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              
              _isLoadingFeed
                  ? const Center(child: CircularProgressIndicator())
                  : _feedItems.isEmpty
                      ? _buildEmptyState('No ciculars')
                      : Column(
                          children: _feedItems.take(3).toList().asMap().entries.map((entry) {
                            return _buildFeedCard(entry.value, entry.key);
                          }).toList(),
                        ),
            ]),
          ),
        ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingClassCard() {
    if (_isLoadingTimetable) {
      return _buildLoadingCard();
    }
    
    final upcomingClasses = _getUpcomingClasses();
    
    if (upcomingClasses.isEmpty) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TimetableScreen(
                clientDetails: widget.clientDetails,
                userData: widget.userData,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.successColor,
            borderRadius: BorderRadius.circular(24),
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
                    child: const Icon(Icons.celebration_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No More Classes!',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enjoy your free time 🎉',
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.6),
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Build swipeable cards for upcoming classes
    return Column(
      children: [
        SizedBox(
          height: 185,
          child: PageView.builder(
            controller: _classPageController,
            itemCount: upcomingClasses.length,
            onPageChanged: (index) {
              if (index != _lastClassPage) {
                HapticFeedback.selectionClick();
                _lastClassPage = index;
              }
            },
            itemBuilder: (context, index) {
              return _buildClassCard(upcomingClasses[index], index);
            },
          ),
        ),
        if (upcomingClasses.length > 1) ...[
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _classPageController,
            builder: (context, child) {
              double page = 0;
              if (_classPageController.hasClients && _classPageController.position.hasContentDimensions) {
                page = _classPageController.page ?? 0;
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(upcomingClasses.length, (index) {
                  // Calculate smooth interpolation
                  final distance = (page - index).abs();
                  final scale = (1 - distance.clamp(0.0, 1.0));
                  final width = 8 + (16 * scale); // 8 to 24
                  final opacity = 0.3 + (0.7 * scale); // 0.3 to 1.0
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: width,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(opacity),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildClassCard(Map<String, String> classData, int index) {
    final subjectCode = classData['subject'] ?? 'Class';
    final subjectName = _getSubjectNameByCode(subjectCode);
    
    // Solid colors array
    final colors = [
      AppTheme.primaryColor,
    ];
    final cardColor = colors[index % colors.length];
    
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TimetableScreen(
              clientDetails: widget.clientDetails,
              userData: widget.userData,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        index == 0 ? 'Up Next' : 'Coming Up',
                        style: GoogleFonts.inter(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subjectName,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.6),
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildInfoChip(Icons.access_time_rounded, classData['time'] ?? ''),
                _buildInfoChip(Icons.location_on_outlined, classData['location'] ?? ''),
              ],
            ),
            if (classData['teacher']?.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, color: Colors.white.withOpacity(0.8), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      classData['teacher'] ?? '',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],

          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    // Get the currently selected class from the swipe view
    final upcomingClasses = _getUpcomingClasses();
    Map<String, String>? selectedClass;
    
    // Get current page from controller
    int currentPage = 0;
    if (_classPageController.hasClients && _classPageController.position.hasContentDimensions) {
      currentPage = _classPageController.page?.round() ?? 0;
    }
    
    if (upcomingClasses.isNotEmpty && currentPage < upcomingClasses.length) {
      selectedClass = upcomingClasses[currentPage];
    }
    
    double currentClassAttendance = 0.0;
    String currentClassName = 'No Class';
    String? subjectCodeForNav;
    
    if (selectedClass != null) {
      final subjectCode = selectedClass['subject'] ?? '';
      subjectCodeForNav = subjectCode;
      
      // Try matching by subject code first (most reliable)
      var matchingSubject = _subjects.firstWhere(
        (s) => s.code?.toLowerCase() == subjectCode.toLowerCase(),
        orElse: () => AttendanceSubject(),
      );
      
      // If no code match, try by name
      if (matchingSubject.name == null) {
        matchingSubject = _subjects.firstWhere(
          (s) => s.name?.toLowerCase() == subjectCode.toLowerCase(),
          orElse: () => AttendanceSubject(),
        );
      }
      
      // If still no match, try contains
      if (matchingSubject.name == null) {
        matchingSubject = _subjects.firstWhere(
          (s) => (s.name?.toLowerCase().contains(subjectCode.toLowerCase()) ?? false) ||
                 (s.code?.toLowerCase().contains(subjectCode.toLowerCase()) ?? false),
          orElse: () => AttendanceSubject(),
        );
      }
      
      if (matchingSubject.name != null) {
        currentClassAttendance = double.tryParse(matchingSubject.percentage ?? '0') ?? 0.0;
        currentClassName = matchingSubject.name ?? _getSubjectNameByCode(subjectCode);
      } else {
        currentClassName = _getSubjectNameByCode(subjectCode);
        if (currentClassName == subjectCode) {
          currentClassName = subjectCode.isNotEmpty ? subjectCode : 'No Data';
        }
      }
    }
    
    final totalSubjects = _isLoadingSubjects ? 0 : _subjectDetails.length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Attendance',
            currentClassAttendance > 0 ? '${currentClassAttendance.toStringAsFixed(1)}%' : '--',
            Icons.pie_chart_rounded,
            currentClassAttendance >= 75 ? AppTheme.successColor : (currentClassAttendance > 0 ? AppTheme.errorColor : AppTheme.primaryColor),
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AttendanceScreen(
                    clientDetails: widget.clientDetails,
                    userData: widget.userData,
                    initialSubjectCode: subjectCodeForNav,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Subjects',
            totalSubjects > 0 ? '$totalSubjects' : '--',
            Icons.menu_book_rounded,
            AppTheme.accentColor,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SubjectsScreen(
                    clientDetails: widget.clientDetails,
                    userData: widget.userData,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: isDark ? AppTheme.darkCardColor : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? color.withOpacity(0.3) : color.withOpacity(0.2), 
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: color.withOpacity(0.7),
                      size: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    'View',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: color.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onViewAll) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        if (onViewAll != null)
          TextButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              onViewAll();
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(
              'View All',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFeedCard(dynamic item, int index) {
    final title = (item['title']?['S'] ?? 'No Title').toString().decodeHtml;
    final desc = (item['desc']?['S'] ?? '').toString().decodeHtml;
    final date = item['creDate']?['S'] ?? '';
    final timeStr = item['creTime']?['S'] ?? '';
    final time = formatTime(timeStr);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Cycle through colors for visual variety - Professional palette
    final colors = [

      AppTheme.accentColor,
    ];
    final accentColor = colors[index % colors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FeedDetailScreen(
                  clientDetails: widget.clientDetails,
                  userData: widget.userData,
                  itemId: item['itemId']?['N'] ?? '',
                  itemType: item['itemType']?['N'] ?? '',
                  title: title,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon with solid color background
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          desc,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark ? Colors.grey.shade400 : Colors.black54,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (date.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 12, color: accentColor),
                              const SizedBox(width: 6),
                              Text(
                                time.isNotEmpty ? '$date • $time' : date,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: accentColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded, 
                  size: 14, 
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 140,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildEmptyState(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined, 
            size: 64, 
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.inter(
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalLeaveContent() {
    return MedicalLeaveScreen(
      clientDetails: widget.clientDetails,
      userData: widget.userData,
      onBackPressed: () {
        // Navigate back to home tab (index 0)
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
    );
  }

  Widget _buildProfileContent() {
    return ProfileScreen(
      clientDetails: widget.clientDetails,
      userData: widget.userData,
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
