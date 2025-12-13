import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

// Conditional imports for platform-specific HTTP client
import 'http_client_stub.dart'
    if (dart.library.io) 'http_client_native.dart'
    if (dart.library.html) 'http_client_web.dart';

class ApiService {
  // Base URL for getClientDetails endpoint
  static const String _clientDetailsUrl = 'https://gdemo.schoolpad.in/mobile/getClientDetails';

  // Default User-Agent header
  static const String _defaultUserAgent = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36';

  // Static headers to share cookies across all instances
  // Note: User-Agent and Connection are forbidden in browser fetch, so stored separately
  static final Map<String, String> _headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
  };

  /// Get User-Agent header (returns empty string on web since it's forbidden)
  static String get userAgent => kIsWeb ? '' : _defaultUserAgent;
  
  /// Get Connection header (returns empty string on web since it's forbidden)
  static String get connectionHeader => kIsWeb ? '' : 'keep-alive';

  // Session ID for web cookie management via proxy
  static final String _webSessionId = DateTime.now().millisecondsSinceEpoch.toString();

  // Track if cookies have been loaded this session
  static bool _cookiesLoaded = false;

  // HTTP client
  late final http.Client _httpClient;

  ApiService() {
    _httpClient = HttpClientFactoryImpl().createClient();
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

  /// Build headers for web requests (adds proxy-specific headers)
  Map<String, String> _buildHeaders({Map<String, String>? extra, String? referer}) {
    final headers = Map<String, String>.from(_headers);
    if (extra != null) {
      headers.addAll(extra);
    }
    
    // Add platform-specific headers (only on native, forbidden on web)
    if (!kIsWeb) {
      headers['User-Agent'] = _defaultUserAgent;
      headers['Connection'] = 'keep-alive';
    }
    
    if (kIsWeb) {
      headers['X-Session-Id'] = _webSessionId;
      if (referer != null) {
        headers['X-Target-Referer'] = referer;
      }
    } else if (referer != null) {
      headers['Referer'] = referer;
    }
    
    return headers;
  }

  /// Build the API URL, wrapping with proxy if on web
  Uri _buildUrl(String url) {
    if (kIsWeb) {
      return Uri.parse('${ApiConfig.corsProxyUrl}?url=${Uri.encodeComponent(url)}');
    }
    return Uri.parse(url);
  }

  /// Handle response from proxy (extract cookies on web)
  void _handleProxyResponse(http.Response response) {
    if (kIsWeb) {
      // On web, cookies come back via X-Set-Cookies header from proxy
      final cookies = response.headers['x-set-cookies'];
      if (cookies != null && cookies.isNotEmpty) {
        _headers['Cookie'] = cookies;
        _cookiesLoaded = true;
        debugPrint('🍪 Web cookies received: $cookies');
      }
    }
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
      
      // Get existing cookies
      String existingCookies = prefs.getString(_keyCookies) ?? '';
      
      // Parse new cookies from set-cookie header
      // Multiple cookies are separated by comma in the set-cookie header
      final newCookies = <String>[];
      final cookieParts = rawCookie.split(',');
      
      for (var part in cookieParts) {
        // Extract just the key=value part before any semicolon
        final cookieValue = part.trim().split(';').first;
        if (cookieValue.isNotEmpty && cookieValue.contains('=')) {
          newCookies.add(cookieValue);
        }
      }
      
      // Merge with existing cookies (avoid duplicates by key)
      final Map<String, String> cookieMap = {};
      
      // Add existing cookies
      if (existingCookies.isNotEmpty) {
        for (var cookie in existingCookies.split(';')) {
          final parts = cookie.trim().split('=');
          if (parts.length == 2) {
            cookieMap[parts[0].trim()] = parts[1].trim();
          }
        }
      }
      
      // Update/add new cookies
      for (var cookie in newCookies) {
        final parts = cookie.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          cookieMap[key] = value;
        }
      }
      
      // Build final cookie string
      final finalCookies = cookieMap.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      
      debugPrint('🍪 Saving cookies: $finalCookies');
      
      await prefs.setString(_keyCookies, finalCookies);
      _headers['Cookie'] = finalCookies;
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
      final url = _buildUrl(_clientDetailsUrl);
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(),
        body: {'schoolCode': schoolCode},
      );

      // Handle cookies from proxy response
      _handleProxyResponse(response);

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/appLoginAuthV2');
    try {
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(),
        body: {
          'txtUsername': username,
          'txtPassword': password,
        },
      );

      await _saveCookies(response);
      _handleProxyResponse(response);

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

  Future<void> forgotPassword(String username, String baseUrl, String clientAbbr) async {
    final url = _buildUrl('https://$clientAbbr.$baseUrl/loginManager/forgotPassword');
    try {
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(),
        body: {
          'txtForgotPassword': username,
        },
      );

      _handleProxyResponse(response);

      if (response.statusCode != 200) {
        throw Exception('Failed to send reset email');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String otp, String userId, String baseUrl, String clientAbbr) async {
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/verifyOtp');
    try {
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(),
        body: {
          'OTPText': otp,
          'authUserId': userId,
        },
      );

      await _saveCookies(response);
      _handleProxyResponse(response);

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getAppFeed');
    
    // Ensure cookies are loaded if not already
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    try {
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(),
        body: {
          'userId': userId,
          'roleId': roleId,
          'sessionId': sessionId,
          'start': start is String ? start : start.toString(),
          'limit': limit.toString(),
          'appKey': appKey,
        },
      );

      _handleProxyResponse(response);

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getAppItemDetail');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    // Generate timestamp in format: yyMMddHHmmssSSSSSS
    final now = DateTime.now();
    final formatter = DateFormat('yyMMddHHmmssSSSSSS');
    final timeStamp = formatter.format(now);

    try {
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'}),
        body: {
          'userId': userId,
          'roleId': roleId,
          'itemId': itemId,
          'itemType': itemType,
          'timeStamp': timeStamp,
        },
      );

      _handleProxyResponse(response);

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getAppAttachmentDetails');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getProfileMenu');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/commonPage');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getAllSession');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/commonPage');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/changePassword');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getLeaveDetailsApp');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/commonPage01');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getCategoryNameApp');
    
    // Ensure cookies are loaded
    if (!_headers.containsKey('Cookie')) {
      await _loadCookies();
    }

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

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
    List<int>? fileBytes, // For web: pass file bytes directly
    String? fileName, // For web: pass filename directly
  }) async {
    // File upload is not supported on web via this method
    if (kIsWeb) {
      throw UnsupportedError('File upload is not supported on web yet. Please use the mobile app.');
    }
    
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/dutyMedicalLeaveAttachmentUpload');
    
    debugPrint('🔄 Uploading leave attachment...');
    debugPrint('📡 Upload URL: $url');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      // Get file info - import dart:io conditionally handled by the native impl
      final actualFileName = fileName ?? filePath.split('/').last;
      final extension = actualFileName.split('.').last;
      
      debugPrint('📎 File path: $filePath');
      debugPrint('📎 File name: $actualFileName, Extension: $extension');
      debugPrint('🍪 Cookies loaded: ${_headers.containsKey('Cookie')}');
      
      var request = http.MultipartRequest('POST', url);
      
      // Add all standard headers (User-Agent and Connection only on native)
      if (!kIsWeb) {
        request.headers['User-Agent'] = _defaultUserAgent;
        request.headers['Connection'] = 'keep-alive';
      }
      request.headers['Accept'] = _headers['Accept']!;
      
      // Add cookies from headers
      if (_headers.containsKey('Cookie')) {
        request.headers['Cookie'] = _headers['Cookie']!;
        debugPrint('🍪 Cookie header added');
      }
      request.headers['X-Requested-With'] = 'codebrigade.chalkpadpro.app';
      
      // Add web proxy session ID
      if (kIsWeb) {
        request.headers['X-Session-Id'] = _webSessionId;
      }
      
      // Add form fields as per expected format (no sessionId)
      request.fields.addAll({
        'value1': actualFileName,
        'value2': extension,
        'value3': userId,
      });
      
      debugPrint('📋 Form fields: value1=$actualFileName, value2=$extension, value3=$userId');
      
      // Add file with explicit filename (not content URI)
      var multipartFile = await http.MultipartFile.fromPath(
        'file', 
        filePath,
        filename: actualFileName, // Explicitly set filename to avoid content URI
      );
      request.files.add(multipartFile);
      
      debugPrint('📎 Multipart file added with filename: $actualFileName');
      
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

  /// Upload leave attachment using file bytes (works on all platforms including web)
  Future<Map<String, dynamic>> uploadLeaveAttachmentBytes({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/dutyMedicalLeaveAttachmentUpload');
    
    debugPrint('🔄 Uploading leave attachment (bytes)...');
    debugPrint('📡 Upload URL: $url');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      final extension = fileName.split('.').last;
      
      debugPrint('📎 File name: $fileName, Extension: $extension');
      debugPrint('📎 File size: ${fileBytes.length} bytes');
      debugPrint('🍪 Cookies loaded: ${_headers.containsKey('Cookie')}');
      
      var request = http.MultipartRequest('POST', url);
      
      // Add all standard headers (User-Agent and Connection only on native)
      if (!kIsWeb) {
        request.headers['User-Agent'] = _defaultUserAgent;
        request.headers['Connection'] = 'keep-alive';
      }
      request.headers['Accept'] = _headers['Accept']!;
      
      // Add cookies from headers
      if (_headers.containsKey('Cookie')) {
        request.headers['Cookie'] = _headers['Cookie']!;
        debugPrint('🍪 Cookie header added');
      }
      request.headers['X-Requested-With'] = 'codebrigade.chalkpadpro.app';
      
      // Add web session ID if on web
      if (kIsWeb) {
        request.headers['X-Session-Id'] = _webSessionId;
      }
      
      // Add form fields as per expected format
      request.fields.addAll({
        'value1': fileName,
        'value2': extension,
        'value3': userId,
      });
      
      debugPrint('📋 Form fields: value1=$fileName, value2=$extension, value3=$userId');
      
      // Add file from bytes
      var multipartFile = http.MultipartFile.fromBytes(
        'file', 
        fileBytes,
        filename: fileName,
      );
      request.files.add(multipartFile);
      
      debugPrint('📎 Multipart file added with filename: $fileName');
      debugPrint('📤 Sending upload request...');
      
      // Send request
      var streamedResponse = await _httpClient.send(request);
      var response = await http.Response.fromStream(streamedResponse);
      
      await _saveCookies(response);
      _handleProxyResponse(response);

      debugPrint('📥 Upload response: ${response.statusCode}');
      debugPrint('📄 Upload body: ${response.body}');

      if (response.statusCode == 200) {
        // Server returns plain text in format: "fullname.pdf|randomname.pdf|"
        final responseText = response.body.trim();
        
        if (responseText.isEmpty) {
          throw Exception('Server returned empty response');
        }
        
        // Parse the pipe-separated response
        final parts = responseText.split('|').where((s) => s.isNotEmpty).toList();
        
        final uploadedFullName = parts.isNotEmpty ? parts[0] : fileName;
        final uploadedShortName = parts.length > 1 ? parts[1] : uploadedFullName;
        
        debugPrint('✅ File uploaded successfully');
        debugPrint('   Full name: $uploadedFullName');
        debugPrint('   Short name (for deletion): $uploadedShortName');
        
        return {
          'success': true,
          'fileName': uploadedShortName,
          'fullName': uploadedFullName,
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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/removeDutyMedicalLeaveAttachment');
    
    debugPrint('🗑️ Removing leave attachment...');
    debugPrint('📡 Remove URL: $url');
    debugPrint('📎 File to remove: $fileName');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(extra: {
          'X-Requested-With': 'codebrigade.chalkpadpro.app',
        }),
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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/cancelDutyMedicalLeave');
    
    debugPrint('🚫 Cancelling leave...');
    debugPrint('📡 Cancel URL: $url');
    debugPrint('🆔 Leave ID: $leaveId');
    debugPrint('👤 User ID: $userId');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    try {
      final response = await _httpClient.post(
        url,
        headers: _buildHeaders(extra: {
          'X-Requested-With': 'codebrigade.chalkpadpro.app',
        }),
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
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/addLeaveApp');

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
      final headers = _buildHeaders(extra: {
        'X-Requested-With': 'codebrigade.chalkpadpro.app',
      });

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

  /// Fetches fee receipt details for a student
  Future<String> getReceiptDetails({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required String roleId,
  }) async {
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/getReceiptDetails');
    
    debugPrint('📡 Fetching receipt details...');
    debugPrint('  URL: $url');
    debugPrint('  UserID: $userId');
    debugPrint('  SessionID: $sessionId');
    debugPrint('  RoleID: $roleId');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    final headers = _buildHeaders(extra: {'X-Requested-With': 'codebrigade.chalkpadpro.app'});

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'userId': userId,
          'sessionId': sessionId,
          'roleId': roleId,
        },
      );

      await _saveCookies(response);

      debugPrint('📥 Receipt details response: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Try to parse as JSON first
        try {
          final data = json.decode(response.body);
          // If it's a JSON response with 'content' field
          if (data is Map && data.containsKey('content')) {
            return data['content'] as String? ?? '';
          }
          // If it's just a string in JSON
          if (data is String) {
            return data;
          }
          // Return as is
          return response.body;
        } catch (jsonError) {
          // If JSON parsing fails, assume it's plain HTML
          debugPrint('Response is not JSON, returning as plain HTML');
          return response.body;
        }
      } else {
        debugPrint('❌ Response body on error: ${response.body}');
        throw Exception('Failed to load receipt details: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching receipt details: $e');
      throw Exception('Error fetching receipt details: $e');
    }
  }

  /// Calls showAttendance endpoint to initialize server session
  /// This is required before calling getAttendanceRegister
  /// Endpoint: /mobile/showAttendance
  Future<Map<String, dynamic>> showAttendance({
    required String baseUrl,
    required String clientAbbr,
    required String userId,
    required String sessionId,
    required String apiKey,
    required String roleId,
    String prevNext = '0',
    String month = '',
  }) async {
    final url = _buildUrl('https://$clientAbbr.$baseUrl/mobile/showAttendance');
    
    debugPrint('📡 Calling showAttendance to initialize session...');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    final headers = _buildHeaders();

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'prevNext': prevNext,
          'userId': userId,
          'sessionId': sessionId,
          'apiKey': apiKey,
          'roleId': roleId,
          'month': month,
        },
      );

      await _saveCookies(response);

      debugPrint('📥 showAttendance response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to initialize attendance session: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error calling showAttendance: $e');
      rethrow;
    }
  }

  /// Fetches attendance register for a student
  /// Endpoint: /chalkpadpro/studentDetails/getAttendanceRegister
  Future<String> getAttendanceRegister({
    required String baseUrl,
    required String clientAbbr,
    required String studentId,
    required String sessionId,
  }) async {
    final url = _buildUrl('https://$clientAbbr.$baseUrl/chalkpadpro/studentDetails/getAttendanceRegister');
    
    debugPrint('📡 Fetching attendance register...');
    
    // Ensure cookies are loaded
    await ensureCookiesLoaded();

    final headers = _buildHeaders();

    try {
      final response = await _httpClient.post(
        url,
        headers: headers,
        body: {
          'studentId': studentId,
          'sessionId': sessionId,
        },
      );

      await _saveCookies(response);

      debugPrint('📥 Attendance register response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        if (response.body.isEmpty || response.body.length < 50) {
          throw Exception('Received empty response. Please try again.');
        }
        debugPrint('✅ Successfully fetched attendance register');
        return response.body;
      } else {
        throw Exception('Failed to load attendance register: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching attendance register: $e');
      rethrow;
    }
  }
}
