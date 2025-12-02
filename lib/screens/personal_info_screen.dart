import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:html/parser.dart' as html_parser;
import '../services/api_service.dart';

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

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  
  // Student info
  String? _studentPhotoUrl;
  Map<String, String> _studentDetails = {};
  Map<String, String> _customFields = {};
  Map<String, String> _addressInfo = {};
  
  // Parent info
  String? _fatherPhotoUrl;
  Map<String, String> _fatherDetails = {};
  String? _motherPhotoUrl;
  Map<String, String> _motherDetails = {};

  @override
  void initState() {
    super.initState();
    _fetchPersonalInfo();
  }

  Future<void> _fetchPersonalInfo() async {
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

      _parseHtml(htmlContent);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _parseHtml(String htmlString) {
    final document = html_parser.parse(htmlString);
    
    // Parse Student Photo
    final studentPhoto = document.querySelector('.ui-student-photo');
    if (studentPhoto != null) {
      final style = studentPhoto.attributes['style'] ?? '';
      final urlMatch = RegExp(r'url\((.*?)\)').firstMatch(style);
      if (urlMatch != null) {
        _studentPhotoUrl = urlMatch.group(1)?.replaceAll(r'\/', '/');
      }
    }

    // Parse Student Details
    final studentInfo = document.querySelector('#student-info');
    if (studentInfo != null) {
      _studentDetails = _parseDetailsSection(studentInfo);
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          debugPrint('✅ Personal Info: Predictive back gesture completed');
        }
      },
      child: Scaffold(
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
                        title: Text(
                          'Personal Info',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                        ),
                        titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildStudentSection(),
                          const SizedBox(height: 16),
                          _buildCustomFieldsSection(),
                          const SizedBox(height: 16),
                          _buildAddressSection(),
                          const SizedBox(height: 16),
                          _buildParentSection('Father', _fatherPhotoUrl, _fatherDetails),
                          const SizedBox(height: 16),
                          _buildParentSection('Mother', _motherPhotoUrl, _motherDetails),
                          const SizedBox(height: 20),
                        ]),
                      ),
                    ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildStudentSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_studentPhotoUrl != null)
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey.shade300,
                    child: ClipOval(
                      child: Image.network(
                        _studentPhotoUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.person, size: 40, color: Colors.grey);
                        },
                      ),
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: _studentDetails.entries
                        .map((e) => _buildDetailRow(e.key, e.value))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildCustomFieldsSection() {
    if (_customFields.isEmpty) return const SizedBox.shrink();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  .map((e) => _buildDetailRow(e.key, e.value))
                  .toList(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildAddressSection() {
    if (_addressInfo.isEmpty) return const SizedBox.shrink();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  .map((e) => _buildDetailRow(e.key, e.value))
                  .toList(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms, duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildParentSection(String parentType, String? photoUrl, Map<String, String> details) {
    if (details.isEmpty) return const SizedBox.shrink();
    
    final gradientColors = parentType == 'Father' 
        ? [const Color(0xFF10B981), const Color(0xFF059669)]
        : [const Color(0xFFEC4899), const Color(0xFFDB2777)];
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              gradient: LinearGradient(colors: gradientColors),
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
                    backgroundColor: Colors.grey.shade300,
                    child: ClipOval(
                      child: Image.network(
                        photoUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(Icons.person, size: 30, color: Colors.grey);
                        },
                      ),
                    ),
                  ),
                if (photoUrl != null && !photoUrl.contains('prof-img.svg'))
                  const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: details.entries
                        .map((e) => _buildDetailRow(e.key, e.value))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (parentType == 'Father' ? 300 : 400).ms, duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildDetailRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
