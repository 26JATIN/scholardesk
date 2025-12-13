import 'package:http/http.dart' as http;

/// Abstract factory for creating platform-specific HTTP clients
abstract class HttpClientFactory {
  http.Client createClient();
}
