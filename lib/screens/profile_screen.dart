import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/api_config.dart';
import '../services/profile_cache_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';
import '../main.dart' show themeService;
import 'school_code_screen.dart';
import 'session_screen.dart';
import 'personal_info_screen.dart';
import 'report_card.dart';
import 'change_password_screen.dart';
import 'fee_receipts_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const ProfileScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  final ProfileCacheService _cacheService = ProfileCacheService();
  final UpdateService _updateService = UpdateService();
  
  // Student info
  String? _name;
  String? _profileImageUrl;
  String? _details;
  String? _gender; // Track gender for color theming
  
  // Parsed separate fields (from menu or detailed API)
  String? _parsedSemester;
  String? _parsedGroup;
  String? _parsedBatch;
  String? _parsedRollNo;

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _cacheAge = '';
  bool _isOffline = false;
  List<ProfileMenuItem> _menuItems = [];

  // Gender-based profile border color
  Color get _profileBorderColor => _gender?.toLowerCase() == 'female' 
      ? const Color(0xFFDB2777) // Professional Pink for girls
      : AppTheme.primaryColor; // Professional Blue for boys

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFromCacheAndFetch();
    });
  }

  /// Load cached data first, then fetch from API if needed
  Future<void> _loadFromCacheAndFetch() async {
    await _cacheService.init();
    
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    widget.userData['sessionId'].toString();
    
    debugPrint('🔍 Loading profile for userId=$userId, clientAbbr=$clientAbbr');
    
    // Try to load from cache first
    // Try to load from cache first
    final cached = await _cacheService.getCachedBasicProfile(userId, clientAbbr);
    
    debugPrint('📦 Cache result: ${cached != null ? "FOUND" : "NOT FOUND"}');
    if (cached != null) {
      debugPrint('📦 Cached name: ${cached.profile.name}');
      debugPrint('📦 Cached photo: ${cached.profile.profileImageUrl}');
      debugPrint('📦 Cached details: ${cached.profile.details}');
      debugPrint('📦 Cached menu items: ${cached.profile.menuItems.length}');
    }
    
    if (cached != null && mounted) {
      // Load cached data immediately - must set all state variables inside setState
      setState(() {
        _name = cached.profile.name;
        _profileImageUrl = cached.profile.profileImageUrl;
        _details = cached.profile.details;
        _gender = cached.profile.gender;
        _parsedSemester = cached.profile.parsedSemester;
        _parsedGroup = cached.profile.parsedGroup;
        _parsedBatch = cached.profile.parsedBatch;
        _parsedRollNo = cached.profile.parsedRollNo;
        
        // Restore menu items
        _menuItems = cached.profile.menuItems.map((name) => ProfileMenuItem(
          name: name,
          action: () => _handleMenuAction(name, null, null),
        )).toList();
        
        _isLoading = false;
        _cacheAge = _cacheService.getProfileCacheAgeString(userId, clientAbbr);
        _isOffline = false;
      });
      
      debugPrint('✅ Loaded profile from cache: name=$_name, photo=$_profileImageUrl');
      
      // Check for updates in background if cache is old
      if (!cached.isValid) {
        debugPrint('🔍 Cache is stale, refreshing in background...');
        _fetchProfileMenu(isBackgroundRefresh: true);
      }
    } else {
      // No cache, fetch from API
      debugPrint('📭 No cache found, fetching from API');
      _fetchProfileMenu();
    }
  }

  Future<void> _fetchProfileMenu({bool isBackgroundRefresh = false, bool isRefresh = false}) async {
    final userId = widget.userData['userId'].toString();
    final clientAbbr = widget.clientDetails['client_abbr'];
    widget.userData['sessionId'].toString();
    
    // Store existing data in case of refresh failure
    final existingName = _name;
    final existingPhoto = _profileImageUrl;
    final existingDetails = _details;
    final existingGender = _gender;
    final existingMenuItems = List<ProfileMenuItem>.from(_menuItems);
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
      final baseUrl = widget.clientDetails['baseUrl'];
      final data = await _apiService.getProfileMenu(baseUrl, clientAbbr);
      
      // 1. Try to get basic info from JSON first (fallback)
      String? jsonName = data['name'];
      String? jsonPhoto = data['photo'];
      
      // 2. Parse HTML content for detailed info
      String? htmlContent = data['content'];
      if (htmlContent == null) {
        for (var value in data.values) {
          if (value is String && value.contains('<div')) {
            htmlContent = value;
            break;
          }
        }
      }

      if (htmlContent != null) {
        _parseHtml(htmlContent);
      }
      
      // 3. Update state with parsed data or JSON fallback
      _name ??= jsonName;
      _profileImageUrl ??= jsonPhoto;
      
      // Cache the profile data
      await _cacheService.cacheBasicProfile(
        userId: userId,
        clientAbbr: clientAbbr,
        profile: CachedProfileBasic(
          name: _name,
          profileImageUrl: _profileImageUrl,
          details: _details,
          gender: _gender,
          parsedSemester: _parsedSemester,
          parsedGroup: _parsedGroup,
          parsedBatch: _parsedBatch,
          parsedRollNo: _parsedRollNo,
          menuItems: _menuItems.map((m) => m.name).toList(),
        ),
      );
      
      debugPrint('📦 Cached profile: name=$_name, photo=$_profileImageUrl, details=$_details');
      
      if (mounted) {
        setState(() {
          // Ensure all state variables are set for UI update
          _isLoading = false;
          _isRefreshing = false;
          _isOffline = false;
          _cacheAge = 'Just now';
        });
        
        if (isRefresh && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profile updated'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
      
      // Save semester info if parsed
      if (_parsedSemester != null || _parsedBatch != null || _parsedGroup != null) {
        await _apiService.saveSemesterInfo(
          semester: _parsedSemester,
          batch: _parsedBatch,
          group: _parsedGroup,
        );
        debugPrint('Saved semester info: Sem=$_parsedSemester, Batch=$_parsedBatch, Group=$_parsedGroup');
      }
      
      // Only fetch from detailed API if we are missing critical info
      if (_name == null || _name!.isEmpty || _profileImageUrl == null || _details == null) {
         debugPrint('Missing info, fetching from detailed API...');
         _fetchProfileDetails();
      } else {
        debugPrint('Profile info parsed successfully from Menu API.');
      }
      
    } catch (e) {
      debugPrint('Profile Screen - Error: $e');
      if (mounted) {
        // Check if it's a network error
        final errorStr = e.toString().toLowerCase();
        final isNetworkError = errorStr.contains('socket') || 
                               errorStr.contains('connection') || 
                               errorStr.contains('network') ||
                               errorStr.contains('timeout') ||
                               errorStr.contains('host');
        
        // If we had existing data, restore it
        if (existingName != null || existingMenuItems.isNotEmpty) {
          setState(() {
            _name = existingName;
            _profileImageUrl = existingPhoto;
            _details = existingDetails;
            _gender = existingGender;
            _menuItems = existingMenuItems;
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
          final cached = await _cacheService.getCachedBasicProfile(userId, clientAbbr);
          if (cached != null) {
            _name = cached.profile.name;
            _profileImageUrl = cached.profile.profileImageUrl;
            _details = cached.profile.details;
            _gender = cached.profile.gender;
            _menuItems = cached.profile.menuItems.map((name) => ProfileMenuItem(
              name: name,
              action: () => _handleMenuAction(name, null, null),
            )).toList();
            
            setState(() {
              _isLoading = false;
              _isRefreshing = false;
              _isOffline = isNetworkError;
              _cacheAge = _cacheService.getProfileCacheAgeString(userId, clientAbbr);
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
              _errorMessage = isNetworkError ? 'No internet connection' : 'Data not available';
              _isLoading = false;
              _isRefreshing = false;
              _isOffline = isNetworkError;
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
    }
  }

  /// Handle pull to refresh
  Future<void> _handleRefresh() async {
    await _fetchProfileMenu(isRefresh: true);
  }

  Future<void> _fetchProfileDetails() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId'].toString();
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

      // Parse HTML to get photo and name
      final document = html_parser.parse(htmlContent);
      
      // Get Photo
      final studentPhoto = document.querySelector('.ui-student-photo');
      if (studentPhoto != null) {
        final style = studentPhoto.attributes['style'] ?? '';
        final urlMatch = RegExp(r'url\((.*?)\)').firstMatch(style);
        if (urlMatch != null) {
          final photoUrl = urlMatch.group(1)?.replaceAll(r'\/', '/');
          setState(() {
            _profileImageUrl = photoUrl;
            debugPrint('Profile photo fetched from detailed API: $_profileImageUrl');
          });
        }
      }

      // Get Name and Details
      final studentInfo = document.querySelector('#student-info');
      if (studentInfo != null) {
        final titles = studentInfo.querySelectorAll('.ui-student-title');
        final values = studentInfo.querySelectorAll('.ui-student-value');
        
        String? fetchedName;
        String? fetchedRollNo;
        String? fetchedDegree;
        String? fetchedProgram;
        String? fetchedBatch;
        String? fetchedSemester;
        String? fetchedGroup;
        String? fetchedGender;

        for (int i = 0; i < titles.length && i < values.length; i++) {
          final title = titles[i].text.trim();
          final value = values[i].text.trim().replaceFirst(':', '').trim();
          
          debugPrint('Found Field: "$title" = "$value"');
          
          final lowerTitle = title.toLowerCase();
          
          if (lowerTitle == 'name') {
            fetchedName = value;
          } else if (lowerTitle.contains('roll no')) {
            fetchedRollNo = value;
          } else if (lowerTitle.contains('sem')) {
            fetchedSemester = value;
          } else if ((lowerTitle.contains('group') || lowerTitle.contains('section')) && !lowerTitle.contains('blood')) {
            fetchedGroup = value;
          } else if (lowerTitle.contains('gender') || lowerTitle.contains('sex')) {
            fetchedGender = value;
          }
        }
        
        // Also try to get batch/group from custom info
        final customInfo = document.querySelector('#student-custom-info');
        if (customInfo != null) {
           final cTitles = customInfo.querySelectorAll('.ui-student-title');
           final cValues = customInfo.querySelectorAll('.ui-student-value');
           for (int i = 0; i < cTitles.length && i < cValues.length; i++) {
             final title = cTitles[i].text.trim();
             final value = cValues[i].text.trim().replaceFirst(':', '').trim();
             final lowerTitle = title.toLowerCase();
             
             debugPrint('Found Custom Field: "$title" = "$value"');
             
             if (lowerTitle.contains('batch')) {
               fetchedBatch = value;
             } else if (lowerTitle.contains('degree')) {
               fetchedDegree = value;
             } else if (lowerTitle.contains('program')) {
               fetchedProgram = value;
             } else if (lowerTitle.contains('sem') && fetchedSemester == null) {
               fetchedSemester = value;
             } else if ((lowerTitle.contains('group') || lowerTitle.contains('section')) && !lowerTitle.contains('blood') && fetchedGroup == null) {
               fetchedGroup = value;
             }
           }
        }

        if (fetchedName != null && fetchedName.isNotEmpty) {
          setState(() {
            _name = fetchedName;
            
            // Set gender for color theming
            if (fetchedGender != null && fetchedGender.isNotEmpty) {
              _gender = fetchedGender;
            }
            
            // Construct details string if we have extra info
            List<String> detailsParts = [];
            if (fetchedRollNo != null) detailsParts.add('Roll No: $fetchedRollNo');
            
            // Combine Degree/Program/Batch intelligently
            String academicInfo = '';
            // Prefer Program, fallback to Degree, or combine if distinct
            if (fetchedProgram != null && fetchedProgram.isNotEmpty) {
              academicInfo = fetchedProgram;
              // Normalize strings to check for duplication (ignore case and special chars)
              String normProgram = fetchedProgram.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
              String normDegree = (fetchedDegree ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
              
              if (fetchedDegree != null && fetchedDegree.isNotEmpty && !normProgram.contains(normDegree)) {
                 academicInfo = '$fetchedDegree - $academicInfo';
              }
            } else if (fetchedDegree != null) {
              academicInfo = fetchedDegree;
            }
            
            // Add Semester and Group (prefer fetched, fallback to parsed from menu)
            List<String> extraInfo = [];
            String? displaySem = fetchedSemester ?? _parsedSemester;
            String? displayGroup = fetchedGroup ?? _parsedGroup;
            String? displayBatch = fetchedBatch ?? _parsedBatch;
            
            if (displaySem != null) extraInfo.add('Sem: $displaySem');
            if (displayGroup != null) extraInfo.add('Group: $displayGroup');
            if (displayBatch != null) extraInfo.add('Batch: $displayBatch');
            
            if (extraInfo.isNotEmpty) {
              if (academicInfo.isNotEmpty) academicInfo += '\n';
              academicInfo += extraInfo.join(' | ');
            }
            
            if (academicInfo.isNotEmpty) detailsParts.add(academicInfo);
            
            if (detailsParts.isNotEmpty) {
              _details = detailsParts.join('\n');
            }
            
            debugPrint('Profile details fetched from detailed API: $_name, $_details');
          });
        }
      }

      // Cache the complete profile data after fetching from detailed API
      await _cacheService.cacheBasicProfile(
        userId: userId,
        clientAbbr: clientAbbr,
        profile: CachedProfileBasic(
          name: _name,
          profileImageUrl: _profileImageUrl,
          details: _details,
          gender: _gender,
          parsedSemester: _parsedSemester,
          parsedGroup: _parsedGroup,
          parsedBatch: _parsedBatch,
          parsedRollNo: _parsedRollNo,
          menuItems: _menuItems.map((item) => item.name).toList(),
        ),
      );
      debugPrint('📦 Profile details cached after detailed API fetch: name=$_name, photo=$_profileImageUrl');

    } catch (e) {
      debugPrint('Error fetching profile details: $e');
    }
  }

  void _parseHtml(String htmlString) {
    // Unescape the HTML string if it contains escaped characters
    String cleanHtml = htmlString.replaceAll(r'\"', '"').replaceAll(r'\/', '/');
    // Remove any leading/trailing quotes if it was a JSON string
    if (cleanHtml.startsWith('"') && cleanHtml.endsWith('"')) {
      cleanHtml = cleanHtml.substring(1, cleanHtml.length - 1);
    }
    
    debugPrint('Cleaned HTML: $cleanHtml');
    final document = html_parser.parse(cleanHtml);

    // --- Extract Profile Header Info ---
    // Try multiple selectors to be robust
    var profileBox = document.querySelector('.grid-profile-box');
    
    if (profileBox != null) {
      debugPrint('Found .grid-profile-box');
      
      // 1. Photo URL
      // Look for the div with background-image
      final iconDiv = profileBox.querySelector('.grid-school-icon');
      if (iconDiv != null) {
        final style = iconDiv.attributes['style'] ?? '';
        debugPrint('Found icon div style: $style');
        
        // Regex to find url(...)
        final urlMatch = RegExp(r'url\((.*?)\)').firstMatch(style);
        if (urlMatch != null) {
          String url = urlMatch.group(1) ?? '';
          // Remove quotes if present
          url = url.replaceAll("'", "").replaceAll('"', "");
          
          if (url.isNotEmpty) {
            _profileImageUrl = url;
            debugPrint('Extracted Photo URL: $_profileImageUrl');
          }
        }
      } else {
        debugPrint('Could not find .grid-school-icon');
      }

      // 2. Name and Details
      final nameDivs = profileBox.querySelectorAll('.grid-name');
      debugPrint('Found ${nameDivs.length} .grid-name divs in Profile Box');
      debugPrint('Profile Box Text: ${profileBox.text}');
      
      if (nameDivs.isNotEmpty) {
        _name = nameDivs[0].text.trim();
        debugPrint('Extracted Name: $_name');
        
        if (nameDivs.length > 1) {
          // Format: "Roll. No: 2310990533, 2023-BE-CSE-5 SEM 5 SEM-G7-A"
          String rawDetails = nameDivs[1].text.trim();
          debugPrint('Raw Details String: $rawDetails');
          
          // Split by comma to separate Roll No from the rest
          List<String> parts = rawDetails.split(',');
          
          if (parts.isNotEmpty) {
            String rollNoPart = parts[0].trim(); // "Roll. No: 2310990533"
            // Extract just the number
            final rollMatch = RegExp(r'Roll\.?\s*No[:\.]?\s*(\d+)').firstMatch(rollNoPart);
            if (rollMatch != null) {
              _parsedRollNo = rollMatch.group(1);
            } else {
              _parsedRollNo = rollNoPart.replaceAll(RegExp(r'Roll\.?\s*No[:\.]?\s*'), '');
            }
            
            String academicPart = '';
            if (parts.length > 1) {
              academicPart = parts.sublist(1).join(',').trim(); // "2023-BE-CSE-5 SEM 5 SEM-G7-A"
              debugPrint('Academic Part to Parse: $academicPart');
              
              // Extract Batch (4 digits at start)
              final batchMatch = RegExp(r'^(\d{4})').firstMatch(academicPart);
              if (batchMatch != null) {
                _parsedBatch = batchMatch.group(1);
              }
              
              // Extract Semester (e.g., "5 SEM")
              final semMatch = RegExp(r'(\d+)\s*SEM').firstMatch(academicPart);
              if (semMatch != null) {
                _parsedSemester = semMatch.group(1);
              }
              
              // Extract Group (e.g., "G7-A" or "G7")
              // Look for G followed by digits, optionally hyphen and letters
              // Ensure it's not part of a larger word
              final groupMatch = RegExp(r'\b(G\d+(?:-[A-Z0-9]+)?)').firstMatch(academicPart);
              if (groupMatch != null) {
                _parsedGroup = groupMatch.group(1);
              }
              
              debugPrint('Parsed from Menu: Roll=$_parsedRollNo, Batch=$_parsedBatch, Sem=$_parsedSemester, Group=$_parsedGroup');
            }
            
            // Construct initial details from what we parsed
            List<String> finalDetails = [];
            if (_parsedRollNo != null) finalDetails.add('Roll No: $_parsedRollNo');
            
            // If we have the academic part, use it temporarily until detailed fetch updates it
            // Or construct a nice string now
            List<String> extra = [];
            if (_parsedSemester != null) extra.add('Sem: $_parsedSemester');
            if (_parsedGroup != null) extra.add('Group: $_parsedGroup');
            if (_parsedBatch != null) extra.add('Batch: $_parsedBatch');
            
            // Add the raw academic part if we couldn't parse specific fields well, 
            // or just the nice extra info
            if (extra.isNotEmpty) {
               // Try to extract the degree/program part (everything between Batch and Sem/Group)
               // This is hard to do perfectly with regex, so we might rely on detailed fetch for Degree name
               // For now, just show the raw string if detailed fetch hasn't run yet
               finalDetails.add(academicPart); 
            } else if (academicPart.isNotEmpty) {
               finalDetails.add(academicPart);
            }
            
            _details = finalDetails.join('\n');
          } else {
             _details = rawDetails;
          }
        }
      }
    } else {
      debugPrint('Could not find .grid-profile-box');
    }

    // --- Extract Menu Items ---
    final menuLinks = document.querySelectorAll('.grid-profile-menu a');
    _menuItems = menuLinks
        .where((link) {
          final nameDiv = link.querySelector('.grid-name');
          final name = nameDiv?.text.trim() ?? 'Unknown';
          // Filter out items we don't want
          final lowerName = name.toLowerCase();
          return lowerName != 'privacy' && 
                 lowerName != 'attendance' && 
                 lowerName != 'timetable' && 
                 lowerName != 'subjects';
        })
        .map((link) {
      final nameDiv = link.querySelector('.grid-name');
      final name = nameDiv?.text.trim() ?? 'Unknown';
      final href = link.attributes['href'];
      final onclick = link.attributes['onclick'];
      
      return ProfileMenuItem(
        name: name,
        action: () => _handleMenuAction(name, href, onclick),
      );
    }).toList();

    // Manually add Report Card item
    if (!_menuItems.any((item) => item.name.toLowerCase() == 'report card')) {
      _menuItems.insert(0, ProfileMenuItem(
        name: 'Report Card',
        action: () => _handleMenuAction('Report Card', null, null),
      ));
    }
    
    // Add Fee Receipts item after Report Card
    if (!_menuItems.any((item) => item.name.toLowerCase() == 'fee receipts')) {
      final reportCardIndex = _menuItems.indexWhere((item) => item.name.toLowerCase() == 'report card');
      final insertIndex = reportCardIndex >= 0 ? reportCardIndex + 1 : 1;
      
      _menuItems.insert(insertIndex, ProfileMenuItem(
        name: 'Fee Receipts',
        action: () => _handleMenuAction('Fee Receipts', null, null),
      ));
    }
    
    // Add Check for Updates item - only on mobile (not web)
    if (!kIsWeb && !_menuItems.any((item) => item.name.toLowerCase() == 'check for updates')) {
      // Find logout position and insert before it, or at end
      final logoutIndex = _menuItems.indexWhere((item) => item.name.toLowerCase() == 'logout');
      final insertIndex = logoutIndex >= 0 ? logoutIndex : _menuItems.length;
      
      _menuItems.insert(insertIndex, ProfileMenuItem(
        name: 'Check for Updates',
        action: () => _handleMenuAction('Check for Updates', null, null),
      ));
    }
    
    // Add About item
    if (!_menuItems.any((item) => item.name.toLowerCase() == 'about')) {
      // Find logout position and insert before it, or at end
      final logoutIndex = _menuItems.indexWhere((item) => item.name.toLowerCase() == 'logout');
      final insertIndex = logoutIndex >= 0 ? logoutIndex : _menuItems.length;
      
      _menuItems.insert(insertIndex, ProfileMenuItem(
        name: 'About',
        action: () => _handleMenuAction('About', null, null),
      ));
    }
  }

  Future<void> _handleMenuAction(String name, String? href, String? onclick) async {
    if (name.toLowerCase() == 'logout') {
      await _logout();
    } else if (name.toLowerCase() == 'change password') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChangePasswordScreen(
            clientDetails: widget.clientDetails,
            userData: widget.userData,
          ),
        ),
      );
    } else if (name.toLowerCase() == 'session') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SessionScreen(
            clientDetails: widget.clientDetails,
            userData: widget.userData,
          ),
        ),
      );
    } else if (name.toLowerCase() == 'report card' || name.toLowerCase() == 'results') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportCardScreen(
            clientDetails: widget.clientDetails,
            userData: widget.userData,
          ),
        ),
      );
    } else if (name.toLowerCase() == 'fee receipts') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FeeReceiptsScreen(
            clientDetails: widget.clientDetails,
            userData: widget.userData,
          ),
        ),
      );
    } else if (name.toLowerCase() == 'personal info' || name.toLowerCase() == 'profile') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PersonalInfoScreen(
            clientDetails: widget.clientDetails,
            userData: widget.userData,
          ),
        ),
      );
    } else if (name.toLowerCase() == 'check for updates') {
      await _checkForUpdatesManually();
    } else if (name.toLowerCase() == 'about') {
      _showAboutDialog();
    } else {
      // Default handling
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected: $name')),
      );
    }
  }

  /// Check for updates manually (force check)
  Future<void> _checkForUpdatesManually() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Initialize update service to get current version
      await _updateService.init();
      
      final update = await _updateService.checkForUpdate(force: true);
      
      if (!mounted) return;
      
      // Dismiss loading
      Navigator.of(context).pop();
      
      if (update != null) {
        await UpdateDialog.show(context, update);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Text('You\'re on the latest version (v${UpdateService.currentVersion})'),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to check for updates. Please try again.'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Show about dialog with app info
  void _showAboutDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Ensure version is fetched
    await _updateService.init();
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App icon
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.school_rounded,
                  size: 40,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ScholarDesk',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'v${UpdateService.currentVersion}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              
              // Made with love by Jatin
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Made with ',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  const Icon(
                    Icons.favorite,
                    size: 16,
                    color: Color(0xFFE53935),
                  ),
                  Text(
                    ' by Jatin',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Full Stack Developer',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              
              // Privacy notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.white.withOpacity(0.05) 
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No data is collected. All data is sent/received to official Chitkara servers only.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Portfolio link
              InkWell(
                onTap: () async {
                  final uri = Uri.parse('https://jatingupta.me');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.language_rounded,
                        size: 16,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'jatingupta.me',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Close button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _apiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SchoolCodeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: AppTheme.primaryColor,
                  backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 100,
                      floating: false,
                      pinned: true,
                      backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
                      surfaceTintColor: Colors.transparent,
                      actions: [
                        // Cache age indicator
                        if (_isRefreshing)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDark ? Colors.white70 : AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else if (_cacheAge.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (_isOffline ? AppTheme.warningColor : AppTheme.successColor).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _isOffline ? 'Offline' : _cacheAge,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _isOffline ? AppTheme.warningColor : AppTheme.successColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Theme Toggle
                        IconButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            themeService.toggleTheme();
                          },
                          icon: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: isDark ? AppTheme.warningColor : AppTheme.primaryColor,
                          ),
                          tooltip: isDark ? 'Light mode' : 'Dark mode',
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        title: Text(
                          'Profile',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(20.0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Profile Header
                          _buildProfileHeader().animate().fadeIn(duration: 600.ms).slideY(begin: 0.2),
                          const SizedBox(height: 24),
                          
                          // Menu Grid
                          _buildMenuGrid().animate().fadeIn(delay: 200.ms, duration: 600.ms).slideY(begin: 0.2),
                          const SizedBox(height: 20),
                        ]),
                      ),
                    ),
                  ],
                  ),
                ),
    );
  }

  Widget _buildProfileHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.transparent,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Profile Picture with error handling - make it clickable
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PersonalInfoScreen(
                      clientDetails: widget.clientDetails,
                      userData: widget.userData,
                    ),
                  ),
                );
              },
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _profileBorderColor, width: 3),
                    ),
                    child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                        ? CircleAvatar(
                            radius: 50,
                            backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                            child: ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: ApiConfig.proxyImageUrl(_profileImageUrl!),
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(_profileBorderColor),
                                  ),
                                ),
                                errorWidget: (context, url, error) {
                                  debugPrint('Error loading profile image: $error');
                                  return Icon(Icons.person, size: 50, color: _profileBorderColor);
                                },
                              ),
                            ),
                          )
                        : CircleAvatar(
                            radius: 50,
                            backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                            child: Icon(Icons.person, size: 50, color: _profileBorderColor),
                          ),
                  ),
                  // Tap hint overlay
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppTheme.darkCardColor : Colors.white, 
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _name ?? 'User',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (_details != null) ...[
              const SizedBox(height: 10),
              Text(
                _details!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: _menuItems.length,
      itemBuilder: (context, index) {
        final item = _menuItems[index];
        return _buildMenuItem(item);
      },
    );
  }

  Widget _buildMenuItem(ProfileMenuItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    IconData iconData;
    Color accentColor;

    switch (item.name.toLowerCase()) {
      case 'session':
        iconData = Icons.calendar_today_rounded;
        accentColor = AppTheme.secondaryColor;
        break;
      case 'report card':
      case 'results':
        iconData = Icons.assignment_turned_in_rounded;
        accentColor = AppTheme.successColor;
        break;
      case 'personal info':
      case 'profile':
        iconData = Icons.person_rounded;
        accentColor = AppTheme.accentColor;
        break;
      case 'change password':
        iconData = Icons.lock_reset_rounded;
        accentColor = AppTheme.warningColor;
        break;
      case 'check for updates':
        iconData = Icons.system_update_rounded;
        accentColor = AppTheme.accentColor;
        break;
      case 'about':
        iconData = Icons.info_rounded;
        accentColor = AppTheme.tertiaryColor;
        break;
      case 'logout':
        iconData = Icons.logout_rounded;
        accentColor = AppTheme.errorColor;
        break;
      default:
        iconData = Icons.grid_view_rounded;
        accentColor = AppTheme.tertiaryColor;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: item.action,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(iconData, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Text(
                    item.name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileMenuItem {
  final String name;
  final VoidCallback action;

  ProfileMenuItem({required this.name, required this.action});
}
