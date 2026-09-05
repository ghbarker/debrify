import 'dart:io';

/// Keep image loading on Flutter's test HTTP stub (400, no sockets), but reject
/// every unplanned IO request. Trakt JSON uses the separate MockClient fixture.
class CwOriginImageHttp extends HttpOverrides {
  CwOriginImageHttp(this.fallback, this.unexpected);

  final HttpOverrides fallback;
  final List<String> unexpected;
  int imageRequests = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ImageClient(fallback.createHttpClient(context), this);
}

class _ImageClient implements HttpClient {
  _ImageClient(this.delegate, this.fixture);
  final HttpClient delegate;
  final CwOriginImageHttp fixture;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (method != 'GET' ||
        url.toString() != 'https://cw-art.invalid/tt0000002.png' ||
        ++fixture.imageRequests > 2) {
      fixture.unexpected.add('$method $url');
      throw StateError('Unexpected IO request: $method $url');
    }
    return delegate.openUrl(method, url);
  }

  @override
  set autoUncompress(bool value) => delegate.autoUncompress = value;

  @override
  void close({bool force = false}) => delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
