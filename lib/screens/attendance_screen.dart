import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const AttendanceScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  List<AttendanceSubject> _subjects = [];
  Map<int, int> _classesToMissMap = {}; // Track classes to miss per subject

  @override
  void initState() {
    super.initState();
    _fetchAttendance();
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

      _parseHtml(htmlContent);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
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
        final text = div.text.trim();
        if (text.startsWith('Teacher :')) {
          subject.teacher = text.replaceAll('Teacher :', '').trim();
        } else if (text.startsWith('From :')) {
          // Parse From and To dates
          // Example: From : 01 Jul 2025    TO : 28 Nov 2025
          // This might be tricky with just text, let's try basic split
          subject.duration = text.trim(); 
        } else if (text.startsWith('Delivered :')) {
          subject.delivered = text.replaceAll('Delivered :', '').trim();
        } else if (text.startsWith('Attended :')) {
          subject.attended = text.replaceAll('Attended :', '').trim();
        } else if (text.startsWith('Absent :')) {
          subject.absent = text.replaceAll('Absent :', '').trim();
        } else if (text.contains('DL :') && text.contains('ML :')) {
          // Store the raw string (e.g., "DL : 10  ML : 0")
          // Parsing is done via getters in AttendanceSubject
          subject.leaves = text.trim();
        } else if (text.startsWith('Total Percentage :')) {
          subject.percentage = text.replaceAll('Total Percentage :', '').replaceAll('%', '').trim();
        } else if (text.startsWith('Total Approved DL :')) {
          subject.totalApprovedDL = text.replaceAll('Total Approved DL :', '').trim();
        } else if (text.startsWith('Total Approved ML :')) {
          subject.totalApprovedML = text.replaceAll('Total Approved ML :', '').trim();
        }
      }
      return subject;
    }).toList();
  }



  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (bool didPop) {
        if (didPop) {
          debugPrint('✅ Attendance: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              expandedHeight: 140,
              floating: false,
              pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Attendance',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                ),
              ),
            ),
          ),
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _errorMessage != null
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, 
                              size: 64, 
                              color: AppTheme.errorColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error: $_errorMessage',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _subjects.isEmpty
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined, 
                                  size: 64, 
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No attendance records found',
                                  style: GoogleFonts.inter(color: Colors.grey.shade400),
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
                                return _buildSubjectCard(_subjects[index], index);
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

  Widget _buildSubjectCard(AttendanceSubject subject, int index) {
    double percentage = double.tryParse(subject.percentage ?? '0') ?? 0.0;
    Color progressColor = percentage >= 75 
        ? AppTheme.successColor 
        : (percentage >= 60 ? AppTheme.warningColor : AppTheme.errorColor);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: progressColor.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: progressColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Percentage Circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        progressColor,
                        progressColor.withOpacity(0.7),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: progressColor.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${percentage.toStringAsFixed(2)}%',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          percentage >= 75 ? '✓' : '!',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Subject Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.name ?? 'Unknown Subject',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (subject.code != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: progressColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            subject.code!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: progressColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildMiniStat(
                            'Present',
                            subject.attended ?? '0',
                            AppTheme.successColor,
                          ),
                          const SizedBox(width: 8),
                          _buildMiniStat(
                            'Total',
                            subject.delivered ?? '0',
                            AppTheme.accentColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  if (subject.teacher != null && subject.teacher!.isNotEmpty)
                    _buildDetailRow(Icons.person_outline, 'Teacher', subject.teacher),
                  if (subject.absent != null && subject.absent!.isNotEmpty)
                    _buildDetailRow(Icons.cancel_outlined, 'Absent', subject.absent),
                  if (subject.leaves != null)
                    _buildDetailRow(Icons.info_outline, 'Leaves', subject.leaves),
                  if (subject.totalApprovedDL != null)
                    _buildDetailRow(Icons.verified_outlined, 'Approved DL', subject.totalApprovedDL),
                  if (subject.totalApprovedML != null)
                    _buildDetailRow(Icons.medical_services_outlined, 'Approved ML', subject.totalApprovedML),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildPredictionCard(subject, index),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (80 * index).ms).slideX(begin: 0.1, end: 0);
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionCard(AttendanceSubject subject, int index) {
    final delivered = int.tryParse(subject.delivered ?? '0') ?? 0;
    final attended = int.tryParse(subject.attended ?? '0') ?? 0;
    final dl = subject.dl;
    final ml = subject.ml;
    
    if (delivered == 0) return const SizedBox.shrink();
    
    // Get or initialize classes to miss for this subject
    final classesToMiss = _classesToMissMap[index] ?? 1;
    
    // Calculate attendance (DL is always counted as attended)
    final attendedWithDL = attended + dl;
    // Current attendance as shown in system (includes ML)
    final currentAttendance = (attendedWithDL + ml) / delivered * 100;
    // Real attendance without ML
    final attendanceWithoutML = attendedWithDL / delivered * 100;
    
    // Calculate if missing X classes
    final newDelivered = delivered + classesToMiss;
    final ifMissWithoutML = attendedWithDL / newDelivered * 100;
    final ifMissWithML = (attendedWithDL + ml) / newDelivered * 100;
    
    // Determine status
    String status;
    Color statusColor;
    IconData statusIcon;
    String message;
    
    if (attendanceWithoutML < 65) {
      status = "Don't Miss!";
      statusColor = AppTheme.errorColor;
      statusIcon = Icons.block;
      message = "Your real attendance (excluding ML) is below 65%";
    } else if (ifMissWithML >= 75) {
      status = "Good to Go";
      statusColor = AppTheme.successColor;
      statusIcon = Icons.check_circle;
      message = "You'll stay above 75% even with ML counted";
    } else {
      status = "Risky";
      statusColor = AppTheme.warningColor;
      statusIcon = Icons.warning;
      message = "Safe without ML (≥65%) but below 75% with ML";
    }
    
    return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                statusColor.withOpacity(0.1),
                statusColor.withOpacity(0.05),
              ],
            ),
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
                        color: Colors.black87,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildPredictionRow(
                      'Current (with ML)',
                      currentAttendance,
                      Colors.blue,
                    ),
                    const Divider(height: 16),
                    _buildPredictionRow(
                      'Real (without ML)',
                      attendanceWithoutML,
                      attendanceWithoutML >= 65 ? AppTheme.successColor : AppTheme.errorColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Classes to miss:',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.black87,
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
                        color: Colors.white,
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
                    onPressed: classesToMiss < 10
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
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'If you miss $classesToMiss class${classesToMiss > 1 ? 'es' : ''}:',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'With ML:',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '${ifMissWithML.toStringAsFixed(2)}%',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: ifMissWithML >= 75 ? AppTheme.successColor : AppTheme.errorColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Without ML:',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '${ifMissWithoutML.toStringAsFixed(2)}%',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: ifMissWithoutML >= 65 ? AppTheme.successColor : AppTheme.errorColor,
                          ),
                        ),
                      ],
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
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
  }

  Widget _buildPredictionRow(String label, double percentage, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.black87,
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
