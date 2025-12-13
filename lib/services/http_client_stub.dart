import 'package:http/http.dart' as http;
import 'http_client_factory.dart';

/// Stub implementation - this file is never actually imported,
/// it just satisfies the Dart analyzer for conditional imports
class HttpClientFactoryImpl implements HttpClientFactory {
  @override
  http.Client createClient() {
    throw UnsupportedError('Stub implementation');
  }
}

void setupHttpOverrides() {
  throw UnsupportedError('Stub implementation');
}
