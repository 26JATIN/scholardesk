import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as html_parser;
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Screen to display attendance register from the API
/// Endpoint: /chalkpadpro/studentDetails/getAttendanceRegister
class AttendanceRegisterScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const AttendanceRegisterScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<AttendanceRegisterScreen> createState() => _AttendanceRegisterScreenState();
}

class _AttendanceRegisterScreenState extends State<AttendanceRegisterScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _error;
  List<SubjectAttendanceRegister> _subjects = [];

  @override
  void initState() {
    super.initState();
    _fetchAttendanceRegister();
  }

  Future<void> _fetchAttendanceRegister() async {
    setState(() {
      _isLoading = true;
      _error = null;
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
        throw Exception('Missing required client or user details');
      }

      debugPrint('🔍 Step 1: Initializing attendance session...');
      
      // Step 1: Call showAttendance to initialize server state (exactly like the web app)
      try {
        await _apiService.showAttendance(
          baseUrl: baseUrl,
          clientAbbr: clientAbbr,
          userId: userId,
          sessionId: sessionId,
          apiKey: apiKey,
          roleId: roleId,
          prevNext: '0',
          month: '', // Empty month parameter as per your trace
        );
        debugPrint('✅ Step 1: Attendance session initialized');
      } catch (e) {
        debugPrint('⚠️ Step 1 failed (continuing anyway): $e');
        // Continue even if this fails - it might not be critical
      }

      debugPrint('🔍 Step 2: Fetching Attendance Register...');
      debugPrint('   URL: https://$clientAbbr.$baseUrl/chalkpadpro/studentDetails/getAttendanceRegister');
      debugPrint('   StudentID: $studentId');
      debugPrint('   SessionID: $sessionId');

      // Step 2: Call the attendance register endpoint
      final response = await _apiService.getAttendanceRegister(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        studentId: studentId,
        sessionId: sessionId,
      );

      debugPrint('✅ Step 2: Received response: ${response.length} characters');

      // Parse the HTML response
      _parseAttendanceRegister(response);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error fetching attendance register: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _parseAttendanceRegister(String htmlContent) {
    debugPrint('🔍 Starting to parse HTML response...');
    debugPrint('📄 HTML length: ${htmlContent.length} characters');
    
    // Save HTML for inspection (first time only)
    if (_subjects.isEmpty) {
      debugPrint('📝 First 2000 chars of HTML:\n${htmlContent.substring(0, htmlContent.length > 2000 ? 2000 : htmlContent.length)}');
    }
    
    final document = html_parser.parse(htmlContent);
    
    // The response has a single table with multiple thead/tbody pairs
    final table = document.querySelector('table');
    if (table == null) {
      debugPrint('❌ No table found in response');
      debugPrint('📄 HTML preview: ${htmlContent.substring(0, htmlContent.length > 500 ? 500 : htmlContent.length)}');
      return;
    }

    final subjects = <SubjectAttendanceRegister>[];
    
    // Find all thead elements - each represents a subject
    final theadElements = table.querySelectorAll('thead');
    final tbodyElements = table.querySelectorAll('tbody');

    debugPrint('📊 Found ${theadElements.length} thead elements and ${tbodyElements.length} tbody elements');

    for (int i = 0; i < theadElements.length && i < tbodyElements.length; i++) {
      try {
        final thead = theadElements[i];
        final tbody = tbodyElements[i];

        // Get all rows in thead
        final theadRows = thead.querySelectorAll('tr');
        debugPrint('  Subject $i: Found ${theadRows.length} rows in thead');
        
        // Log first few rows to understand structure
        for (int rowIdx = 0; rowIdx < theadRows.length && rowIdx < 3; rowIdx++) {
          final row = theadRows[rowIdx];
          final cells = row.querySelectorAll('th');
          debugPrint('    Row $rowIdx: ${cells.length} cells');
          if (cells.isNotEmpty) {
            final sampleText = cells.take(3).map((c) => '"${c.text.trim()}"').join(', ');
            debugPrint('    Sample: $sampleText');
          }
        }
        
        if (theadRows.length < 2) {
          debugPrint('  Subject $i: Skipping - not enough rows');
          continue;
        }

        // Second row has subject name and lecture headers
        final subjectRow = theadRows[1];
        final allHeaders = subjectRow.querySelectorAll('th');
        
        debugPrint('  Subject $i: Found ${allHeaders.length} header cells');
        
        if (allHeaders.isEmpty) {
          debugPrint('  Subject $i: Skipping - no headers');
          continue;
        }

        // First header is subject name and code - uses <br> tags
        final subjectCell = allHeaders[0];
        final subjectHtml = subjectCell.innerHtml;
        final subjectParts = subjectHtml.split(RegExp(r'<br\s*/?>', caseSensitive: false))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        
        String subjectName = 'Unknown Subject';
        String subjectCode = '';
        
        if (subjectParts.isNotEmpty) {
          subjectName = subjectParts[0].trim();
          if (subjectParts.length > 1) {
            subjectCode = subjectParts[1].replaceAll('(', '').replaceAll(')', '').trim();
          }
        }

        debugPrint('📚 Parsing: $subjectName ($subjectCode)');

        // Parse lecture headers (skip first column, stop before last 2 columns which are Total/%age)
        // Headers are in format: "1<br>01-07<br>3" (lecture number, date, period)
        final lectures = <LectureInfo>[];
        for (int j = 1; j < allHeaders.length - 2; j++) {
          final headerHtml = allHeaders[j].innerHtml;
          final parts = headerHtml.split(RegExp(r'<br\s*/?>', caseSensitive: false))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          
          if (j <= 3) {
            debugPrint('   🔍 Header $j HTML: "$headerHtml" -> parts: $parts');
          }
          
          if (parts.length >= 3) {
            lectures.add(LectureInfo(
              number: parts[0].trim(),
              date: parts[1].trim(),
              period: parts[2].trim(),
            ));
          } else if (parts.length == 1) {
            // Fallback: if no <br> tags, try to parse the single value
            lectures.add(LectureInfo(
              number: (j).toString(),
              date: '',
              period: parts[0].trim(),
            ));
          }
        }

        debugPrint('   📅 Lectures: ${lectures.length}');

        // Parse attendance data from tbody
        final dataRow = tbody.querySelector('tr');
        if (dataRow == null) {
          debugPrint('   ❌ No data row found in tbody');
          continue;
        }

        final cells = dataRow.querySelectorAll('td');
        debugPrint('   📊 Found ${cells.length} cells in data row');
        
        final attendanceData = <String>[];
        
        // Skip first cell (label "Attendance Count"), read until last 2 cells (total and percentage)
        for (int j = 1; j < cells.length - 2; j++) {
          final cellValue = cells[j].text.trim();
          attendanceData.add(cellValue);
        }

        debugPrint('   ✅ Attendance data points: ${attendanceData.length}');
        if (attendanceData.isNotEmpty) {
          debugPrint('   📈 Sample data: ${attendanceData.take(10).join(", ")}');
        }

        // Get total and percentage from last 2 cells
        final totalCell = cells.length >= 2 ? cells[cells.length - 2].text.trim() : '0/0';
        final percentCell = cells.length >= 1 ? cells[cells.length - 1].text.trim() : '0%';

        debugPrint('   📊 Total: $totalCell, Percentage: $percentCell');

        subjects.add(SubjectAttendanceRegister(
          name: subjectName,
          code: subjectCode,
          lectures: lectures,
          attendanceData: attendanceData,
          total: totalCell,
          percentage: percentCell,
        ));
      } catch (e) {
        debugPrint('❌ Error parsing subject at index $i: $e');
        debugPrint('❌ Stack trace: ${StackTrace.current}');
      }
    }

    setState(() {
      _subjects = subjects;
    });

    debugPrint('✅ Successfully parsed ${subjects.length} subjects');
    if (subjects.isEmpty) {
      debugPrint('⚠️ WARNING: No subjects were parsed!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Attendance Register',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _fetchAttendanceRegister,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator.adaptive(),
            SizedBox(height: 16),
            Text('Loading attendance register...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
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
                'Error Loading Register',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _fetchAttendanceRegister,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Attendance Register Found',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _subjects.length,
      itemBuilder: (context, index) {
        return _buildSubjectCard(_subjects[index]);
      },
    );
  }

  Widget _buildSubjectCard(SubjectAttendanceRegister subject) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percentage = double.tryParse(
      subject.percentage.replaceAll('%', '').trim()
    ) ?? 0.0;
    
    final isGood = percentage >= 75;
    final statusColor = isGood ? AppTheme.successColor : AppTheme.errorColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.all(16),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject.name,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subject.code.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subject.code,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subject.percentage,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  subject.total,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          children: [
            _buildAttendanceGrid(subject),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceGrid(SubjectAttendanceRegister subject) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem('P', 'Present', AppTheme.successColor),
              _buildLegendItem('A', 'Absent', AppTheme.errorColor),
              _buildLegendItem('DL', 'Duty Leave', Colors.blue),
              _buildLegendItem('ML', 'Medical Leave', Colors.orange),
            ],
          ),
        ),
        
        // Calendar Grid
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: _buildAttendanceCalendar(subject),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String code, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Center(
            child: Text(
              code,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceCalendar(SubjectAttendanceRegister subject) {
    // If we have lectures with date/period info, use them
    // Otherwise, fall back to just attendance data with index
    
    if (subject.lectures.isNotEmpty) {
      // Ensure we have matching data
      final itemCount = subject.lectures.length < subject.attendanceData.length 
          ? subject.lectures.length 
          : subject.attendanceData.length;

      // Build grid items
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(itemCount, (index) {
          final lecture = subject.lectures[index];
          final status = subject.attendanceData[index];
          
          return _buildCalendarDay(lecture, status);
        }),
      );
    } else {
      // Fallback: just show attendance data without lecture info
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(subject.attendanceData.length, (index) {
          final status = subject.attendanceData[index];
          final lecture = LectureInfo(
            number: (index + 1).toString(),
            date: '#${index + 1}',
            period: '-',
          );
          
          return _buildCalendarDay(lecture, status);
        }),
      );
    }
  }

  Widget _buildCalendarDay(LectureInfo lecture, String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Determine status type and color
    Color statusColor;
    String statusDisplay;
    IconData statusIcon;
    
    if (status == 'X') {
      // Absent
      statusColor = AppTheme.errorColor;
      statusDisplay = 'A';
      statusIcon = Icons.cancel;
    } else if (status == 'DL') {
      // Duty Leave
      statusColor = Colors.blue;
      statusDisplay = 'DL';
      statusIcon = Icons.work_outline;
    } else if (status == 'ML') {
      // Medical Leave
      statusColor = Colors.orange;
      statusDisplay = 'ML';
      statusIcon = Icons.medical_services_outlined;
    } else if (int.tryParse(status) != null) {
      // Present (number indicates attendance count)
      statusColor = AppTheme.successColor;
      statusDisplay = 'P';
      statusIcon = Icons.check_circle;
    } else {
      // Unknown
      statusColor = Colors.grey;
      statusDisplay = '?';
      statusIcon = Icons.help_outline;
    }

    return Container(
      width: 70,
      height: 85,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Date
          Text(
            lecture.date,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          
          // Period
          Text(
            'P${lecture.period}',
            style: GoogleFonts.inter(
              fontSize: 9,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 6),
          
          // Status indicator
          Container(
            width: 50,
            height: 28,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: statusColor,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  statusIcon,
                  size: 12,
                  color: statusColor,
                ),
                const SizedBox(width: 3),
                Text(
                  statusDisplay,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }
}

// Data models
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
