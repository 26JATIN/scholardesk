import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'apply_leave_screen.dart';

class MedicalLeaveScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;
  final VoidCallback? onBackPressed;

  const MedicalLeaveScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
    this.onBackPressed,
  });

  @override
  State<MedicalLeaveScreen> createState() => _MedicalLeaveScreenState();
}

class _MedicalLeaveScreenState extends State<MedicalLeaveScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _leaveHistory = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchLeaveHistory();
  }

  Future<void> _fetchLeaveHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('🔄 Fetching leave history...');
      await _apiService.ensureCookiesLoaded();
      
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final sessionId = widget.userData['sessionId']?.toString() ?? '18';
      final userId = widget.userData['userId']?.toString() ?? '15260';
      
      debugPrint('📡 API Request:');
      debugPrint('  BaseURL: $baseUrl');
      debugPrint('  Client: $clientAbbr');
      debugPrint('  UserID: $userId');
      debugPrint('  SessionID: $sessionId');
      
      final htmlContent = await _apiService.getLeaveHistory(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
      );

      debugPrint('✅ Received response (${htmlContent.length} bytes)');

      if (mounted) {
        final parsedLeaves = _parseLeaveHistory(htmlContent);
        setState(() {
          _leaveHistory = parsedLeaves;
          _isLoading = false;
        });
        
        if (_leaveHistory.isEmpty) {
          debugPrint('⚠️ No leave records found');
        } else {
          debugPrint('✅ Loaded ${_leaveHistory.length} leave records');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching leave history: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load leave history\n${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _parseLeaveHistory(String htmlContent) {
    debugPrint('📄 Parsing leave history HTML...');
    debugPrint('HTML Content length: ${htmlContent.length}');
    
    final List<Map<String, dynamic>> leaves = [];
    
    try {
      // Split content by monthly sections
      final sections = htmlContent.split('show-monthly-history-section');
      debugPrint('Found ${sections.length} sections');
      
      for (var section in sections) {
        if (section.trim().isEmpty) continue;
        
        // Extract month
        final monthMatch = RegExp(r'<span>([A-Za-z]+,\s*\d{4})</span>').firstMatch(section);
        final currentMonth = monthMatch?.group(1) ?? '';
        
        // Extract all leaves in this section
        // Updated regex: make status- class optional (pending leaves don't have it)
        final leaveWrapRegex = RegExp(
          r'navigateToLeaveDetail\((\d+)\).*?<p>(.*?)</p>.*?<span>(.*?)</span>.*?<div[^>]*class="[^"]*leave-status(?:\s+status-(\w+))?[^"]*"[^>]*>\s*<span[^>]*>([^<]+)</span>',
          multiLine: true,
          dotAll: true,
        );
        
        final leaveMatches = leaveWrapRegex.allMatches(section);
        
        for (var match in leaveMatches) {
          final leaveId = match.group(1) ?? '';
          final leaveType = match.group(2)?.trim() ?? '';
          final dateRange = match.group(3)?.trim() ?? '';
          // Group 4 is now optional (status class without 'status-' prefix)
          final statusClass = match.group(4)?.toLowerCase() ?? '';
          final statusText = match.group(5)?.trim() ?? '';
          
          // If no status class found, derive it from status text (for Pending leaves)
          final effectiveStatusClass = statusClass.isEmpty 
              ? statusText.toLowerCase() 
              : statusClass;
          
          // Debug: show the actual matched HTML fragment
          final matchedText = match.group(0);
          debugPrint('🔍 Raw HTML match: ${matchedText?.substring(0, matchedText.length > 200 ? 200 : matchedText.length)}...');
          debugPrint('📋 Parsed leave: ID=$leaveId, Type=$leaveType, Status=$statusText, StatusClass=$effectiveStatusClass');
          
          if (leaveId.isNotEmpty) {
            leaves.add({
              'id': leaveId,
              'type': leaveType,
              'dateRange': dateRange,
              'status': statusText,
              'statusClass': effectiveStatusClass,
              'month': currentMonth,
            });
          }
        }
      }
      
      debugPrint('✅ Parsed ${leaves.length} leave records');
      
      // If no leaves found, try alternative parsing method
      if (leaves.isEmpty) {
        debugPrint('⚠️ No leaves found with primary method, trying alternative...');
        
        // Alternative: match leave-his-wrap divs
        final altRegex = RegExp(
          r'<div class="leave-his-wrap"[^>]*onclick="navigateToLeaveDetail\((\d+)\);">(.*?)</div>\s*</div>',
          multiLine: true,
          dotAll: true,
        );
        
        final altMatches = altRegex.allMatches(htmlContent);
        
        for (var match in altMatches) {
          final leaveId = match.group(1) ?? '';
          final content = match.group(2) ?? '';
          
          // Extract info from content
          final typeMatch = RegExp(r'<p>(.*?)</p>').firstMatch(content);
          final dateMatch = RegExp(r'<span>([\w,\s-]+)</span>').firstMatch(content);
          // Make status- prefix optional in alternative parsing too
          final statusMatch = RegExp(r'(?:status-)?(\w+).*?<span>(\w+)</span>', dotAll: true).firstMatch(content);
          
          final statusClass = statusMatch?.group(1)?.toLowerCase() ?? '';
          final statusText = statusMatch?.group(2)?.trim() ?? 'Unknown';
          
          // If status class looks like it's part of the status text (for pending), use status text
          final effectiveStatusClass = statusClass == statusText.toLowerCase() 
              ? statusClass 
              : (statusClass.isEmpty ? statusText.toLowerCase() : statusClass);
          
          if (leaveId.isNotEmpty) {
            leaves.add({
              'id': leaveId,
              'type': typeMatch?.group(1)?.trim() ?? 'Leave',
              'dateRange': dateMatch?.group(1)?.trim() ?? '',
              'status': statusText,
              'statusClass': effectiveStatusClass,
              'month': 'Recent',
            });
          }
        }
        
        debugPrint('✅ Alternative parsing found ${leaves.length} leave records');
      }
      
    } catch (e) {
      debugPrint('❌ Error parsing leave history: $e');
    }
    
    return leaves;
  }

  Map<String, List<Map<String, dynamic>>> _groupLeavesByMonth() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    
    for (var leave in _leaveHistory) {
      final month = leave['month'] ?? 'Unknown';
      if (!grouped.containsKey(month)) {
        grouped[month] = [];
      }
      grouped[month]!.add(leave);
    }
    
    return grouped;
  }

  Color _getStatusColor(String status, bool isDark) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppTheme.successColor;
      case 'cancelled':
        return AppTheme.errorColor;
      case 'pending':
        return AppTheme.warningColor;
      default:
        return isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ApplyLeaveScreen(
                clientDetails: widget.clientDetails,
                userData: widget.userData,
              ),
            ),
          ).then((_) => _fetchLeaveHistory()); // Refresh when returning
        },
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Apply Leave',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchLeaveHistory();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : Colors.black87,
                size: 20,
              ),
              onPressed: () {
                if (widget.onBackPressed != null) {
                  widget.onBackPressed!();
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
              title: Text(
                'Leave History',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _isLoading
                ? _buildLoadingState()
                : _errorMessage != null
                    ? _buildErrorState()
                    : _buildLeaveHistory(isDark),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.all(32.0),
      child: Center(
        child: CircularProgressIndicator.adaptive(),
      ),
    );
  }

  Widget _buildErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Error Loading Leave History',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'An error occurred',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _fetchLeaveHistory,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveHistory(bool isDark) {
    if (_leaveHistory.isEmpty) {
      return _buildEmptyState(isDark);
    }

    final groupedLeaves = _groupLeavesByMonth();
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: groupedLeaves.entries.map((entry) {
          return _buildMonthSection(entry.key, entry.value, isDark);
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.medical_services_outlined,
            size: 64,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No Leave History',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You haven\'t applied for any leaves yet',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSection(String month, List<Map<String, dynamic>> leaves, bool isDark) {
    return Column(
      children: [
        _buildMonthHeader(month, isDark),
        const SizedBox(height: 16),
        ...leaves.map((leave) => _buildLeaveCard(leave, isDark)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMonthHeader(String month, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkElevatedColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  month,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveCard(Map<String, dynamic> leave, bool isDark) {
    final statusColor = _getStatusColor(leave['status'] ?? '', isDark);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Navigate to leave detail page
            _showLeaveDetails(leave);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Leave type icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getLeaveIcon(leave['type'] ?? ''),
                    color: statusColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Leave info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leave['type'] ?? 'Leave',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            size: 14,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              leave['dateRange'] ?? '',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    leave['status'] ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getLeaveIcon(String leaveType) {
    if (leaveType.toLowerCase().contains('medical')) {
      return Icons.local_hospital_rounded;
    } else if (leaveType.toLowerCase().contains('duty')) {
      return Icons.work_outline_rounded;
    } else if (leaveType.toLowerCase().contains('casual')) {
      return Icons.beach_access_rounded;
    }
    return Icons.event_note_rounded;
  }

  Future<void> _showLeaveDetails(Map<String, dynamic> leave) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: 16),
              Text(
                'Loading details...',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // Fetch detailed leave information
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final sessionId = widget.userData['sessionId']?.toString() ?? '18';
      final userId = widget.userData['userId']?.toString() ?? '15260';
      final roleId = widget.userData['roleId']?.toString() ?? '4';
      final leaveId = leave['id']?.toString() ?? '';
      
      debugPrint('🔍 Fetching leave detail for ID: $leaveId');
      
      final detailsHtml = await _apiService.getLeaveDetail(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        leaveId: leaveId,
      );

      debugPrint('✅ Received leave detail (${detailsHtml.length} bytes)');

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Parse and show details
      final details = _parseLeaveDetails(detailsHtml);
      
      debugPrint('📋 Parsed ${details.length} detail fields');
      
      if (mounted) {
        if (details.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No details available for this leave'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        } else {
          _showLeaveDetailsBottomSheet(details, isDark, leave);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching leave details: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load leave details'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Map<String, String> _parseLeaveDetails(String htmlContent) {
    final details = <String, String>{};
    
    try {
      // Extract key-value pairs from the HTML
      final infoRegex = RegExp(
        r'<div class="applied-type">\s*<span>(.*?)</span>\s*</div>\s*<div class="applied-content">\s*<span>(.*?)</span>',
        multiLine: true,
        dotAll: true,
      );
      
      final matches = infoRegex.allMatches(htmlContent);
      
      // First pass: collect all fields
      for (var match in matches) {
        final key = match.group(1)?.trim() ?? '';
        final value = match.group(2)?.trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) {
          debugPrint('📋 Detail field: $key = $value');
          details[key] = value;
        }
      }
      
      // Second pass: clean up based on status
      final status = details['Status']?.toLowerCase() ?? '';
      debugPrint('🔍 Status detected: $status');
      
      // If status is cancelled, remove "Approved by" and "Approved on" fields
      // (they shouldn't appear for cancelled leaves)
      if (status.contains('cancel')) {
        details.removeWhere((key, value) => 
          key.toLowerCase().contains('approved')
        );
        debugPrint('🧹 Removed approval fields for cancelled status');
      }
      
      // If status is pending, remove both approved and cancelled fields
      if (status.contains('pending')) {
        details.removeWhere((key, value) => 
          key.toLowerCase().contains('approved') || 
          key.toLowerCase().contains('cancel')
        );
        debugPrint('🧹 Removed approval/cancellation fields for pending status');
      }
      
      debugPrint('✅ Parsed ${details.length} detail fields');
    } catch (e) {
      debugPrint('❌ Error parsing leave details: $e');
    }
    
    return details;
  }

  void _showLeaveDetailsBottomSheet(Map<String, String> details, bool isDark, Map<String, dynamic> leave) {
    // Get actual status from detail - look for Status field in details
    String actualStatus = leave['status'] ?? 'Unknown';
    for (var entry in details.entries) {
      if (entry.key.toLowerCase().contains('status')) {
        actualStatus = entry.value;
        break;
      }
    }
    
    // Check if leave can be cancelled (not approved, rejected, or already cancelled)
    final canCancel = !actualStatus.toLowerCase().contains('approved') &&
                      !actualStatus.toLowerCase().contains('reject') &&
                      !actualStatus.toLowerCase().contains('cancelled');
    
    final leaveId = leave['id']?.toString() ?? '';
    
    debugPrint('📋 Leave status from detail: $actualStatus, Can cancel: $canCancel');
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle - tappable area for dismiss
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    // Title
                    Text(
                      'Leave Details',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Details
                    ...details.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildDetailRow(
                          entry.key,
                          entry.value,
                          _getIconForField(entry.key),
                          isDark,
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                    // Buttons
                    if (canCancel) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _cancelLeave(leaveId);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade600,
                            side: BorderSide(color: Colors.red.shade600),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(
                            'Cancel Request',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelLeave(String leaveId) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Cancel Leave Request?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to cancel this leave request? This action cannot be undone.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: GoogleFonts.inter()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: Text('Yes, Cancel', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId']?.toString() ?? '15260';
      
      final success = await _apiService.cancelLeave(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        leaveId: leaveId,
        userId: userId,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Leave request cancelled successfully',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
          
          // Refresh leave history
          _fetchLeaveHistory();
        } else {
          _showErrorSnackBar('Failed to cancel leave request');
        }
      }
    } catch (e) {
      debugPrint('❌ Cancel failed: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading
        _showErrorSnackBar('Error: ${e.toString().replaceAll('Exception:', '').trim()}');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  IconData _getIconForField(String fieldName) {
    final field = fieldName.toLowerCase();
    if (field.contains('type')) return Icons.medical_services_outlined;
    if (field.contains('category')) return Icons.category_outlined;
    if (field.contains('event') || field.contains('title')) return Icons.event_outlined;
    if (field.contains('from') || field.contains('to') || field.contains('date')) return Icons.date_range_rounded;
    if (field.contains('time') || field.contains('slot')) return Icons.access_time_rounded;
    if (field.contains('lecture')) return Icons.school_outlined;
    if (field.contains('status')) return Icons.info_outline_rounded;
    if (field.contains('cancelled')) return Icons.cancel_outlined;
    if (field.contains('approved')) return Icons.check_circle_outline_rounded;
    return Icons.info_outline_rounded;
  }

  Widget _buildDetailRow(String label, String value, IconData icon, bool isDark) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppTheme.primaryColor,
          ),
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
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
