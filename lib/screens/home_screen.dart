import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:html/parser.dart' as html_parser;
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' show themeService;
import 'feed_screen.dart';
import 'feed_detail_screen.dart';
import 'attendance_screen.dart';
import 'timetable_screen.dart';
import 'profile_screen.dart';
import 'subjects_screen.dart';

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
  late PageController _pageController;
  late PageController _classPageController;
  
  // Data holders
  List<dynamic> _feedItems = [];
  Map<String, List<Map<String, String>>> _timetable = {};
  List<AttendanceSubject> _subjects = [];
  List<Subject> _subjectDetails = []; // Subject details from subjects screen
  
  // Loading states
  bool _isLoadingFeed = true;
  bool _isLoadingTimetable = true;
  bool _isLoadingSubjects = true;
  
  String? _userName;
  String? _currentSemester;
  String? _currentGroup;
  int _selectedIndex = 0;
  int _currentClassPage = 0;

  @override
  bool get wantKeepAlive => true; // Keep state alive for smooth transitions

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _selectedIndex,
      viewportFraction: 1.0, // Full page view
    );
    _classPageController = PageController(viewportFraction: 0.92);
    // Listen for page changes to update nav bar smoothly
    _pageController.addListener(_onPageScroll);
    _fetchAllData();
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _classPageController.dispose();
    super.dispose();
  }

  // Smooth page scroll listener - updates nav only when page settles
  void _onPageScroll() {
    if (!mounted) return;
    final page = _pageController.page;
    if (page == null) return;
    
    // Only update when page is fully settled (no animation in progress)
    final roundedPage = page.round();
    if ((page - roundedPage).abs() < 0.01 && _selectedIndex != roundedPage) {
      setState(() {
        _selectedIndex = roundedPage;
      });
    }
  }

  Future<void> _fetchAllData() async {
    _userName = widget.userData['name'] ?? 'Student';
    
    // Ensure cookies are loaded before making API calls
    await _apiService.ensureCookiesLoaded();
    
    // First load cached semester info for instant display
    _loadSemesterInfo();
    
    // Fetch all data in parallel for faster loading
    await Future.wait([
      _fetchFeed(),
      _fetchTimetable(),
      _fetchAttendance(),
      _fetchSubjectsData(), // Fetch subjects to get semester & group
      _fetchSubjectDetails(), // Fetch detailed subject info
    ]);
  }

  Future<void> _loadSemesterInfo() async {
    final semesterInfo = await _apiService.getSemesterInfo();
    if (mounted) {
      setState(() {
        _currentSemester = semesterInfo['semester'];
        _currentGroup = semesterInfo['group'];
      });
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

      // Parse semester and group from subjects
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

    // Get semester from heading - e.g., "Subject(s) Details (5 SEM)"
    final heading = document.querySelector('.heading');
    String? semester;
    if (heading != null) {
      semester = ApiService.parseSemesterFromText(heading.text.trim());
    }

    // Get group from first subject
    String? group;
    final subjectWraps = document.querySelectorAll('.ui-subject-wrap');
    for (var wrap in subjectWraps) {
      final details = wrap.querySelectorAll('.ui-subject-detail');
      for (var detail in details) {
        final text = detail.text.trim();
        if (text.contains('Group:')) {
          group = text.replaceFirst('Group:', '').trim();
          break;
        }
      }
      if (group != null) break;
    }

    // Save and update state
    if (semester != null || group != null) {
      _apiService.saveSemesterInfo(semester: semester, group: group);
      if (mounted) {
        setState(() {
          if (semester != null) _currentSemester = semester;
          if (group != null) _currentGroup = group;
        });
      }
    }
  }

  Future<void> _fetchSubjectDetails() async {
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

      _parseSubjectDetails(htmlContent);
    } catch (e) {
      debugPrint('Error fetching subject details: $e');
      if (mounted) {
        setState(() {
          _isLoadingSubjects = false;
        });
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

  Future<void> _fetchFeed() async {
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
        start: 0,
        limit: 5,
      );

      if (mounted) {
        setState(() {
          _feedItems = response['feed'] ?? [];
          _isLoadingFeed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFeed = false;
        });
      }
    }
  }

  Future<void> _fetchTimetable() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final roleId = widget.userData['roleId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final htmlContent = await _apiService.getCommonPage(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
        commonPageId: '84',
      );

      _parseTimetable(htmlContent);

      if (mounted) {
        setState(() {
          _isLoadingTimetable = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTimetable = false;
        });
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

  Future<void> _fetchAttendance() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
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

      _parseAttendance(htmlContent);
    } catch (e) {
      // Handle error silently
    }
  }

  void _parseAttendance(String htmlString) {
    final document = html_parser.parse(htmlString);
    final subjectBoxes = document.querySelectorAll('.tt-box-new');
    
    _subjects = subjectBoxes.map((box) {
      final subject = AttendanceSubject();
      
      final periodNumberDiv = box.querySelector('.tt-period-number');
      if (periodNumberDiv != null) {
        final spans = periodNumberDiv.querySelectorAll('span');
        if (spans.isNotEmpty) subject.name = spans[0].text.trim();
        if (spans.length > 1) subject.code = spans[1].text.trim();
      }

      final detailsDivs = box.querySelectorAll('.tt-period-name');
      for (var div in detailsDivs) {
        final text = div.text.trim();
        if (text.startsWith('Delivered :')) {
          subject.delivered = text.replaceAll('Delivered :', '').trim();
        } else if (text.startsWith('Attended :')) {
          subject.attended = text.replaceAll('Attended :', '').trim();
        } else if (text.startsWith('Total Percentage :')) {
          subject.percentage = text.replaceAll('Total Percentage :', '').replaceAll('%', '').trim();
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
    // Try to find the subject in attendance data by code
    for (var subject in _subjects) {
      if (subject.code == code) {
        return subject.name ?? code;
      }
    }
    
    // If not found in attendance, return the code as is
    return code;
  }



  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && _selectedIndex == 1) {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedIndex = 0;
          });
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          physics: const ClampingScrollPhysics(),
          children: [
            RepaintBoundary(
              key: const ValueKey('home_page'),
              child: _buildHomeContent(),
            ),
            RepaintBoundary(
              key: const ValueKey('profile_page'),
              child: _buildProfileContent(),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                  _buildNavItem(1, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData selectedIcon, String label) {
    final isSelected = _selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        if (_selectedIndex != index && mounted) {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedIndex = index;
          });
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppTheme.primaryColor.withOpacity(isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              size: 24,
              color: isSelected 
                  ? AppTheme.primaryColor
                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return CustomScrollView(
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
                if (_currentSemester != null || _currentGroup != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_currentSemester != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Sem $_currentSemester',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (_currentSemester != null && _currentGroup != null)
                          const SizedBox(width: 6),
                        if (_currentGroup != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _currentGroup!,
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
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Upcoming Class Card
              _buildUpcomingClassCard().animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),
              const SizedBox(height: 16),
              
              // Quick Stats Row
              _buildQuickStats().animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
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
              setState(() {
                _currentClassPage = index;
              });
            },
            itemBuilder: (context, index) {
              return _buildClassCard(upcomingClasses[index], index);
            },
          ),
        ),
        if (upcomingClasses.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(upcomingClasses.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentClassPage == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentClassPage == index 
                      ? AppTheme.primaryColor 
                      : AppTheme.primaryColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
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
    
    if (upcomingClasses.isNotEmpty && _currentClassPage < upcomingClasses.length) {
      selectedClass = upcomingClasses[_currentClassPage];
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
            currentClassName.length > 15 ? 'Attendance' : currentClassName,
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
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: isDark ? AppTheme.darkCardColor : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
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
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
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
            onPressed: onViewAll,
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
    final title = item['title']?['S'] ?? 'No Title';
    final desc = item['desc']?['S'] ?? '';
    final date = item['creDate']?['S'] ?? '';
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
                                date,
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
    ).animate().fadeIn(delay: (100 * index).ms, duration: 400.ms).slideY(begin: 0.2);
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
  String? delivered;
  String? attended;
  String? percentage;
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
