import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// Beautiful update dialog with changelog and download progress
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
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
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
            _downloadError = 'Could not open installer. Opening download page...';
          });
          await Future.delayed(const Duration(seconds: 2));
          await _openInBrowser();
        }
      } else {
        setState(() {
          _isDownloading = false;
          _downloadError = 'Download failed. Please try again or download from browser.';
        });
      }
    } catch (e) {
      debugPrint('Error during download/install: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadError = 'An error occurred. Please try again.';
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
    final screenSize = MediaQuery.of(context).size;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: screenSize.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(isDark),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Version info
                      _buildVersionInfo(isDark),
                      const SizedBox(height: 20),
                      
                      // What's New section
                      _buildWhatsNew(isDark),
                      
                      // Error message
                      if (_downloadError != null) ...[
                        const SizedBox(height: 16),
                        _buildErrorMessage(),
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

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.accentColor,
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update Available',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A new version is ready to install',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isDownloading ? null : _dismiss,
            icon: Icon(
              Icons.close_rounded,
              color: Colors.white.withOpacity(_isDownloading ? 0.3 : 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionInfo(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.05) 
            : AppTheme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.1) 
              : AppTheme.primaryColor.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'v${widget.update.version}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 16,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'v${UpdateService.currentVersion}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.update.formattedDate,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.update.formattedSize,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
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

  Widget _buildWhatsNew(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: AppTheme.accentColor,
            ),
            const SizedBox(width: 8),
            Text(
              "What's New",
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
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
        if (trimmedLine.isEmpty) return const SizedBox(height: 8);
        
        // Check if it's a bullet point
        if (trimmedLine.startsWith('-') || trimmedLine.startsWith('•') || trimmedLine.startsWith('*')) {
          final content = trimmedLine.substring(1).trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    content,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
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
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              headerContent,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          );
        }
        
        // Regular text
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            trimmedLine,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: isDark ? Colors.grey.shade300 : Colors.black87,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: AppTheme.errorColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _downloadError!,
              style: GoogleFonts.inter(
                fontSize: 13,
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
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.03) 
            : Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (isComplete)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  if (isComplete) const SizedBox(width: 8),
                  Text(
                    isComplete ? 'Installing...' : 'Downloading...',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              Text(
                isComplete ? 'Complete' : '$percentage%',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isComplete ? AppTheme.successColor : AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: isDark 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isComplete ? AppTheme.successColor : AppTheme.primaryColor,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isComplete 
                ? 'Opening installer...' 
                : 'Please wait while the update is being downloaded',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.03) 
            : Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          // Update Now button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _downloadAndInstall,
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(
                'Download & Install',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Secondary buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _skipUpdate,
                  child: Text(
                    'Skip Version',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade300,
              ),
              Expanded(
                child: TextButton(
                  onPressed: _dismiss,
                  child: Text(
                    'Later',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
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
