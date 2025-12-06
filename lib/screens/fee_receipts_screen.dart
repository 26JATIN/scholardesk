import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/fee_receipts_cache_service.dart';
import '../theme/app_theme.dart';

/// Model class for Fee Receipt
class FeeReceipt {
  final String receiptNo;
  final double amount;
  final DateTime paidOn;
  final String cycle;
  final String? semester;
  final String? pdfUrl;
  final String? receiptId;

  FeeReceipt({
    required this.receiptNo,
    required this.amount,
    required this.paidOn,
    required this.cycle,
    this.semester,
    this.pdfUrl,
    this.receiptId,
  });

  String get formattedAmount {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  String get formattedDate {
    return DateFormat('dd MMM yyyy').format(paidOn);
  }

  String get dateString {
    return DateFormat('dd-MM-yyyy').format(paidOn);
  }

  /// Extract semester number from cycle string
  String? get extractedSemester {
    if (semester != null) return semester;
    
    // Try to extract semester from cycle
    final patterns = [
      RegExp(r'(\d+)(?:ST|ND|RD|TH)?\s*SEM', caseSensitive: false),
      RegExp(r'SEM\s*(\d+)', caseSensitive: false),
      RegExp(r'SEMESTER\s*(\d+)', caseSensitive: false),
    ];
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(cycle);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
}

class FeeReceiptsScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const FeeReceiptsScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<FeeReceiptsScreen> createState() => _FeeReceiptsScreenState();
}

class _FeeReceiptsScreenState extends State<FeeReceiptsScreen> {
  final ApiService _apiService = ApiService();
  final FeeReceiptsCacheService _cacheService = FeeReceiptsCacheService();
  
  List<FeeReceipt> _receipts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  double _totalPaid = 0;
  String _cacheAge = '';
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadFromCacheAndFetch();
  }

  /// Load cached data first, then fetch from API if needed
  Future<void> _loadFromCacheAndFetch() async {
    await _cacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    
    // Try to load from cache first
    final cached = await _cacheService.getCachedReceipts(userId, clientAbbr);
    
    if (cached != null && cached.receipts.isNotEmpty) {
      // Load cached items immediately
      _receipts = cached.receipts.map((r) => FeeReceipt(
        receiptNo: r.receiptNo,
        amount: r.amount,
        paidOn: _parseDate(r.paidOnStr),
        cycle: r.cycle,
        semester: r.semester,
        pdfUrl: r.pdfUrl,
        receiptId: r.receiptId,
      )).toList();
      
      setState(() {
        _totalPaid = cached.totalPaid;
        _isLoading = false;
        _cacheAge = _cacheService.getCacheAgeString(userId, clientAbbr);
        _isOffline = false;
      });
      
      debugPrint('📦 Loaded ${cached.receipts.length} receipts from cache');
      
      // Check for updates in background if cache is old
      if (!cached.isValid) {
        debugPrint('🔍 Cache is stale, refreshing in background...');
        _fetchReceipts(isBackgroundRefresh: true);
      }
    } else {
      // No cache, fetch from API
      debugPrint('📭 No cache found, fetching from API');
      _fetchReceipts();
    }
  }

