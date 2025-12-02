import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import '../theme/app_theme.dart';

class SessionScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const SessionScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _sessions = [];

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  Future<void> _fetchSessions() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();

      final sessions = await _apiService.getAllSession(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
      );

      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _changeSession(Map<String, dynamic> session) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Update local userData
      final newUserData = Map<String, dynamic>.from(widget.userData);
      newUserData['sessionId'] = session['sessionId'];
      newUserData['sessionName'] = session['sessionName']; // Optional, if used elsewhere

      // Persist changes
      await _apiService.saveSession(widget.clientDetails, newUserData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session changed to ${session['sessionName']}'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        // Navigate to HomeScreen to reload everything with new session
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              clientDetails: widget.clientDetails,
              userData: newUserData,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to change session: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSessionId = widget.userData['sessionId'].toString();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Session: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FE),
        body: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              expandedHeight: 140,
              floating: false,
              pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Select Session',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
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
                            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'Error: $_errorMessage',
                              style: GoogleFonts.inter(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final session = _sessions[index];
                            final isSelected = session['sessionId'].toString() == currentSessionId;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: isSelected
                                    ? Border.all(color: AppTheme.primaryColor, width: 2.5)
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected 
                                        ? AppTheme.primaryColor.withOpacity(0.2)
                                        : Colors.black.withOpacity(0.06),
                                    blurRadius: isSelected ? 15 : 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  onTap: isSelected ? null : () => _changeSession(session),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            gradient: isSelected
                                                ? AppTheme.primaryGradient
                                                : LinearGradient(
                                                    colors: [Colors.grey.shade200, Colors.grey.shade300],
                                                  ),
                                            borderRadius: BorderRadius.circular(14),
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: AppTheme.primaryColor.withOpacity(0.3),
                                                      blurRadius: 8,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Icon(
                                            Icons.calendar_month_rounded,
                                            color: isSelected ? Colors.white : Colors.grey.shade600,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                session['sessionName'] ?? 'Unknown Session',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 16,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  color: isSelected ? AppTheme.primaryColor : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.event_rounded,
                                                    size: 14,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      '${session['startDate']} - ${session['endDate']}',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        color: Colors.grey.shade600,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              gradient: AppTheme.successGradient,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.successColor.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ).animate().fadeIn(delay: (50 * index).ms, duration: 400.ms).slideY(begin: 0.2);
                          },
                          childCount: _sessions.length,
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}
