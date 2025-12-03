import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ReportCardScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const ReportCardScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends State<ReportCardScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  
  // Parsed Data
  List<SemesterResult> _semesters = [];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _fetchReportCard();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _fetchReportCard() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final roleId = widget.userData['roleId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      // commonPageId 31 is for Report Card based on user info
      final htmlContent = await _apiService.getCommonPage(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        appKey: appKey,
        commonPageId: '31', 
      );

      _parseHtml(htmlContent);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_semesters.isNotEmpty) {
            _tabController = TabController(length: _semesters.length, vsync: this);
            // Optional: Default to the last semester (most recent)
             _tabController?.animateTo(_semesters.length - 1);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _parseHtml(String htmlString) {
    try {
      // Clean up HTML
      String cleanHtml = htmlString.replaceAll(r'\"', '"').replaceAll(r'\/', '/');
      if (cleanHtml.startsWith('"') && cleanHtml.endsWith('"')) {
        cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
      }
      
      final document = html_parser.parse(cleanHtml);
      
      // Find tables
      final tables = document.querySelectorAll('table');
      debugPrint('Found ${tables.length} tables');
      
      dom.Element? resultTable;
      
      for (var table in tables) {
        final text = table.text.toLowerCase();
        if (text.contains('subject code') && text.contains('grade')) {
          resultTable = table;
          break;
        }
      }
      
      // 1. Parse Semesters and Subjects
      if (resultTable != null) {
        debugPrint('Found Result Table');
        
        final rows = resultTable.querySelectorAll('tbody > tr');
        if (rows.isEmpty) {
           // Fallback if > selector doesn't work as expected in this package
           // Select all trs and filter
           resultTable.querySelectorAll('tr');
        }
        
        List<SubjectResult> currentSubjects = [];
        
        for (var row in rows) {
          final cells = row.querySelectorAll('td');
          if (cells.isEmpty) continue;
          
          // Check if it's a summary row
          bool isSummaryRow = false;
          String summaryText = '';
          
          if (cells.length == 1) {
             isSummaryRow = true;
             summaryText = cells[0].text.trim();
          } else if (cells[0].attributes.containsKey('colspan')) {
             isSummaryRow = true;
             summaryText = row.text.trim();
          }
          
          if (isSummaryRow) {
            // Parse Summary
            debugPrint('Found Summary Row: $summaryText');
            
            String semName = '';
            String sgpa = '';
            String cgpa = '';
            
            // Extract Sem Name
            final semMatch = RegExp(r'Study Period:\s*(.*?)(?:\s{2,}|$)', caseSensitive: false).firstMatch(summaryText);
            if (semMatch != null) {
              semName = semMatch.group(1)?.trim() ?? '';
            }
            
            // Extract SGPA
            final sgpaMatch = RegExp(r'SGPA:\s*([\d\.]+)', caseSensitive: false).firstMatch(summaryText);
            if (sgpaMatch != null) sgpa = sgpaMatch.group(1) ?? '';
            
            // Extract CGPA
            final cgpaMatch = RegExp(r'CGPA:\s*([\d\.]+)', caseSensitive: false).firstMatch(summaryText);
            if (cgpaMatch != null) cgpa = cgpaMatch.group(1) ?? '';
            
            if (semName.isNotEmpty) {
              _semesters.add(SemesterResult(
                semesterName: semName,
                sgpa: sgpa,
                cgpa: cgpa,
                subjects: List.from(currentSubjects),
              ));
              currentSubjects.clear();
            }
          } else {
            // Subject Row
            if (cells.length >= 5) {
              final serial = cells[0].text.trim();
              final code = cells[1].text.trim();
              final name = cells[2].text.trim();
              final credits = cells[3].text.trim();
              final grade = cells[4].text.trim();
              
              // Filter out header if it appeared again
              if (code.toLowerCase() != 'subject code' && code.isNotEmpty) {
                currentSubjects.add(SubjectResult(
                  serialNo: serial,
                  code: code,
                  name: name,
                  credits: credits,
                  grade: grade,
                ));
              }
            }
          }
        }
      }
      
    } catch (e) {
      debugPrint('Error parsing report card HTML: $e');
      setState(() {
        _errorMessage = 'Failed to parse report card: $e';
      });
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
              ? Center(child: Text(
                  'Error: $_errorMessage',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                ))
              : _semesters.isEmpty
                  ? Center(child: Text(
                      'No report card data found',
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                    ))
                  : NestedScrollView(
                      headerSliverBuilder: (context, innerBoxIsScrolled) {
                        return [
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
                            flexibleSpace: FlexibleSpaceBar(
                              title: Text(
                                'Report Card',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
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
                                tabs: _semesters.map((sem) {
                                  return Tab(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(sem.semesterName),
                                    ),
                                  );
                                }).toList(),
                              ),
                              isDark: isDark,
                            ),
                          ),
                        ];
                      },
                      body: TabBarView(
                        controller: _tabController,
                        children: _semesters.map((semester) => _buildSemesterView(semester, isDark)).toList(),
                      ),
                    ),
    );
  }

  Widget _buildSemesterView(SemesterResult semester, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // GPA Summary Card
        Container(
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildGpaStat('SGPA', semester.sgpa),
              Container(width: 1, height: 40, color: Colors.white.withOpacity(0.2)),
              _buildGpaStat('CGPA', semester.cgpa),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.1, end: 0),
        
        const SizedBox(height: 24),
        
        Text(
          'Subjects',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        
        // Subjects List
        ...semester.subjects.asMap().entries.map((entry) {
          final index = entry.key;
          final subject = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildSubjectCard(subject, isDark)
                .animate()
                .fadeIn(delay: (50 * index).ms)
                .slideX(begin: 0.1, end: 0),
          );
        }),
        
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildGpaStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 24,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectCard(SubjectResult subject, bool isDark) {
    Color gradeColor = _getGradeColor(subject.grade);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.name,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkElevatedColor : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                        ),
                      ),
                      child: Text(
                        subject.code,
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Credits: ${subject.credits}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: gradeColor.withOpacity(isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: gradeColor.withOpacity(0.2)),
            ),
            child: Text(
              subject.grade,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: gradeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'O':
      case 'A+':
        return const Color(0xFF10B981); // Green
      case 'A':
        return const Color(0xFF3B82F6); // Blue
      case 'B+':
      case 'B':
        return const Color(0xFFF59E0B); // Amber
      case 'C':
      case 'P':
        return const Color(0xFFF97316); // Orange
      case 'F':
        return const Color(0xFFEF4444); // Red
      default:
        return Colors.grey;
    }
  }
}

class SemesterResult {
  final String semesterName;
  final String sgpa;
  final String cgpa;
  final List<SubjectResult> subjects;

  SemesterResult({
    required this.semesterName,
    required this.sgpa,
    required this.cgpa,
    required this.subjects,
  });
}

class SubjectResult {
  final String serialNo;
  final String code;
  final String name;
  final String credits;
  final String grade;

  SubjectResult({
    required this.serialNo,
    required this.code,
    required this.name,
    required this.credits,
    required this.grade,
  });
}

// Sticky TabBar Delegate
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _StickyTabBarDelegate(this.tabBar, {required this.isDark});

  final TabBar tabBar;
  final bool isDark;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar || isDark != oldDelegate.isDark;
  }
}