  DateTime _parseDate(String dateStr) {
    try {
      return DateFormat('dd-MM-yyyy').parse(dateStr);
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<void> _fetchReceipts({bool isBackgroundRefresh = false, bool isRefresh = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    
    // Store existing data in case of refresh failure
    final existingReceipts = List<FeeReceipt>.from(_receipts);
    final existingTotal = _totalPaid;
    final existingCacheAge = _cacheAge;
    
    if (isRefresh) {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    } else if (!isBackgroundRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      await _apiService.ensureCookiesLoaded();
      
      final baseUrl = widget.clientDetails['baseUrl'];
      final sessionId = widget.userData['sessionId']?.toString() ?? '';
      final roleId = widget.userData['roleId']?.toString() ?? '4';
      
      debugPrint('📡 Fetching fee receipts...');
      
      final htmlContent = await _apiService.getReceiptDetails(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
      );

      debugPrint('✅ Received response (${htmlContent.length} bytes)');

      if (mounted) {
        final parsedReceipts = _parseReceipts(htmlContent);
        
        // Calculate total
        double total = 0;
        for (var receipt in parsedReceipts) {
          total += receipt.amount;
        }
        
        // Cache the results
        if (parsedReceipts.isNotEmpty) {
          await _cacheService.cacheReceipts(
            userId: userId,
            clientAbbr: clientAbbr,
            receipts: parsedReceipts.map((r) => CachedFeeReceipt(
              receiptNo: r.receiptNo,
              amount: r.amount,
              paidOnStr: r.dateString,
              cycle: r.cycle,
              semester: r.extractedSemester,
              pdfUrl: r.pdfUrl,
              receiptId: r.receiptId,
            )).toList(),
            totalPaid: total,
          );
        }
        
        setState(() {
          _receipts = parsedReceipts;
          _totalPaid = total;
          _isLoading = false;
          _isRefreshing = false;
          _isOffline = false;
          _cacheAge = 'Just now';
        });
        
        if (isRefresh && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Fee receipts updated'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
        
        debugPrint('✅ Parsed ${_receipts.length} receipts, Total: ₹$_totalPaid');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching receipts: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        final isNetworkError = errorStr.contains('socket') || 
                               errorStr.contains('connection') || 
                               errorStr.contains('network') ||
                               errorStr.contains('timeout') ||
                               errorStr.contains('host');
        
        // If we had existing data, restore it
        if (existingReceipts.isNotEmpty) {
          setState(() {
            _receipts = existingReceipts;
            _totalPaid = existingTotal;
            _isLoading = false;
            _isRefreshing = false;
            _isOffline = isNetworkError;
            _cacheAge = existingCacheAge;
          });
          
          if (isRefresh) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isNetworkError 
                    ? 'No internet connection' 
                    : 'Failed to refresh'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppTheme.warningColor,
              ),
            );
          }
        } else {
          setState(() {
            _errorMessage = isNetworkError 
                ? 'No internet connection' 
                : 'Failed to load fee receipts';
            _isLoading = false;
            _isRefreshing = false;
            _isOffline = isNetworkError;
          });
        }
      }
    }
  }

  /// Handle pull to refresh
  Future<void> _handleRefresh() async {
    await _fetchReceipts(isRefresh: true);
  }

  List<FeeReceipt> _parseReceipts(String htmlContent) {
    final List<FeeReceipt> receipts = [];
    
    try {
      // Clean the HTML
      String cleanHtml = htmlContent
          .replaceAll(r'\"', '"')
          .replaceAll(r'\/', '/')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '\t');
      
      if (cleanHtml.startsWith('"') && cleanHtml.endsWith('"')) {
        cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
      }
      
      final document = html_parser.parse(cleanHtml);
      
      // Find all receipt wraps
      final receiptWraps = document.querySelectorAll('.receipt-wrap');
      debugPrint('Found ${receiptWraps.length} receipt-wrap elements');
      
      for (var wrap in receiptWraps) {
        try {
          // Extract receipt number
          final receiptNoEl = wrap.querySelector('.receipt-no');
          String receiptNo = receiptNoEl?.text.trim() ?? '';
          receiptNo = receiptNo.replaceAll('Receipt No.', '').trim();
          
          // Extract amount
          final amountEl = wrap.querySelector('.receipt-amount');
          String amountStr = amountEl?.text.trim() ?? '0';
          amountStr = amountStr.replaceAll('Rs.', '').replaceAll(',', '').trim();
          double amount = double.tryParse(amountStr) ?? 0;
          
          // Extract date
          final dateEl = wrap.querySelector('.receipt-date');
          String dateStr = dateEl?.text.trim() ?? '';
          dateStr = dateStr.replaceAll('Paid On:', '').trim();
          DateTime paidOn;
          try {
            paidOn = DateFormat('dd-MM-yyyy').parse(dateStr);
          } catch (_) {
            paidOn = DateTime.now();
          }
          
          // Extract cycle
          final cycleEl = wrap.querySelector('.receipt-cycle-value');
          String cycle = cycleEl?.text.trim() ?? 'Unknown';
          
          // Extract PDF URL and Receipt ID from script or printPdfDiv
          String? pdfUrl;
          String? receiptId;
          
          final printDivId = wrap.querySelector('[id^="printPdfDiv_"]')?.id;
          if (printDivId != null) {
            receiptId = printDivId.replaceAll('printPdfDiv_', '');
          }
          
          // Try to extract PDF URL from script content
          final scripts = wrap.querySelectorAll('script');
          for (var script in scripts) {
            final scriptContent = script.text;
            final urlMatch = RegExp(r"printFromURL\('([^']+)'").firstMatch(scriptContent);
            if (urlMatch != null) {
              pdfUrl = urlMatch.group(1);
              break;
            }
          }
          
          if (receiptNo.isNotEmpty && amount > 0) {
            receipts.add(FeeReceipt(
              receiptNo: receiptNo,
              amount: amount,
              paidOn: paidOn,
              cycle: cycle,
              pdfUrl: pdfUrl,
              receiptId: receiptId,
            ));
          }
        } catch (e) {
          debugPrint('Error parsing receipt: $e');
        }
      }
      
      // Sort by date (newest first)
      receipts.sort((a, b) => b.paidOn.compareTo(a.paidOn));
      
    } catch (e) {
      debugPrint('Error parsing receipts HTML: $e');
    }
    
    return receipts;
  }

