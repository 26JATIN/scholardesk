import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// Minimal update dialog with clean design
class UpdateDialog extends StatefulWidget {
  final AppUpdate update;
  final VoidCallback? onSkip;
  final VoidCallback? onDismiss;

  const UpdateDialog({
    super.key,
    required this.update,
    this.onSkip,
    this.onDismiss,
  });

  /// Show the update dialog
  static Future<void> show(
    BuildContext context, 
    AppUpdate update, {
    VoidCallback? onSkip,
    VoidCallback? onDismiss,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(
        update: update,
        onSkip: onSkip,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> with SingleTickerProviderStateMixin {
  final UpdateService _updateService = UpdateService();
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _downloadError;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Download the update and install it
  Future<void> _downloadAndInstall() async {
    HapticFeedback.mediumImpact();
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadError = null;
    });

    try {
      final filePath = await _updateService.downloadUpdate(
        widget.update,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (!mounted) return;

      if (filePath != null) {
        // Show installing state
        setState(() {
          _downloadProgress = 1.0;
        });
        
        // Small delay to show 100% progress
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Install the APK using UpdateService
        final installed = await _updateService.installApk(filePath);
        
        if (!mounted) return;
        
        if (installed) {
          // Close the dialog - installation prompt is shown by system
          Navigator.of(context).pop();
        } else {
          // Fallback to browser if installation fails
          setState(() {
            _isDownloading = false;
            _downloadError = 'Could not open installer';
          });
          await Future.delayed(const Duration(seconds: 2));
          await _openInBrowser();
        }
      } else {
        setState(() {
          _isDownloading = false;
          _downloadError = 'Download failed';
        });
      }
    } catch (e) {
      debugPrint('Error during download/install: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadError = 'Something went wrong';
        });
      }
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.update.htmlUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _skipUpdate() {
    HapticFeedback.lightImpact();
    _updateService.skipVersion(widget.update.version);
    widget.onSkip?.call();
    Navigator.of(context).pop();
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    widget.onDismiss?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Minimal Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.rocket_launch_rounded,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Update Available',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'v${UpdateService.currentVersion} → v${widget.update.version}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isDownloading)
                      IconButton(
                        onPressed: _dismiss,
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                          size: 20,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // What's New section - compact
                      _buildWhatsNew(isDark),
                      
                      // Error message
                      if (_downloadError != null) ...[
                        const SizedBox(height: 12),
                        _buildErrorMessage(isDark),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Download progress or buttons
              _isDownloading 
                  ? _buildDownloadProgress(isDark)
                  : _buildButtons(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhatsNew(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "What's New",
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 160),
          child: SingleChildScrollView(
            child: _buildReleaseNotes(isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildReleaseNotes(bool isDark) {
    final notes = widget.update.releaseNotes;
    final lines = notes.split('\n');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) return const SizedBox(height: 6);
        
        // Check if it's a bullet point
        if (trimmedLine.startsWith('-') || trimmedLine.startsWith('•') || trimmedLine.startsWith('*')) {
          final content = trimmedLine.substring(1).trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 7),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    content,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? Colors.grey.shade300 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        
        // Check if it's a header (starts with # or ##)
        if (trimmedLine.startsWith('#')) {
          final headerContent = trimmedLine.replaceAll('#', '').trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 4),
            child: Text(
              headerContent,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          );
        }
        
        // Regular text
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            trimmedLine,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: isDark ? Colors.grey.shade300 : Colors.black87,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorMessage(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppTheme.errorColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _downloadError!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.errorColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(bool isDark) {
    final percentage = (_downloadProgress * 100).toInt();
    final isComplete = _downloadProgress >= 1.0;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isComplete ? 'Installing...' : 'Downloading...',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              Text(
                isComplete ? '✓' : '$percentage%',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isComplete ? AppTheme.successColor : AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: isDark 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isComplete ? AppTheme.successColor : AppTheme.primaryColor,
              ),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          // Update Now button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _downloadAndInstall,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Update Now',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Secondary buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _skipUpdate,
                child: Text(
                  'Skip',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ),
              Text(
                '•',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                ),
              ),
              TextButton(
                onPressed: _dismiss,
                child: Text(
                  'Later',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
