import 'dart:io';

import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supplemental source/type inventory only, not behavioral origin proof.
/// Live host pins include magic_tv_captured_unlock_origin_test.dart. Captured
/// capability calls preserve the key; these are not key-rereading cloud ports.
///
/// Quirks:
/// - [DebridService.unrestrictLink] returns a Map; Magic TV reads
///   `unrestrict['download']` and the size-rules helper reads
///   `unrestrict['filesize']`.
/// - [DebridService.addTorrentToDebridPreferVideos] returns a Map;
///   Magic TV reads `downloadLink`, `torrentId`, `links`.
/// - [AllDebridService.unlockLink] returns a String URL.
/// - Magic TV passes `apiKey` as the first argument to captured capabilities.
///   The separate key-rereading APIs retain their CloudCredentials behavior.
/// - Existing [CloudUnlock.unlockPlaybackEntry] / [CloudMagnetAdd.addMagnet]
///   / [CloudMagicTvLockedLinks] are different dialects — do not unify.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Host plus the extracted cache warmer so `unrestrict['filesize']` still
/// resolves after M1-1 moved `_rdLinkPassesSizeRules`.
String _magicTvSources() {
  var host = _read('lib/screens/magic_tv_screen.dart');
  const aliases = {
    'rdUnlock.unrestrictLinkWithKey': 'DebridService.unrestrictLink',
    'rdUnlock.addTorrentPreferVideosWithKey': 'DebridService.addTorrentToDebridPreferVideos',
    'adUnlock.unlockLinkWithKey': 'AllDebridService.unlockLink',
  };
  // Check exact fixed adapter registration and nonasync service forwarding.
  // No file, method-body or invocation-count exemption.
  for (final registration in const [
    'rdUnlock: const RealDebridCloudProvider(),',
    'adUnlock: const AllDebridCloudProvider(),',
  ]) {
    expect(registration.allMatches(host).length, 1);
    host = host.replaceFirst(registration, '');
  }
  final rd = _read('lib/services/cloud/rd_cloud_provider.dart');
  final ad = _read('lib/services/cloud/alldebrid_cloud_provider.dart');
  for (final forward in const [
    'Future<Map<String, dynamic>> unrestrictLinkWithKey(String apiKey, String link) =>\n'
        '      DebridService.unrestrictLink(apiKey, link);',
    'Future<Map<String, dynamic>> addTorrentPreferVideosWithKey(\n'
        '    String apiKey,\n'
        '    String magnet,\n'
        '  ) => DebridService.addTorrentToDebridPreferVideos(apiKey, magnet);',
  ]) {
    expect(forward.allMatches(rd).length, 1);
  }
  expect(
    ('Future<String> unlockLinkWithKey(String apiKey, String link) =>\n'
        '      AllDebridService.unlockLink(apiKey, link);').allMatches(ad).length,
    1,
  );
  final buf = StringBuffer(host);
  buf.writeln(_read('lib/screens/debrify_tv/channel_switch_flow.dart'));
  buf.writeln(_read('lib/services/debrify_tv/channel_cache_warmer.dart'));
  buf.writeln(_read('lib/services/debrify_tv/queue_prefetcher.dart'));
  for (final provider in [
    'provider_watch_flow', 'torbox_watch_flow',
    'pikpak_watch_flow', 'premiumize_watch_flow', 'alldebrid_watch_flow',
    'cached_locked_watch_programme',
  ]) {
    var flow = _read('lib/screens/debrify_tv/watch/$provider.dart');
    for (final alias in aliases.entries) {
      flow = flow.replaceAll('host.${alias.key}(', '${alias.value}(');
    }
    buf.writeln(flow);
  }
  // Retain all original assertions below; canonicalize only formatter layout
  // of these exact calls, never argument expressions, values or call counts.
  return buf.toString()
      .replaceAllMapped(
        RegExp(r'DebridService\.unrestrictLink\(\s*(apiKeyEarly),'),
        (m) => 'DebridService.unrestrictLink(\n                ${m[1]},',
      )
      .replaceAllMapped(
        RegExp(r'DebridService\.addTorrentToDebridPreferVideos\(\s*(apiKey),\s*(magnetLink),'),
        (m) => 'DebridService.addTorrentToDebridPreferVideos(\n              ${m[1]},\n              ${m[2]},',
      );
}

void main() {
  late String debridSrc;
  late String alldebridSrc;
  late String magicTvSrc;
  late String capabilitiesSrc;

  setUpAll(() {
    debridSrc = _read('lib/services/debrid_service.dart');
    alldebridSrc = _read('lib/services/alldebrid_service.dart');
    magicTvSrc = _magicTvSources();
    capabilitiesSrc = _read('lib/services/cloud/cloud_capabilities.dart');
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
    expect("'downloadLink': downloadLink,".allMatches(preferVideos).length, 2);
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
    expect('DebridService.unrestrictLink'.allMatches(magicTvSrc).length, 6);
    // First arg is the in-scope apiKey, not a credentials lookup.
    expect(
      magicTvSrc,
      contains(
        'DebridService.unrestrictLink(\n'
        '                apiKeyEarly,',
      ),
    );
    expect(magicTvSrc, contains('DebridService.unrestrictLink(apiKey, link)'));
  });

  test('Magic TV PreferVideos reads downloadLink / torrentId / links', () {
    expect(
      'addTorrentToDebridPreferVideos'.allMatches(magicTvSrc).length,
      2,
      reason: 'requestMagicNext and _playNextFromQueue — not locked-link walk',
    );
    expect(magicTvSrc.contains("result['downloadLink'] as String?"), isTrue);
    expect(magicTvSrc.contains("result['torrentId'] as String? ?? ''"), isTrue);
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
      contains(
        'final videoUrl = await AllDebridService.unlockLink(apiKey, link)',
      ),
    );
    expect(
      magicTvSrc,
      contains(
        'videoUrl = await AllDebridService.unlockLink(apiKey, headLink)',
      ),
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
      contains('Future<MagicTvLockedBatch?> prepareMagicTvLockedLinks('),
    );
    expect(capabilitiesSrc.contains('unrestrictLink'), isFalse);
    expect(capabilitiesSrc.contains('addTorrentPreferVideos'), isFalse);
    expect(capabilitiesSrc.contains('unlockLink'), isFalse);
  });
}