  Future<void> _downloadReceipt(FeeReceipt receipt) async {
    if (receipt.pdfUrl == null && receipt.receiptId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF not available for this receipt'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      
      String url = receipt.pdfUrl ?? 
          'https://$clientAbbr.$baseUrl/mobile/printReceiptApp/${receipt.receiptId}';
      
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Cannot open URL');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open receipt: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white60 : Colors.black54;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppTheme.primaryColor,
        backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // App Bar
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: textColor,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
                title: Text(
                  'Fee Receipts',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              actions: [
                if (_cacheAge.isNotEmpty && !_isLoading)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isOffline 
                            ? AppTheme.warningColor.withOpacity(0.2)
                            : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isOffline)
                            const Icon(
                              Icons.cloud_off_rounded,
                              size: 12,
                              color: AppTheme.warningColor,
                            ),
                          if (_isOffline) const SizedBox(width: 4),
                          Text(
                            _cacheAge,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _isOffline 
                                  ? AppTheme.warningColor
                                  : subtextColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isRefreshing)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
            
            // Content
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator.adaptive(),
                ),
              )
            else if (_errorMessage != null && _receipts.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isOffline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                        size: 64,
                        color: subtextColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(
                          color: subtextColor,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _fetchReceipts(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_receipts.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 64,
                        color: subtextColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No fee receipts found',
                        style: GoogleFonts.inter(
                          color: subtextColor,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Summary Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: _buildSummaryCard(isDark, colorScheme),
                ),
              ),
              
              // Receipts List
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final receipt = _receipts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildReceiptCard(receipt, isDark, colorScheme, index),
                      );
                    },
                    childCount: _receipts.length,
                  ),
                ),
              ),
              
              // Bottom padding
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(bool isDark, ColorScheme colorScheme) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Fee Paid',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatter.format(_totalPaid),
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.receipt_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_receipts.length} Payment${_receipts.length != 1 ? 's' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildReceiptCard(FeeReceipt receipt, bool isDark, ColorScheme colorScheme, int index) {
    final cardColor = isDark ? AppTheme.darkCardColor : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white60 : Colors.black54;
    
    // Color coding based on amount
    Color amountColor;
    if (receipt.amount >= 100000) {
      amountColor = AppTheme.primaryColor;
    } else if (receipt.amount >= 50000) {
      amountColor = AppTheme.successColor;
    } else if (receipt.amount >= 10000) {
      amountColor = AppTheme.accentColor;
    } else {
      amountColor = isDark ? Colors.white70 : AppTheme.tertiaryColor;
    }
    
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showReceiptDetails(receipt),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _downloadReceipt(receipt);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Receipt Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: amountColor.withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: amountColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Receipt Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receipt.receiptNo,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 12,
                                color: subtextColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                receipt.formattedDate,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: subtextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Amount
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          receipt.formattedAmount,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: amountColor,
                          ),
                        ),
                        if (receipt.extractedSemester != null)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: amountColor.withOpacity(isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Sem ${receipt.extractedSemester}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: amountColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                
                // Cycle Info
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? Colors.white.withOpacity(0.05) 
                        : Colors.grey.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.school_rounded,
                        size: 14,
                        color: subtextColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          receipt.cycle,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: subtextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (receipt.pdfUrl != null || receipt.receiptId != null)
                        Icon(
                          Icons.download_rounded,
                          size: 16,
                          color: subtextColor,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.1, end: 0);
  }

  void _showReceiptDetails(FeeReceipt receipt) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white60 : Colors.black54;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCardColor : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Title
            Text(
              'Receipt Details',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 24),
            
            // Details
            _buildDetailRow('Receipt No', receipt.receiptNo, textColor, subtextColor),
            _buildDetailRow('Amount', receipt.formattedAmount, textColor, subtextColor),
            _buildDetailRow('Paid On', receipt.formattedDate, textColor, subtextColor),
            _buildDetailRow('Fee Cycle', receipt.cycle, textColor, subtextColor),
            if (receipt.extractedSemester != null)
              _buildDetailRow('Semester', receipt.extractedSemester!, textColor, subtextColor),
            
            const SizedBox(height: 24),
            
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: receipt.receiptNo));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Receipt number copied'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (receipt.pdfUrl != null || receipt.receiptId != null)
                        ? () {
                            Navigator.pop(context);
                            _downloadReceipt(receipt);
                          }
                        : null,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            // Bottom padding for safe area
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: subtextColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
