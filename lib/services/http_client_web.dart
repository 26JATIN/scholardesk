import 'package:http/http.dart' as http;
import 'http_client_factory.dart';

class HttpClientFactoryImpl implements HttpClientFactory {
  @override
  http.Client createClient() {
    // For web, just use the standard http.Client
    // CORS will be handled by the proxy
    return http.Client();
  }
}

/// No-op for web platform
void setupHttpOverrides() {
  // No HTTP overrides needed for web
}
