import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class TimetableScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const TimetableScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, List<Map<String, String>>> _timetable = {};
  late TabController _tabController;
  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  
  // Subject code to name mapping
  Map<String, String> _subjectNames = {};
  bool _isLoadingSubjects = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _days.length, vsync: this);
    _fetchTimetable();
    _fetchSubjectNames(); // Fetch subjects in parallel
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        commonPageId: '84', // ID for Timetable
      );

      _parseTimetable(htmlContent);

      setState(() {
        _isLoading = false;
      });
      
      // Set initial tab to current day if possible
      final now = DateTime.now();
      // weekday: 1 = Mon, 7 = Sun. We map Mon(1) -> 0, Sat(6) -> 5.
      if (now.weekday >= 1 && now.weekday <= 6) {
        _tabController.animateTo(now.weekday - 1);
      }

    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchSubjectNames() async {
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

      _parseSubjectNames(htmlContent);

      setState(() {
        _isLoadingSubjects = false;
      });
    } catch (e) {
      debugPrint('Error fetching subject names: $e');
      setState(() {
        _isLoadingSubjects = false;
      });
    }
  }

  void _parseSubjectNames(String htmlContent) {
    // Clean the HTML
    String cleanHtml = htmlContent.replaceAll(r'\"', '"').replaceAll(r'\/', '/');
    if (cleanHtml.startsWith('"') && cleanHtml.endsWith('"')) {
      cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
    }

    final document = html_parser.parse(cleanHtml);
    final subjectWraps = document.querySelectorAll('.ui-subject-wrap');

    for (var wrap in subjectWraps) {
      final details = wrap.querySelectorAll('.ui-subject-detail');
      
      String? name;
      String? code;

      for (var detail in details) {
        final text = detail.text.trim();
        
        if (text.contains('Subject Name:')) {
          name = text.replaceFirst('Subject Name:', '').trim();
        } else if (text.contains('Subject Code:')) {
          code = text.replaceFirst('Subject Code:', '').trim();
          // Remove any "(Optional)" text from code
          code = code.replaceAll(RegExp(r'\s*\(Optional\)', caseSensitive: false), '').trim();
        }
      }

      if (code != null && name != null) {
        _subjectNames[code] = name;
      }
    }
    
    debugPrint('Loaded ${_subjectNames.length} subject names');
  }

  void _parseTimetable(String html) {
    final document = html_parser.parse(html);
    final mobileContainer = document.querySelector('.timetable-mobile');
    
    if (mobileContainer == null) return;

    final dayCards = mobileContainer.querySelectorAll('.day-card');
    
    for (var dayCard in dayCards) {
      final dayHeader = dayCard.querySelector('.day-header .fw-bold')?.text.trim() ?? '';
      // Extract just the day name (e.g., "Monday (Today)" -> "Monday")
      String dayName = dayHeader.split(' ').first;
      if (!_days.contains(dayName)) continue;

      final periods = <Map<String, String>>[];
      final periodCards = dayCard.querySelectorAll('.period-card');

      for (var periodCard in periodCards) {
        final timeText = periodCard.querySelector('.small.text-muted')?.text.trim() ?? '';
        // Format: "04:10 PM - 05:00 PM | 22CS025  ➤"
        final timeRange = timeText.split('|').first.trim();
        
        final detailsDiv = periodCard.querySelector('.period-details');
        if (detailsDiv != null) {
           // Check for "No Lecture"
           if (detailsDiv.text.contains('-- No Lecture --')) {
             continue; // Skip empty slots or handle them if you want to show free periods
           }

           final subjectDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Subject:'), orElse: () => dom.Element.tag('div'));
           final locationDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Location:'), orElse: () => dom.Element.tag('div'));
           final teacherDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Teacher:'), orElse: () => dom.Element.tag('div'));
           final groupDiv = detailsDiv.children.firstWhere((e) => e.text.contains('Group:'), orElse: () => dom.Element.tag('div'));

           final subject = subjectDiv.text.replaceAll('Subject:', '').trim();
           final location = locationDiv.text.replaceAll('Location:', '').trim();
           final teacher = teacherDiv.text.replaceAll('Teacher:', '').trim();
           final group = groupDiv.text.replaceAll('Group:', '').trim();

           if (subject.isNotEmpty) {
             periods.add({
               'time': timeRange,
               'subject': subject,
               'location': location,
               'teacher': teacher,
               'group': group,
             });
           }
        }
      }
      _timetable[dayName] = periods;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Timetable: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar.large(
                expandedHeight: 140,
                floating: false,
                pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  'Timetable',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                  ),
                ),
              ),
            ),
            if (!_isLoading)
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: AppTheme.primaryColor,
                    unselectedLabelColor: Colors.grey,
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
                    tabs: _days.map((day) {
                      final now = DateTime.now();
                      final isToday = day == _days[now.weekday - 1];
                      return Tab(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isToday 
                                ? AppTheme.primaryColor.withOpacity(0.1) 
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(day),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ];
        },
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
                          style: GoogleFonts.inter(color: Colors.black54),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: _days.map((day) => _buildDaySchedule(day)).toList(),
                  ),
        ),
      ),
    );
  }

  Widget _buildDaySchedule(String day) {
    final periods = _timetable[day];

    if (periods == null || periods.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No classes scheduled',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: periods.length,
      itemBuilder: (context, index) {
        final period = periods[index];
        final subjectCode = period['subject'] ?? '';
        final subjectName = _subjectNames[subjectCode];
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                AppTheme.accentColor.withOpacity(0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.accentColor.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentColor.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppTheme.accentGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Subject Name with smooth loading
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: subjectName != null
                                ? Text(
                                    subjectName,
                                    key: ValueKey('name_$subjectCode'),
                                    style: GoogleFonts.outfit(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  )
                                : _isLoadingSubjects
                                    ? Row(
                                        key: const ValueKey('loading'),
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                AppTheme.accentColor.withOpacity(0.5),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Loading...',
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        subjectCode,
                                        key: ValueKey('code_only_$subjectCode'),
                                        style: GoogleFonts.outfit(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                          ),
                          const SizedBox(height: 4),
                          // Subject Code Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              subjectCode,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            period['time'] ?? '',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(Icons.location_on_outlined, period['location'] ?? ''),
                    _buildInfoChip(Icons.group_outlined, period['group'] ?? ''),
                  ],
                ),
                if (period['teacher'] != null && period['teacher']!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded, 
                        size: 18, 
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          period['teacher']!,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ).animate().fadeIn(delay: (50 * index).ms).scale(delay: (50 * index).ms);
      },
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
