import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _baseUrl = 'https://gdemo.schoolpad.in/mobile/getClientDetails';

  // Static headers to share cookies across all instances
  static final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Connection': 'keep-alive',
  };

  // Track if cookies have been loaded this session
  static bool _cookiesLoaded = false;

  // Allowed hosts for SSL connections
  static const List<String> _allowedHosts = [
    'schoolpad.in',
    'gdemo.schoolpad.in',
  ];

  // HTTP client with SSL configuration
  late final http.Client _httpClient;

  ApiService() {
    _httpClient = _createSecureClient();
  }

  /// Ensures cookies are loaded - call this before making authenticated API calls
  Future<void> ensureCookiesLoaded() async {
    if (!_cookiesLoaded || !_headers.containsKey('Cookie')) {
      await _loadCookies();
      _cookiesLoaded = true;
    }
  }

  /// Get cookies for manual HTTP requests
  static String getCookies() {
    return _headers['Cookie'] ?? '';
  }

  /// Creates an HTTP client with SSL certificate validation
  /// In debug mode, it allows bad certificates for testing
  /// In release mode, it enforces strict SSL validation
  http.Client _createSecureClient() {
    final HttpClient httpClient = HttpClient();
    
    // Set connection timeout
    httpClient.connectionTimeout = const Duration(seconds: 30);
    
    // Configure SSL/TLS settings
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // In debug mode, allow all certificates for testing
      if (kDebugMode) {
        debugPrint('SSL: Allowing certificate for $host in debug mode');
        return true;
      }
      
      // In release mode, only allow certificates for our trusted hosts
      final isAllowedHost = _allowedHosts.any(
        (allowedHost) => host.endsWith(allowedHost),
      );
      
      if (!isAllowedHost) {
        debugPrint('SSL: Rejecting certificate for untrusted host: $host');
        return false;
      }
      
      // Verify the certificate is valid and not expired
      final now = DateTime.now();
      if (cert.endValidity.isBefore(now)) {
        debugPrint('SSL: Certificate expired for $host');
        return false;
      }
      
      if (cert.startValidity.isAfter(now)) {
        debugPrint('SSL: Certificate not yet valid for $host');
        return false;
      }
      
      return true;
    };
    
    return IOClient(httpClient);
  }

  /// Closes the HTTP client - call this when disposing the service
  void dispose() {
    _httpClient.close();
  }

  // Persistence keys
  static const String _keyCookies = 'cookies';
  static const String _keyClientDetails = 'clientDetails';
  static const String _keyUserData = 'userData';
  static const String _keySemester = 'currentSemester';
  static const String _keyBatch = 'currentBatch';
  static const String _keyGroup = 'currentGroup';

  Future<void> _saveCookies(http.Response response) async {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCookies, rawCookie);
      _headers['Cookie'] = rawCookie;
      _cookiesLoaded = true;
    }
  }

  Future<void> _loadCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_keyCookies);
    if (cookie != null) {
      _headers['Cookie'] = cookie;
      _cookiesLoaded = true;
    }
  }

  Future<void> saveSession(Map<String, dynamic> clientDetails, Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyClientDetails, json.encode(clientDetails));
    await prefs.setString(_keyUserData, json.encode(userData));
  }

  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final clientDetailsStr = prefs.getString(_keyClientDetails);
    final userDataStr = prefs.getString(_keyUserData);
    
    if (clientDetailsStr != null && userDataStr != null) {
      await _loadCookies();
      return {
        'clientDetails': json.decode(clientDetailsStr),
        'userData': json.decode(userDataStr),
      };
    }
    return null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _headers.remove('Cookie');
    _cookiesLoaded = false;
  }

  // Semester/Academic Info methods
  Future<void> saveSemesterInfo({
    String? semester,
    String? batch,
    String? group,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (semester != null) await prefs.setString(_keySemester, semester);
    if (batch != null) await prefs.setString(_keyBatch, batch);
    if (group != null) await prefs.setString(_keyGroup, group);
  }

  Future<Map<String, String?>> getSemesterInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'semester': prefs.getString(_keySemester),
      'batch': prefs.getString(_keyBatch),
      'group': prefs.getString(_keyGroup),
    };
  }

  /// Parses semester number from various formats like:
  /// - "Subject(s) Details (5 SEM)" -> "5"
  /// - "5 SEM" -> "5"  
  /// - "Semester 5" -> "5"
  /// - "SEM-5" -> "5"
  static String? parseSemesterFromText(String text) {
    // Try various patterns
    final patterns = [
      RegExp(r'(\d+)\s*SEM', caseSensitive: false),           // "5 SEM" or "5SEM"
      RegExp(r'SEM[:\-\s]*(\d+)', caseSensitive: false),      // "SEM 5" or "SEM-5"
      RegExp(r'Semester\s*[:\-]?\s*(\d+)', caseSensitive: false), // "Semester 5"
      RegExp(r'\((\d+)\s*SEM\)', caseSensitive: false),       // "(5 SEM)"
    ];
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> getClientDetails(String schoolCode) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(_baseUrl),
        headers: _headers,
        body: {'schoolCode': schoolCode},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          return data[0] as Map<String, dynamic>;
        } else {
          throw Exception('No client details found for this code.');
        }
      } else {
        throw Exception('Failed to load client details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  Future<Map<String, dynamic>> login(String username, String password, String baseUrl, String clientAbbr) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/appLoginAuthV2');
    try {
      final response = await _httpClient.post(
        url,
        headers: _headers,
        body: {
          'txtUsername': username,
          'txtPassword': password,
        },
      );

      await _saveCookies(response);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      } else {
        throw Exception('Login failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String otp, String userId, String baseUrl, String clientAbbr) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/verifyOtp');
    try {
      final response = await _httpClient.post(
        url,
        headers: _headers,
        body: {
          'OTPText': otp,
          'authUserId': userId,
        },
      );

      await _saveCookies(response);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      } else {
        throw Exception('OTP verification failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  Future<Map<String, dynamic>> getAppFeed({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String roleId,
    required String sessionId,
    required String appKey,
    dynamic start = 0,
    int limit = 10,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/getAppFeed');
    
    // Ensure cookies are loaded if not already
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    try {
      final response = await _httpClient.post(
        url,
        headers: _headers,
        body: {
          'userId': userId,
          'roleId': roleId,
          'sessionId': sessionId,
          'start': start is String ? start : start.toString(),
          'limit': limit.toString(),
          'appKey': appKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Handle case where API returns a List instead of Map (e.g., empty array [])
        if (data is List) {
          return {'feed': data, 'next': null};
        }
        return data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load feed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  Future<Map<String, dynamic>> getAppItemDetail({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String roleId,
    required String sessionId,
    required String appKey,
    required String itemId,
    required String itemType,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/getAppItemDetail');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    // Generate timestamp in format: yyMMddHHmmssSSSSSS
    final now = DateTime.now();
    final formatter = DateFormat('yyMMddHHmmssSSSSSS');
    final timeStamp = formatter.format(now);

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'userId': userId,
          'roleId': roleId,
          'itemId': itemId,
          'itemType': itemType,
          'timeStamp': timeStamp,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load item detail: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  Future<Map<String, dynamic>> getAppAttachmentDetails({
    required String baseUrl,
    required String clientAbbr,
    required String itemId,
    required String itemType,
    required String fileSystem,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/getAppAttachmentDetails');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'id': itemId,
          'itemType': itemType,
          'fileSystem': fileSystem,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load attachment details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }
  Future<Map<String, dynamic>> getProfileMenu(String baseUrl, String clientAbbr) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/getProfileMenu');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    final response = await _httpClient.post(
      url,
      headers: headers,
    );

    await _saveCookies(response);

    if (response.statusCode == 200) {
      debugPrint('getProfileMenu Response Body: ${response.body}');
      final decoded = json.decode(response.body);
      debugPrint('getProfileMenu Decoded Type: ${decoded.runtimeType}');
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is String) {
        // Handle case where it might be double encoded or just a string
        try {
           final doubleDecoded = json.decode(decoded);
           if (doubleDecoded is Map<String, dynamic>) {
             return doubleDecoded;
           }
        } catch (_) {}
        // If it's just a string (HTML?), wrap it in a map to avoid crash
        return {'content': decoded};
      }
      return decoded as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load profile menu: ${response.statusCode} - ${response.body}');
    }
  }

  Future<String> getCommonPage({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required String roleId,
    required String appKey,
    String commonPageId = '28',
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/commonPage');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    final now = DateTime.now();
    final formatter = DateFormat('yyMMddHHmmssSSSSSS');
    final timeStamp = formatter.format(now);

    final response = await _httpClient.post(
      url,
      headers: headers,
      body: {
        'commonPageId': commonPageId,
        'userId': userId,
        'sessionId': sessionId,
        'roleId': roleId,
        'timeStamp': timeStamp,
      },
    );

    await _saveCookies(response);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['content'] as String? ?? '';
    } else {
      throw Exception('Failed to load attendance: ${response.statusCode} - ${response.body}');
    }
  }

  Future<List<dynamic>> getAllSession({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/getAllSession');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    final response = await _httpClient.post(
      url,
      headers: headers,
      body: {
        'userId': userId,
      },
    );

    await _saveCookies(response);

    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to load sessions: ${response.statusCode} - ${response.body}');
    }
  }
  Future<String> getSubjects({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required String roleId,
    required String appKey,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/commonPage');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    final now = DateTime.now();
    final formatter = DateFormat('yyMMddHHmmssSSSSSS');
    final timeStamp = formatter.format(now);

    final response = await _httpClient.post(
      url,
      headers: headers,
      body: {
        'commonPageId': '80', // Subjects page ID
        'userId': userId,
        'sessionId': sessionId,
        'roleId': roleId,
        'timeStamp': timeStamp,
      },
    );

    await _saveCookies(response);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['content'] as String? ?? '';
    } else {
      throw Exception('Failed to load subjects: ${response.statusCode} - ${response.body}');
    }
  }

  Future<Map<String, dynamic>> changePassword({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String oldPwd,
    required String newPwd,
    required String conPwd,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/changePassword');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'oldPwd': oldPwd,
          'newPwd': newPwd,
          'conPwd': conPwd,
          'userId': userId,
        },
      );

      await _saveCookies(response);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to change password: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  Future<String> getLeaveHistory({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/getLeaveDetailsApp');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'sessionId': sessionId,
          'userId': userId,
        },
      );

      await _saveCookies(response);

      if (response.statusCode == 200) {
        // Try to parse as JSON first
        try {
          final data = json.decode(response.body);
          // If it's a JSON response with 'content' field
          if (data is Map && data.containsKey('content')) {
            return data['content'] as String? ?? '';
          }
          // If it's just a plain JSON, return as string
          return response.body;
        } catch (jsonError) {
          // If JSON parsing fails, assume it's plain HTML
          debugPrint('Response is not JSON, returning as plain HTML');
          return response.body;
        }
      } else {
        throw Exception('Failed to load leave history: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching leave history: $e');
    }
  }

  Future<String> getLeaveDetail({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required String roleId,
    required String leaveId,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/commonPage01');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    final now = DateTime.now();
    final formatter = DateFormat('yyMMddHHmmssSSSSSS');
    final timeStamp = formatter.format(now);

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'commonPageId': '27',
          'userId': userId,
          'sessionId': sessionId,
          'roleId': roleId,
          'timeStamp': timeStamp,
          'device': '',
          'commonObj[leaveId]': leaveId,
        },
      );

      await _saveCookies(response);

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          return data['content'] as String? ?? '';
        } catch (e) {
          // If JSON parsing fails, return response as is
          debugPrint('Response is not JSON, returning as plain text');
          return response.body;
        }
      } else {
        throw Exception('Failed to load leave detail: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching leave detail: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getLeaveCategories({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/getCategoryNameApp');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = {
      ..._headers,
      'X-Requested-With': 'codebrigade.chalkpadpro.app',
    };

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'sessionId': sessionId,
          'userId': userId,
        },
      );

      await _saveCookies(response);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((e) => e as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching categories: $e');
      throw Exception('Error fetching categories: $e');
    }
  }

  Future<Map<String, dynamic>> uploadLeaveAttachment({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required String filePath,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/dutyMedicalLeaveAttachmentUpload');
    
    debugPrint('🔄 Uploading leave attachment...');
    debugPrint('📡 Upload URL: $url');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      // Get file info
      final file = File(filePath);
      final fileName = file.path.split('/').last;
      final extension = fileName.split('.').last;
      
      debugPrint('📎 File path: $filePath');
      debugPrint('📎 File name: $fileName, Extension: $extension');
      debugPrint('🍪 Cookies loaded: ${_headers.containsKey('Cookie')}');
      
      var request = http.MultipartRequest('POST', url);
      
      // Add all standard headers
      request.headers['User-Agent'] = _headers['User-Agent']!;
      request.headers['Accept'] = _headers['Accept']!;
      request.headers['Connection'] = _headers['Connection']!;
      
      // Add cookies from headers
      if (_headers.containsKey('Cookie')) {
        request.headers['Cookie'] = _headers['Cookie']!;
        debugPrint('🍪 Cookie header added');
      }
      request.headers['X-Requested-With'] = 'codebrigade.chalkpadpro.app';
      
      // Add form fields as per expected format (no sessionId)
      request.fields.addAll({
        'value1': fileName,
        'value2': extension,
        'value3': userId,
      });
      
      debugPrint('📋 Form fields: value1=$fileName, value2=$extension, value3=$userId');
      
      // Add file with explicit filename (not content URI)
      var multipartFile = await http.MultipartFile.fromPath(
        'file', 
        filePath,
        filename: fileName, // Explicitly set filename to avoid content URI
      );
      request.files.add(multipartFile);
      
      debugPrint('📎 Multipart file added with filename: $fileName');
      
      debugPrint('📤 Sending upload request...');
      
      // Send request
      var streamedResponse = await _httpClient.send(request);
      var response = await http.Response.fromStream(streamedResponse);
      
      await _saveCookies(response);

      debugPrint('📥 Upload response: ${response.statusCode}');
      debugPrint('📄 Upload body: ${response.body}');

      if (response.statusCode == 200) {
        // Server returns plain text in format: "fullname.pdf|randomname.pdf|"
        // Example: "Leave_20251205_file.pdf|1$3O8jZBU7.pdf|"
        final responseText = response.body.trim();
        
        if (responseText.isEmpty) {
          throw Exception('Server returned empty response');
        }
        
        // Parse the pipe-separated response
        final parts = responseText.split('|').where((s) => s.isNotEmpty).toList();
        
        // parts[0] = full server filename (for display)
        // parts[1] = random short filename (for deletion API)
        final uploadedFullName = parts.isNotEmpty ? parts[0] : fileName;
        final uploadedShortName = parts.length > 1 ? parts[1] : uploadedFullName;
        
        debugPrint('✅ File uploaded successfully');
        debugPrint('   Full name: $uploadedFullName');
        debugPrint('   Short name (for deletion): $uploadedShortName');
        
        return {
          'success': true,
          'fileName': uploadedShortName, // Use short name for deletion!
          'fullName': uploadedFullName,  // Keep full name for display if needed
          'originalName': fileName,
          'rawResponse': responseText,
        };
      } else {
        throw Exception('Failed to upload file: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error uploading file: $e');
      throw Exception('Error uploading file: $e');
    }
  }

  Future<bool> removeLeaveAttachment({
    required String baseUrl,
    required String clientAbbr,
    required String fileName,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/removeDutyMedicalLeaveAttachment');
    
    debugPrint('🗑️ Removing leave attachment...');
    debugPrint('📡 Remove URL: $url');
    debugPrint('📎 File to remove: $fileName');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      final response = await _httpClient.post(
        url,
        headers: {
          'User-Agent': _headers['User-Agent']!,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': _headers['Accept']!,
          'Connection': _headers['Connection']!,
          'Cookie': _headers['Cookie'] ?? '',
          'X-Requested-With': 'codebrigade.chalkpadpro.app',
        },
        body: {
          'fileName': fileName,
        },
      );
      
      await _saveCookies(response);

      debugPrint('📥 Remove response: ${response.statusCode}');
      debugPrint('📄 Remove body: ${response.body}');

      if (response.statusCode == 200) {
        final responseText = response.body.trim();
        // Server returns "1" for success
        final success = responseText == '1';
        
        if (success) {
          debugPrint('✅ File removed successfully: $fileName');
        } else {
          debugPrint('⚠️ File removal returned: $responseText');
        }
        
        return success;
      } else {
        throw Exception('Failed to remove file: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error removing file: $e');
      throw Exception('Error removing file: $e');
    }
  }

  Future<bool> cancelLeave({
    required String baseUrl,
    required String clientAbbr,
    required String leaveId,
    required String userId,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/cancelDutyMedicalLeave');
    
    debugPrint('🚫 Cancelling leave...');
    debugPrint('📡 Cancel URL: $url');
    debugPrint('🆔 Leave ID: $leaveId');
    debugPrint('👤 User ID: $userId');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      final response = await _httpClient.post(
        url,
        headers: {
          'User-Agent': _headers['User-Agent']!,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': _headers['Accept']!,
          'Connection': _headers['Connection']!,
          'Cookie': _headers['Cookie'] ?? '',
          'X-Requested-With': 'codebrigade.chalkpadpro.app',
        },
        body: {
          'id': leaveId,
          'userId': userId,
        },
      );
      
      await _saveCookies(response);

      debugPrint('📥 Cancel response: ${response.statusCode}');
      debugPrint('📄 Cancel body: ${response.body}');

      if (response.statusCode == 200) {
        final responseText = response.body.trim();
        // Server returns "1" for success
        final success = responseText == '1';
        
        if (success) {
          debugPrint('✅ Leave cancelled successfully: $leaveId');
        } else {
          debugPrint('⚠️ Leave cancellation returned: $responseText');
        }
        
        return success;
      } else {
        throw Exception('Failed to cancel leave: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error cancelling leave: $e');
      throw Exception('Error cancelling leave: $e');
    }
  }

  Future<Map<String, dynamic>> submitLeaveApplication({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required String roleId,
    required String leaveType,
    required String category,
    required String eventName,
    required String startDate,
    required String endDate,
    required String timeSlot,
    required String periods,
    required String reason,
    String? fileName,
  }) async {
    final url = Uri.parse('https://$clientAbbr.$baseUrl/mobile/addLeaveApp');

    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      debugPrint('📤 Submitting leave application...');
      debugPrint('📋 Leave details:');
      debugPrint('  Type: $leaveType, Category: $category');
      debugPrint('  Event: $eventName');
      debugPrint('  Dates: $startDate to $endDate');
      debugPrint('  File: ${fileName ?? "none"}');
      debugPrint('🍪 Cookies loaded: ${_headers.containsKey('Cookie')}');

      // Server expects application/x-www-form-urlencoded format (not multipart)
      final headers = {
        'User-Agent': _headers['User-Agent']!,
        'Accept': _headers['Accept']!,
        'Connection': _headers['Connection']!,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': _headers['Cookie'] ?? '',
        'X-Requested-With': 'codebrigade.chalkpadpro.app',
      };

      final body = {
        'sessionId': sessionId,
        'userId': userId,
        'roleId': roleId,
        'leaveType': leaveType,
        'category': category,
        'ename': eventName,
        'leaveStartDate': startDate,
        'leaveEndDate': endDate,
        'timeSlot': timeSlot,
        'periodwise': periods,
        'reasonforOtherLeave': reason,
        'fileName': fileName ?? '',
      };

      debugPrint('� Request body: $body');

      final response = await _httpClient.post(url, headers: headers, body: body);
      await _saveCookies(response);

      debugPrint('📥 Submit response: ${response.statusCode}');
      debugPrint('📄 Submit body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        return result;
      } else {
        throw Exception('Failed to submit leave: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error submitting leave: $e');
      throw Exception('Error submitting leave: $e');
    }
  }
}
