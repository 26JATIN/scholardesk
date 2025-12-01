import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'school_code_screen.dart';
import 'attendance_screen.dart';
import 'session_screen.dart';
import 'timetable_screen.dart';
import 'personal_info_screen.dart';

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
  
  // Student info
  String? _name;
  String? _profileImageUrl;
  String? _details;
  
  // Parsed separate fields (from menu or detailed API)
  String? _parsedSemester;
  String? _parsedGroup;
  String? _parsedBatch;
  String? _parsedRollNo;

  bool _isLoading = true;
  String? _errorMessage;
  List<ProfileMenuItem> _menuItems = [];

  @override
  void initState() {
    super.initState();
    _fetchProfileMenu();
  }

  Future<void> _fetchProfileMenu() async {
    try {
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
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
      setState(() {
        // If HTML parsing didn't find a name/photo, use JSON values
        _name ??= jsonName;
        _profileImageUrl ??= jsonPhoto;
        
        debugPrint('Final Profile Name (Menu): $_name');
        debugPrint('Final Profile Photo (Menu): $_profileImageUrl');
        
        _isLoading = false;
      });
      
      // Only fetch from detailed API if we are missing critical info
      if (_name == null || _name!.isEmpty || _profileImageUrl == null || _details == null) {
         debugPrint('Missing info, fetching from detailed API...');
         _fetchProfileDetails();
      } else {
        debugPrint('Profile info parsed successfully from Menu API.');
      }
      
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
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
            
            // Construct details string if we have extra info
            List<String> detailsParts = [];
            if (fetchedRollNo != null) detailsParts.add('Roll No: $fetchedRollNo');
            
            // Combine Degree/Program/Batch intelligently
            String academicInfo = '';
            // Prefer Program, fallback to Degree, or combine if distinct
            if (fetchedProgram != null && fetchedProgram!.isNotEmpty) {
              academicInfo = fetchedProgram!;
              // Normalize strings to check for duplication (ignore case and special chars)
              String normProgram = fetchedProgram!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
              String normDegree = (fetchedDegree ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
              
              if (fetchedDegree != null && fetchedDegree!.isNotEmpty && !normProgram.contains(normDegree)) {
                 academicInfo = '$fetchedDegree - $academicInfo';
              }
            } else if (fetchedDegree != null) {
              academicInfo = fetchedDegree!;
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
    _menuItems = menuLinks.map((link) {
      final nameDiv = link.querySelector('.grid-name');
      final name = nameDiv?.text.trim() ?? 'Unknown';
      final href = link.attributes['href'];
      final onclick = link.attributes['onclick'];
      
      return ProfileMenuItem(
        name: name,
        action: () => _handleMenuAction(name, href, onclick),
      );
    }).toList();

    // Manually add Attendance item if not already present
    if (!_menuItems.any((item) => item.name.toLowerCase() == 'attendance')) {
      _menuItems.insert(0, ProfileMenuItem(
        name: 'Attendance',
        action: () => _handleMenuAction('Attendance', null, null),
      ));
    }

    // Manually add Timetable item if not already present
    if (!_menuItems.any((item) => item.name.toLowerCase() == 'timetable')) {
      _menuItems.insert(1, ProfileMenuItem(
        name: 'Timetable',
        action: () => _handleMenuAction('Timetable', null, null),
      ));
    }
  }

  Future<void> _handleMenuAction(String name, String? href, String? onclick) async {
    if (name.toLowerCase() == 'attendance') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AttendanceScreen(
            clientDetails: widget.clientDetails,
            userData: widget.userData,
          ),
        ),
      );
    } else if (name.toLowerCase() == 'logout') {
      await _logout();
    } else if (name.toLowerCase() == 'privacy') {
       // Handle Privacy Policy - usually opens a URL
       // The onclick has window.open("PRIVACY_POLICY", ...)
       // We can try to construct the URL or just show a placeholder for now
       // Assuming standard privacy policy URL structure or just ignoring for now as per plan
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Privacy Policy not implemented yet')),
      );
    } else if (name.toLowerCase() == 'change password') {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Change Password not implemented yet')),
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
    } else if (name.toLowerCase() == 'timetable') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TimetableScreen(
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
    } else {
      // Default handling
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected: $name')),
      );
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text('Error: $_errorMessage'))
              : CustomScrollView(
                  slivers: [
                    SliverAppBar.large(
                      expandedHeight: 120,
                      floating: false,
                      pinned: true,
                      flexibleSpace: FlexibleSpaceBar(
                        title: const Text(
                          'Profile',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
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
                      border: Border.all(color: const Color(0xFF6366F1), width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                        ? CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey.shade100,
                            child: ClipOval(
                              child: Image.network(
                                _profileImageUrl!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  debugPrint('Error loading profile image: $error');
                                  return const Icon(Icons.person, size: 50, color: Color(0xFF6366F1));
                                },
                              ),
                            ),
                          )
                        : CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey.shade100,
                            child: const Icon(Icons.person, size: 50, color: Color(0xFF6366F1)),
                          ),
                  ),
                  // Tap hint overlay
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEC4899).withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
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
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (_details != null) ...[
              const SizedBox(height: 10),
              Text(
                _details!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
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
    IconData iconData;
    List<Color> gradientColors;

    switch (item.name.toLowerCase()) {
      case 'attendance':
        iconData = Icons.class_rounded;
        gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
        break;
      case 'session':
        iconData = Icons.calendar_today_rounded;
        gradientColors = [const Color(0xFF3B82F6), const Color(0xFF2563EB)];
        break;
      case 'timetable':
        iconData = Icons.schedule_rounded;
        gradientColors = [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)];
        break;
      case 'personal info':
      case 'profile':
        iconData = Icons.person_rounded;
        gradientColors = [const Color(0xFF06B6D4), const Color(0xFF0891B2)];
        break;
      case 'change password':
        iconData = Icons.lock_reset_rounded;
        gradientColors = [const Color(0xFFF59E0B), const Color(0xFFD97706)];
        break;
      case 'privacy':
        iconData = Icons.privacy_tip_rounded;
        gradientColors = [const Color(0xFF6366F1), const Color(0xFF4F46E5)];
        break;
      case 'logout':
        iconData = Icons.logout_rounded;
        gradientColors = [const Color(0xFFEF4444), const Color(0xFFDC2626)];
        break;
      default:
        iconData = Icons.grid_view_rounded;
        gradientColors = [const Color(0xFFA855F7), const Color(0xFF9333EA)];
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
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
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors[0].withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(iconData, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
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
