import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _baseUrl = 'https://gdemo.schoolpad.in/mobile/getClientDetails';

  final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Connection': 'keep-alive',
  };

  // Persistence keys
  static const String _keyCookies = 'cookies';
  static const String _keyClientDetails = 'clientDetails';
  static const String _keyUserData = 'userData';

  Future<void> _saveCookies(http.Response response) async {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCookies, rawCookie);
      _headers['Cookie'] = rawCookie;
    }
  }

  Future<void> _loadCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(_keyCookies);
    if (cookie != null) {
      _headers['Cookie'] = cookie;
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
  }

  Future<Map<String, dynamic>> getClientDetails(String schoolCode) async {
    try {
      final response = await http.post(
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
      final response = await http.post(
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
      final response = await http.post(
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
      final response = await http.post(
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
      final response = await http.post(
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
      final response = await http.post(
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

    final response = await http.post(
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

    final response = await http.post(
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

    final response = await http.post(
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
}
