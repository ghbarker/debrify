import 'dart:io';

import 'package:debrify/services/stream_url_validator.dart';
import 'package:flutter_test/flutter_test.dart';

/// The failover chain's liveness probe: GET `Range: bytes=0-0`, alive iff
/// 200/206, one retry on timeout, any error → dead. Real loopback server so
/// the request headers, redirect following and body cancellation are the
/// real client's, not a mock's.
void main() {
  late HttpServer server;
  late String base;
  late List<HttpRequest> seen;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.address}:${server.port}';
    seen = [];
  });

  tearDown(() async => server.close(force: true));

  void serve(Future<void> Function(HttpRequest req, int n) handler) {
    var n = 0;
    server.listen((req) async {
      seen.add(req);
      await handler(req, n++);
    });
  }

  const fast = Duration(milliseconds: 400);

  Future<bool> probe(String path, {Duration timeout = fast}) =>
      StreamUrlValidator.isAliveByRangeProbe('$base$path', timeout: timeout);

  test('206 Partial Content is alive and the range header was sent', () async {
    serve((req, _) async {
      expect(req.method, 'GET');
      expect(req.headers.value('range'), 'bytes=0-0');
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set('content-range', 'bytes 0-0/1000');
      req.response.add([0]);
      await req.response.close();
    });
    expect(await probe('/a.mkv'), isTrue);
    expect(seen, hasLength(1));
  });

  test('a host that ignores the range and answers 200 is alive', () async {
    serve((req, _) async {
      req.response.statusCode = HttpStatus.ok;
      // A large body the probe must not wait for.
      req.response.headers.contentLength = 50 * 1024 * 1024;
      req.response.add(List.filled(1024, 1));
      await req.response.flush();
      // Keep the socket open; the probe must have cancelled the body.
      await Future<void>.delayed(const Duration(seconds: 3));
      await req.response.close();
    });
    final sw = Stopwatch()..start();
    expect(await probe('/big.mkv'), isTrue);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  for (final status in [
    HttpStatus.notFound,
    HttpStatus.forbidden,
    HttpStatus.internalServerError,
    HttpStatus.requestedRangeNotSatisfiable,
    HttpStatus.noContent,
  ]) {
    test('$status is dead on the first answer, no retry', () async {
      serve((req, _) async {
        req.response.statusCode = status;
        await req.response.close();
      });
      expect(await probe('/x'), isFalse);
      expect(seen, hasLength(1));
    });
  }

  test('a redirect to a live target is alive', () async {
    serve((req, _) async {
      if (req.uri.path == '/start') {
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set('location', '$base/final');
        await req.response.close();
        return;
      }
      expect(req.headers.value('range'), 'bytes=0-0');
      req.response.statusCode = HttpStatus.partialContent;
      req.response.add([0]);
      await req.response.close();
    });
    expect(await probe('/start'), isTrue);
    expect(seen.map((r) => r.uri.path), ['/start', '/final']);
  });

  test('a timeout is retried once and a live second answer wins', () async {
    serve((req, n) async {
      if (n == 0) {
        // Stall past the probe timeout; the client abandons this socket.
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await req.response.close();
        } catch (_) {}
        return;
      }
      req.response.statusCode = HttpStatus.partialContent;
      req.response.add([0]);
      await req.response.close();
    });
    expect(await probe('/slow-then-ok'), isTrue);
    expect(seen, hasLength(2));
  });

  test('two timeouts are dead', () async {
    serve((req, _) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await req.response.close();
      } catch (_) {}
    });
    final sw = Stopwatch()..start();
    expect(await probe('/stall'), isFalse);
    expect(seen, hasLength(2));
    // Two timeouts, no third attempt.
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 1600)));
  });

  test('a refused connection is dead without a retry', () async {
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close(force: true);
    expect(
      await StreamUrlValidator.isAliveByRangeProbe(
        'http://127.0.0.1:$port/gone',
        timeout: fast,
      ),
      isFalse,
    );
  });

  test('garbage URLs are dead without a request', () async {
    expect(
      await StreamUrlValidator.isAliveByRangeProbe('not a url', timeout: fast),
      isFalse,
    );
    expect(
      await StreamUrlValidator.isAliveByRangeProbe('', timeout: fast),
      isFalse,
    );
    expect(seen, isEmpty);
  });

  test('extra headers ride along with the range', () async {
    serve((req, _) async {
      expect(req.headers.value('x-debrify'), 'yes');
      expect(req.headers.value('range'), 'bytes=0-0');
      req.response.statusCode = HttpStatus.partialContent;
      await req.response.close();
    });
    expect(
      await StreamUrlValidator.isAliveByRangeProbe(
        '$base/h',
        timeout: fast,
        headers: const {'X-Debrify': 'yes'},
      ),
      isTrue,
    );
  });
}
