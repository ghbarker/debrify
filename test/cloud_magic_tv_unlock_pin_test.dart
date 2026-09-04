import 'dart:io';

import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the Magic TV RD/AD HTTP call shapes *before* they move onto a
/// cloud-port capability. Drives the origin functions / call sites, not a
/// new adapter file.
///
/// Quirks:
/// - [DebridService.unrestrictLink] returns a Map; Magic TV reads
///   `unrestrict['download']` and `_rdLinkPassesSizeRules` reads
///   `unrestrict['filesize']`.
/// - [DebridService.addTorrentToDebridPreferVideos] returns a Map;
///   Magic TV reads `downloadLink`, `torrentId`, `links`.
/// - [AllDebridService.unlockLink] returns a String URL.
/// - Magic TV passes `apiKey` as the first argument. The later port hides
///   that behind [CloudCredentials].
/// - Existing [CloudUnlock.unlockPlaybackEntry] / [CloudMagnetAdd.addMagnet]
///   / [CloudMagicTvLockedLinks] are different dialects — do not unify.
void main() {
  late String debridSrc;
  late String alldebridSrc;
  late String magicTvSrc;
  late String capabilitiesSrc;

  setUpAll(() {
    String read(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    debridSrc = read('lib/services/debrid_service.dart');
    alldebridSrc = read('lib/services/alldebrid_service.dart');
    magicTvSrc = read('lib/screens/magic_tv_screen.dart');
    capabilitiesSrc = read('lib/services/cloud/cloud_capabilities.dart');
  });

  test('RD unrestrictLink is (apiKey, link) → Map with download', () {
    expect(
      debridSrc,
      contains(
        'static Future<Map<String, dynamic>> unrestrictLink(\n'
        '    String apiKey,\n'
        '    String link,\n'
        '  )',
      ),
    );
    expect(
      DebridService.unrestrictLink,
      isA<Future<Map<String, dynamic>> Function(String, String)>(),
    );
  });

  test('RD PreferVideos is (apiKey, magnet) → Map with Magic TV keys', () {
    expect(
      debridSrc,
      contains(
        'static Future<Map<String, dynamic>> addTorrentToDebridPreferVideos(\n'
        '    String apiKey,\n'
        '    String magnetLink,\n'
        '  )',
      ),
    );
    expect(
      DebridService.addTorrentToDebridPreferVideos,
      isA<Future<Map<String, dynamic>> Function(String, String)>(),
    );
    final preferVideos = debridSrc.substring(
      debridSrc.indexOf('addTorrentToDebridPreferVideos'),
    );
    // Both success returns (all-videos and largest-video fallback) carry
    // the keys Magic TV reads. fileSelection/files/updatedInfo stay on the
    // origin but Magic TV does not use them at the PreferVideos sites.
    expect(
      "'downloadLink': downloadLink,".allMatches(preferVideos).length,
      2,
    );
    expect("'torrentId': torrentId,".allMatches(preferVideos).length, 2);
    expect("'links': links,".allMatches(preferVideos).length, 2);
  });

  test('AD unlockLink is (apiKey, link) → String URL', () {
    expect(
      alldebridSrc,
      contains(
        'static Future<String> unlockLink(String apiKey, String link) async {',
      ),
    );
    expect(
      AllDebridService.unlockLink,
      isA<Future<String> Function(String, String)>(),
    );
  });

  test('Magic TV reads unrestrict download + filesize, not a String URL', () {
    expect(magicTvSrc.contains("unrestrict['download']"), isTrue);
    expect(magicTvSrc.contains("unrestrict['filesize']"), isTrue);
    expect(
      'DebridService.unrestrictLink'.allMatches(magicTvSrc).length,
      6,
    );
    // First arg is the in-scope apiKey, not a credentials lookup.
    expect(magicTvSrc, contains('DebridService.unrestrictLink(\n'
        '                apiKeyEarly,'));
    expect(magicTvSrc, contains('DebridService.unrestrictLink(apiKey, link)'));
  });

  test('Magic TV PreferVideos reads downloadLink / torrentId / links', () {
    expect(
      'addTorrentToDebridPreferVideos'.allMatches(magicTvSrc).length,
      2,
      reason: 'requestMagicNext and _playNextFromQueue — not locked-link walk',
    );
    expect(magicTvSrc.contains("result['downloadLink'] as String?"), isTrue);
    expect(
      magicTvSrc.contains("result['torrentId'] as String? ?? ''"),
      isTrue,
    );
    expect(
      magicTvSrc.contains("result['links'] as List<dynamic>? ?? const []"),
      isTrue,
    );
    expect(
      magicTvSrc,
      contains(
        'DebridService.addTorrentToDebridPreferVideos(\n'
        '              apiKey,\n'
        '              magnetLink,',
      ),
    );
  });

  test('Magic TV AD unlockLink is assigned to a String URL', () {
    expect(
      'AllDebridService.unlockLink'.allMatches(magicTvSrc).length,
      greaterThanOrEqualTo(5),
    );
    expect(
      magicTvSrc,
      contains('final videoUrl = await AllDebridService.unlockLink(apiKey, link)'),
    );
    expect(
      magicTvSrc,
      contains('videoUrl = await AllDebridService.unlockLink(apiKey, headLink)'),
    );
  });

  test('existing port dialects are not these Magic TV maps / String', () {
    expect(
      capabilitiesSrc,
      contains('Future<String> unlockPlaybackEntry(PlaylistEntry entry);'),
    );
    expect(
      capabilitiesSrc,
      contains(
        'Future<CloudPlaybackResult> addMagnet(String magnet, Torrent torrent);',
      ),
    );
    expect(
      capabilitiesSrc,
      contains(
        'Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks(',
      ),
    );
    expect(capabilitiesSrc.contains('unrestrictLink'), isFalse);
    expect(capabilitiesSrc.contains('addTorrentPreferVideos'), isFalse);
    expect(capabilitiesSrc.contains('unlockLink'), isFalse);
  });
}
