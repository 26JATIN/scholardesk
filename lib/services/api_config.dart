import 'package:flutter/foundation.dart';

/// Configuration for API endpoints with CORS proxy support for web
class ApiConfig {
  /// The CORS proxy URL to use for web requests
  /// Production proxy server on Vercel
  static const String corsProxyUrl = 'https://scholardesk-proxy.vercel.app/proxy';
  
  /// Whether to use the CORS proxy (only on web in debug mode)
  static bool get useCorsProxy => kIsWeb;
  
  /// Wraps a URL with the CORS proxy if running on web
  static String proxyUrl(String originalUrl) {
    if (useCorsProxy) {
      return '$corsProxyUrl?url=${Uri.encodeComponent(originalUrl)}';
    }
    return originalUrl;
  }
  
  /// Builds the full API URL with optional proxy wrapping
  static Uri buildUrl({
    required String baseUrl,
    required String clientAbbr,
    required String endpoint,
  }) {
    final originalUrl = 'https://$clientAbbr.$baseUrl$endpoint';
    
    if (useCorsProxy) {
      return Uri.parse('$corsProxyUrl?url=${Uri.encodeComponent(originalUrl)}');
    }
    
    return Uri.parse(originalUrl);
  }
  
  /// Proxies an image URL for web to avoid CORS issues
  /// Use this for any external image URLs (like S3, etc.)
  static String proxyImageUrl(String imageUrl) {
    if (useCorsProxy && imageUrl.isNotEmpty) {
      return '$corsProxyUrl?url=${Uri.encodeComponent(imageUrl)}';
    }
    return imageUrl;
  }
  
  /// Gets the demo URL with optional proxy wrapping
  static Uri getDemoUrl() {
    const originalUrl = 'https://gdemo.schoolpad.in/mobile/getClientDetails';
    
    if (useCorsProxy) {
      return Uri.parse('$corsProxyUrl?url=${Uri.encodeComponent(originalUrl)}');
    }
    
    return Uri.parse(originalUrl);
  }
}
