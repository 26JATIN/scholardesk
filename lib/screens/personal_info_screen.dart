import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/profile_cache_service.dart';
import '../theme/app_theme.dart';

class PersonalInfoScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const PersonalInfoScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final ProfileCacheService _cacheService = ProfileCacheService();
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _cacheAge = '';
  bool _isOffline = false;
  TabController? _tabController;
  
  // Student info
  Map<String, String> _studentDetails = {};
  Map<String, String> _customFields = {};
  Map<String, String> _addressInfo = {};
  String? _gender; // Track gender for color theming
  
  // Parent info
  String? _fatherPhotoUrl;
  Map<String, String> _fatherDetails = {};
  String? _motherPhotoUrl;
  Map<String, String> _motherDetails = {};

  // Gender-based colors
  Color get _studentPrimaryColor => _gender?.toLowerCase() == 'female' 
      ? const Color(0xFFDB2777) // Professional Pink for girls
      : const Color(0xFF1E40AF); // Professional Blue for boys
  
  Color get _additionalInfoColor => const Color(0xFFDC2626); // Red for additional info

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromCacheAndFetch();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  /// Load cached data first, then fetch from API if needed
  Future<void> _loadFromCacheAndFetch() async {
    await _cacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    final sessionId = widget.userData['sessionId'].toString();
    
    // Try to load from cache first (NEVER EXPIRES)
    final cached = await _cacheService.getCachedPersonalInfo(userId, clientAbbr, sessionId);
    
    if (cached != null) {
      // Load cached data immediately
      _studentDetails = cached.info.studentDetails;
      _customFields = cached.info.customFields;
      _addressInfo = cached.info.addressInfo;
      _gender = cached.info.gender;
      _fatherPhotoUrl = cached.info.fatherPhotoUrl;
      _fatherDetails = cached.info.fatherDetails;
      _motherPhotoUrl = cached.info.motherPhotoUrl;
      _motherDetails = cached.info.motherDetails;
      
      setState(() {
        _isLoading = false;
        _cacheAge = _cacheService.getPersonalInfoCacheAgeString(userId, clientAbbr, sessionId);
        _isOffline = false;
      });
      
      debugPrint('📦 Loaded personal info from cache (NEVER EXPIRES)');
      
      // Personal info cache never expires, but we can still allow refresh
    } else {
      // No cache, fetch from API
      debugPrint('📭 No cache found, fetching from API');
      _fetchPersonalInfo();
    }
  }

  Future<void> _fetchPersonalInfo({bool isRefresh = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    
    // Store existing data in case of refresh failure
    final existingStudentDetails = Map<String, String>.from(_studentDetails);
    final existingCustomFields = Map<String, String>.from(_customFields);
    final existingAddressInfo = Map<String, String>.from(_addressInfo);
    final existingGender = _gender;
    final existingFatherPhotoUrl = _fatherPhotoUrl;
    final existingFatherDetails = Map<String, String>.from(_fatherDetails);
    final existingMotherPhotoUrl = _motherPhotoUrl;
    final existingMotherDetails = Map<String, String>.from(_motherDetails);
    final existingCacheAge = _cacheAge;
    
    if (isRefresh) {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
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
        commonPageId: '5', // Personal Info page ID
      );

      _parseHtml(htmlContent);
      
      // Cache the personal info (NEVER EXPIRES)
      await _cacheService.cachePersonalInfo(
        userId: userId,
        clientAbbr: clientAbbr,
        sessionId: sessionId,
        info: CachedPersonalInfo(
          studentDetails: _studentDetails,
          customFields: _customFields,
          addressInfo: _addressInfo,
          gender: _gender,
          fatherPhotoUrl: _fatherPhotoUrl,
          fatherDetails: _fatherDetails,
          motherPhotoUrl: _motherPhotoUrl,
          motherDetails: _motherDetails,
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _isOffline = false;
          _cacheAge = 'Just now';
        });
        
        if (isRefresh && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Personal info updated'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Personal Info Screen - Error: $e');
      if (mounted) {
        // Check if it's a network error
        final errorStr = e.toString().toLowerCase();
        final isNetworkError = errorStr.contains('socket') || 
                               errorStr.contains('connection') || 
                               errorStr.contains('network') ||
                               errorStr.contains('timeout') ||
                               errorStr.contains('host');
        
        // If we had existing data (refresh case), restore it
        if (existingStudentDetails.isNotEmpty) {
          setState(() {
            _studentDetails = existingStudentDetails;
            _customFields = existingCustomFields;
            _addressInfo = existingAddressInfo;
            _gender = existingGender;
            _fatherPhotoUrl = existingFatherPhotoUrl;
            _fatherDetails = existingFatherDetails;
            _motherPhotoUrl = existingMotherPhotoUrl;
            _motherDetails = existingMotherDetails;
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
          // Try to load from cache as fallback
          final sessionId = widget.userData['sessionId'].toString();
          final cached = await _cacheService.getCachedPersonalInfo(userId, clientAbbr, sessionId);
          if (cached != null) {
            _studentDetails = cached.info.studentDetails;
            _customFields = cached.info.customFields;
            _addressInfo = cached.info.addressInfo;
            _gender = cached.info.gender;
            _fatherPhotoUrl = cached.info.fatherPhotoUrl;
            _fatherDetails = cached.info.fatherDetails;
            _motherPhotoUrl = cached.info.motherPhotoUrl;
            _motherDetails = cached.info.motherDetails;
            
            setState(() {
              _isLoading = false;
              _isRefreshing = false;
              _isOffline = isNetworkError;
              _cacheAge = _cacheService.getPersonalInfoCacheAgeString(userId, clientAbbr, sessionId);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isNetworkError 
                    ? 'No internet - Showing cached data ($_cacheAge)'
                    : 'Error - Showing cached data'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppTheme.warningColor,
              ),
            );
          } else {
            setState(() {
              _errorMessage = e.toString().replaceAll('Exception: ', '');
              _isLoading = false;
              _isRefreshing = false;
            });
          }
        }
      }
    }
  }

  /// Handle pull to refresh
  Future<void> _handleRefresh() async {
    await _fetchPersonalInfo(isRefresh: true);
  }

  void _parseHtml(String htmlString) {
    final document = html_parser.parse(htmlString);
    
    // Parse Student Photo
    final studentPhoto = document.querySelector('.ui-student-photo');
    if (studentPhoto != null) {
      final style = studentPhoto.attributes['style'] ?? '';
      final urlMatch = RegExp(r'url\((.*?)\)').firstMatch(style);
      if (urlMatch != null) {
      }
    }

    // Parse Student Details
    final studentInfo = document.querySelector('#student-info');
    if (studentInfo != null) {
      _studentDetails = _parseDetailsSection(studentInfo);
      // Extract gender from student details
      for (var entry in _studentDetails.entries) {
        if (entry.key.toLowerCase().contains('gender') || 
            entry.key.toLowerCase().contains('sex')) {
          _gender = entry.value;
          break;
        }
      }
    }

    // Parse Custom Fields
    final customInfo = document.querySelector('#student-custom-info');
    if (customInfo != null) {
      _customFields = _parseDetailsSection(customInfo);
    }

    // Parse Address Info
    final addressInfo = document.querySelector('#address-info');
    if (addressInfo != null) {
      _addressInfo = _parseDetailsSection(addressInfo);
    }

    // Parse Father's Details
    final fatherInfo = document.querySelector('#parent-info');
    if (fatherInfo != null) {
      final fatherPhoto = fatherInfo.querySelector('.ui-father-photo');
      if (fatherPhoto != null) {
        final style = fatherPhoto.attributes['style'] ?? '';
        final urlMatch = RegExp(r'url\((.*?)\)').firstMatch(style);
        if (urlMatch != null) {
          _fatherPhotoUrl = urlMatch.group(1)?.replaceAll(r'\/', '/');
        }
      }
      
      // Get father's details from the first ui-profile-det after heading "Father's Details"
      final headings = fatherInfo.querySelectorAll('.heading');
      for (var heading in headings) {
        if (heading.text.contains("Father's Details")) {
          var nextElement = heading.nextElementSibling;
          while (nextElement != null && !nextElement.classes.contains('ui-profile-det')) {
            nextElement = nextElement.nextElementSibling;
          }
          if (nextElement != null) {
            _fatherDetails = _parseDetailsFromElement(nextElement);
            break;
          }
        }
      }
    }

    // Parse Mother's Details
    if (fatherInfo != null) {
      final motherPhoto = fatherInfo.querySelectorAll('.ui-father-photo');
      if (motherPhoto.length > 1) {
        final style = motherPhoto[1].attributes['style'] ?? '';
        final urlMatch = RegExp(r'url\((.*?)\)').firstMatch(style);
        if (urlMatch != null) {
          _motherPhotoUrl = urlMatch.group(1)?.replaceAll(r'\/', '/');
        }
      }
      
      final headings = fatherInfo.querySelectorAll('.heading');
      for (var heading in headings) {
        if (heading.text.contains("Mother's Details")) {
          var nextElement = heading.nextElementSibling;
          while (nextElement != null && !nextElement.classes.contains('ui-profile-det')) {
            nextElement = nextElement.nextElementSibling;
          }
          if (nextElement != null) {
            _motherDetails = _parseDetailsFromElement(nextElement);
            break;
          }
        }
      }
    }
  }

  Map<String, String> _parseDetailsSection(element) {
    final profileDet = element.querySelector('.ui-profile-det');
    if (profileDet == null) return {};
    return _parseDetailsFromElement(profileDet);
  }

  Map<String, String> _parseDetailsFromElement(element) {
    final details = <String, String>{};
    final titles = element.querySelectorAll('.ui-student-title');
    final values = element.querySelectorAll('.ui-student-value');

    for (int i = 0; i < titles.length && i < values.length; i++) {
      final title = titles[i].text.trim();
      final value = values[i].text.trim().replaceFirst(':', '').trim();
      if (title.isNotEmpty && value.isNotEmpty) {
        details[title] = value;
      }
    }
    return details;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Personal Info: Predictive back gesture completed');
        }
      },
      child: Scaffold(
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
                              'Personal Info',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 100),
                          ),
                          actions: [
                            if (_isRefreshing)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: isDark ? Colors.white70 : AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            if (_isOffline && !_isRefreshing)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.cloud_off_rounded,
                                      size: 14,
                                      color: Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Cached',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_cacheAge.isNotEmpty && !_isRefreshing)
                              Container(
                                margin: const EdgeInsets.only(right: 16),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isDark ? Colors.green.shade900 : Colors.green.shade50).withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.save_rounded,
                                      size: 14,
                                      color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _cacheAge,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _StickyTabBarDelegate(
                            TabBar(
                              controller: _tabController,
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
                              tabs: const [
                                Tab(text: 'Student'),
                                Tab(text: 'Info'),
                                Tab(text: 'Address'),
                                Tab(text: 'Parents'),
                              ],
                            ),
                            isDark: isDark,
                          ),
                        ),
                      ];
                    },
                    body: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Student Details
                        RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: AppTheme.primaryColor,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildStudentSection(isDark),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                        
                        // Tab 2: Additional Info
                        RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: AppTheme.primaryColor,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildCustomFieldsSection(isDark),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                        
                        // Tab 3: Address
                        RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: AppTheme.primaryColor,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildAddressSection(isDark),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                        
                        // Tab 4: Parents
                        RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: AppTheme.primaryColor,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildParentSection('Father', _fatherPhotoUrl, _fatherDetails, isDark),
                                const SizedBox(height: 16),
                                _buildParentSection('Mother', _motherPhotoUrl, _motherDetails, isDark),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildStudentSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _studentPrimaryColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  "Student's Details",
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _studentDetails.entries
                  .map((e) => _buildDetailRow(e.key, e.value, isDark))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFieldsSection(bool isDark) {
    if (_customFields.isEmpty) return const SizedBox.shrink();
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _additionalInfoColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  "Additional Information",
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _customFields.entries
                  .map((e) => _buildDetailRow(e.key, e.value, isDark))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection(bool isDark) {
    if (_addressInfo.isEmpty) return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off_outlined, size: 64, color: isDark ? Colors.grey.shade600 : Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No address information found',
            style: GoogleFonts.inter(color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
          ),
        ],
      ),
    );
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.warningColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  "Permanent Address",
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _addressInfo.entries
                  .map((e) => _buildDetailRow(e.key, e.value, isDark))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentSection(String parentType, String? photoUrl, Map<String, String> details, bool isDark) {
    if (details.isEmpty) {
      if (parentType == 'Father' && _fatherDetails.isEmpty && _motherDetails.isEmpty) {
         return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.family_restroom_outlined, size: 64, color: isDark ? Colors.grey.shade600 : Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'No parent information found',
                style: GoogleFonts.inter(color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }
    
    final headerColor = parentType == 'Father' 
        ? AppTheme.primaryColor
        : const Color(0xFFDB2777); // Professional Pink for Mother
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.family_restroom_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  "$parentType's Details",
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photoUrl != null && !photoUrl.contains('prof-img.svg'))
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Icon(
                          Icons.person, 
                          size: 30, 
                          color: isDark ? Colors.grey.shade500 : Colors.grey,
                        ),
                        errorWidget: (context, url, error) {
                          return Icon(Icons.person, size: 30, color: isDark ? Colors.grey.shade500 : Colors.grey);
                        },
                      ),
                    ),
                  ),
                if (photoUrl != null && !photoUrl.contains('prof-img.svg'))
                  const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: details.entries
                        .map((e) => _buildDetailRow(e.key, e.value, isDark))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkElevatedColor : const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
