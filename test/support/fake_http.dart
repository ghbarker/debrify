import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds a [MockClient] from a url → response map.
MockClient fakeHttp(Map<String, http.Response> routes) {
  return MockClient((request) async {
    final key = request.url.toString();
    final response = routes[key];
    if (response == null) {
      return http.Response('not found: $key', 404);
    }
    return response;
  });
}
