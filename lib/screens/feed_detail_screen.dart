import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../main.dart' show themeService;

class FeedDetailScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;
  final String itemId;
  final String itemType;
  final String title;

  const FeedDetailScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
    required this.itemId,
    required this.itemType,
    required this.title,
  });

  @override
  State<FeedDetailScreen> createState() => _FeedDetailScreenState();
}

class _FeedDetailScreenState extends State<FeedDetailScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _detailData;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
      final roleId = widget.userData['roleId'].toString();
      final sessionId = widget.userData['sessionId'].toString();
      final appKey = widget.userData['apiKey'].toString();

      final response = await _apiService.getAppItemDetail(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        roleId: roleId,
        sessionId: sessionId,
        appKey: appKey,
        itemId: widget.itemId,
        itemType: widget.itemType,
      );

      if (mounted) {
        setState(() {
          _detailData = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final isNetworkError = e.toString().toLowerCase().contains('socket') ||
                               e.toString().toLowerCase().contains('connection') ||
                               e.toString().toLowerCase().contains('network');
                               
        setState(() {
          _errorMessage = isNetworkError ? 'No internet connection' : 'Data not available';
          _isLoading = false;
        });
        
        if (isNetworkError) {
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



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Feed Detail: Predictive back gesture completed');
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
        body: CustomScrollView(
          slivers: [
            // Modern App Bar
            SliverAppBar.large(
              expandedHeight: 200,
              floating: false,
              pinned: true,
              backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_rounded, 
                  color: isDark ? Colors.white : Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  onPressed: () => themeService.toggleTheme(),
                ),
              ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Cicular',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              background: Container(
                color: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor.withOpacity(0.1),
                child: Center(
                  child: Icon(
                    Icons.campaign_rounded,
                    size: 80,
                    color: isDark 
                        ? AppTheme.primaryColor.withOpacity(0.3) 
                        : AppTheme.primaryColor.withOpacity(0.2),
                  ),
                ),
              ),
            ),
          ),

          // Content
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
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
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.grey.shade400 : Colors.black54,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_detailData == null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No details found',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark 
                            ? AppTheme.primaryColor.withOpacity(0.15) 
                            : AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: GoogleFonts.outfit(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 400.ms).slideY(
                          begin: 0.2,
                          duration: 400.ms,
                        ),
                    
                    const SizedBox(height: 24),
                    
                    // Content Section
                    _buildContent(),
                    
                    const SizedBox(height: 24),
                    
                    // Attachments Section
                    _buildAttachments(),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_detailData!.containsKey('circular')) {
      final circularData = _detailData!['circular'];
      
      // Handle both List and String types
      String htmlContent = '';
      
      if (circularData is List && circularData.isNotEmpty) {
        final circular = circularData[0];
        htmlContent = circular['noticeText'] ?? '';
      } else if (circularData is String) {
        htmlContent = circularData;
      }
      
      if (htmlContent.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Details',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Content Card
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCardColor : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: isDark ? null : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: HtmlWidget(
                htmlContent,
                textStyle: GoogleFonts.inter(
                  color: isDark ? Colors.grey.shade300 : Colors.black87,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(
                  begin: 0.2,
                  delay: 200.ms,
                  duration: 400.ms,
                ),
          ],
        );
      }
    }
    return const SizedBox.shrink();
  }

  Future<void> _downloadAttachment(String storedAs) async {
    // Show loading snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Preparing download...',
                style: GoogleFonts.inter(),
              ),
            ],
          ),
          backgroundColor: AppTheme.primaryColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];

      final response = await _apiService.getAppAttachmentDetails(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        itemId: widget.itemId,
        itemType: widget.itemType,
        fileSystem: storedAs,
      );

      final downloadUrl = response['filePath'];
      debugPrint('Download URL: $downloadUrl');

      if (downloadUrl != null) {
        final uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Opening file...',
                        style: GoogleFonts.inter(),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppTheme.successColor,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          debugPrint('Could not launch URL: $downloadUrl');
          // Try launching anyway as a fallback
          try {
             await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (e) {
             if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Could not open file',
                          style: GoogleFonts.inter(),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Download URL not available',
                      style: GoogleFonts.inter(),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Error: ${e.toString().replaceAll('Exception: ', '')}',
                    style: GoogleFonts.inter(),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Widget _buildAttachments() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_detailData!.containsKey('circularAttachment')) {
      final attachmentData = _detailData!['circularAttachment'];
      
      // Handle both List and other types
      List<dynamic> attachments = [];
      
      if (attachmentData is List) {
        attachments = attachmentData;
      } else if (attachmentData != null) {
        // If it's not a list but exists, wrap it in a list
        attachments = [attachmentData];
      }
      
      if (attachments.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Attachments',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${attachments.length}',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Attachment Cards
            ...attachments.asMap().entries.map((entry) {
              final index = entry.key;
              final attachment = entry.value;
              final fileName = attachment['attachment'] ?? 'Unknown File';
              final storedAs = attachment['attachmentStoredAs'];
              
              // Determine file type icon and color
              IconData fileIcon = Icons.insert_drive_file_rounded;
              Color iconColor = AppTheme.primaryColor;
              
              if (fileName.toLowerCase().endsWith('.pdf')) {
                fileIcon = Icons.picture_as_pdf_rounded;
                iconColor = AppTheme.errorColor;
              } else if (fileName.toLowerCase().endsWith('.doc') || 
                         fileName.toLowerCase().endsWith('.docx')) {
                fileIcon = Icons.description_rounded;
                iconColor = AppTheme.primaryColor;
              } else if (fileName.toLowerCase().endsWith('.jpg') || 
                         fileName.toLowerCase().endsWith('.png') ||
                         fileName.toLowerCase().endsWith('.jpeg')) {
                fileIcon = Icons.image_rounded;
                iconColor = AppTheme.successColor;
              } else if (fileName.toLowerCase().endsWith('.zip') || 
                         fileName.toLowerCase().endsWith('.rar')) {
                fileIcon = Icons.folder_zip_rounded;
                iconColor = AppTheme.warningColor;
              }
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCardColor : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isDark ? null : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: storedAs != null ? () => _downloadAttachment(storedAs) : null,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // File Icon
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              fileIcon,
                              color: iconColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          
                          // File Name
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to download',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Download Button
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.download_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ).animate(delay: ((index + 1) * 100).ms)
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: 0.2, duration: 400.ms);
            }),
          ],
        );
      }
    }
    return const SizedBox.shrink();
  }
}
