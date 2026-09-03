import 'package:debrify/services/cloud/cloud_playback_helpers.dart';
import 'package:debrify/services/deep_link_service.dart';
import 'package:debrify/services/stream_url_validator.dart';
import 'package:debrify/utils/format_tag_detector.dart';
import 'package:debrify/utils/m3u_parser.dart';
import 'package:debrify/utils/movie_parser.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/seeded_fuzz.dart';

void main() {
  test('seeded parser fuzz does not throw', () {
    final fuzz = SeededFuzz(20260903);
    for (var i = 0; i < 200; i++) {
      final s = i.isEven ? fuzz.garbage() : fuzz.unicodeJunk();
      expect(() => SeriesParser.parseFilename(s), returnsNormally);
      expect(() => MovieParser.parseFilename(s), returnsNormally);
      expect(() => FormatTagDetector.detect(s), returnsNormally);
      expect(() => M3uParser.parse(s), returnsNormally);
      expect(() => DeepLinkService.extractInfohash(s), returnsNormally);
      expect(() => CloudPlaybackHelpers.fileName(s), returnsNormally);
    }
    expect(() => SeriesParser.parseFilename(fuzz.huge(8000)), returnsNormally);
    expect(() => M3uParser.parse(fuzz.huge(20000)), returnsNormally);
    expect(DeepLinkService.extractInfohash(''), isNull);
    expect(DeepLinkService.extractInfohash('not-a-magnet'), isNull);
    expect(
      DeepLinkService.extractInfohash('magnet:?xt=urn:btih:ABCDEF1234'),
      'ABCDEF1234',
    );
  });

  test('orderBySeries puts E1 before E10', () {
    final names = [
      'Show.S01E10.mkv',
      'Show.S01E02.mkv',
      'Show.S01E01.mkv',
    ];
    final (sorted, start) = CloudPlaybackHelpers.orderBySeries(names, (n) => n);
    expect(sorted.first, 'Show.S01E01.mkv');
    expect(start, 0);
    expect(sorted.last, 'Show.S01E10.mkv');
  });

  test('stream URL validator garbage host is dead, not an exception', () async {
    StreamUrlValidator.clientFactory = () => MockClient((request) async {
      return http.Response('', 404);
    });
    addTearDown(() {
      StreamUrlValidator.clientFactory = http.Client.new;
    });
    final ok = await StreamUrlValidator.isPlayableVideoUrl(
      'https://127.0.0.1:1/nope',
    );
    expect(ok, isFalse);
  });
}
