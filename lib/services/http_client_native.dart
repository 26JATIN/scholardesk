import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import 'http_client_factory.dart';

class HttpClientFactoryImpl implements HttpClientFactory {
  static const List<String> _allowedHosts = [
    'schoolpad.in',
    'gdemo.schoolpad.in',
    'codebrigade.in',
  ];

  @override
  http.Client createClient() {
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
}

/// Setup HTTP overrides for native platforms
void setupHttpOverrides() {
  HttpOverrides.global = _MyHttpOverrides();
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
