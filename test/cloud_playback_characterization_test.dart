import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/pack_negative_cache.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudProviderId stored vs playback keys', () {
    test('Real-Debrid maps rd <-> debrid', () {
      expect(CloudProviderId.parse('rd').playbackId, 'debrid');
      expect(CloudProviderId.parse('debrid').storedId, 'rd');
      expect(CloudProviderId.parse('realdebrid').playbackId, 'debrid');
      expect(TorrentPlaybackService.storedProviderKey('debrid'), 'rd');
      expect(TorrentPlaybackService.storedProviderKey('torbox'), 'torbox');
    });

    test('credential keys match historical StorageService names', () {
      expect(CloudProviderId.debrid.credentialKey, 'real_debrid_api_key');
      expect(CloudProviderId.torbox.credentialKey, 'torbox_api_key');
      expect(CloudProviderId.premiumize.credentialKey, 'premiumize_api_key');
      expect(CloudProviderId.alldebrid.credentialKey, 'alldebrid_api_key');
      expect(CloudProviderId.pikpak.credentialKey, 'pikpak_email');
    });

    test('playback precedence keeps Premiumize before PikPak', () {
      final ids = CloudProviderId.playbackPrecedence.map((e) => e.playbackId);
      expect(ids.toList(), [
        'debrid',
        'torbox',
        'premiumize',
        'alldebrid',
        'pikpak',
      ]);
      expect(
        ids.toList().indexOf('premiumize'),
        lessThan(ids.toList().indexOf('pikpak')),
      );
    });
  });

  group('PackNegativeCache', () {
    late PackNegativeCache cache;
    late DateTime now;
    final rules = QuickPlayRules.debrifyDefault(isMovie: false);

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      cache = PackNegativeCache(now: () => now, cap: 3);
    });

    test('failedPackCacheHours <= 0 never remembers', () {
      final off = rules.copyWith(failedPackCacheHours: 0);
      cache.markNoPack('tt1', 1, 'debrid', off, const Duration(hours: 6));
      expect(cache.recentlyNoPack('tt1', 1, 'debrid', off), isFalse);
    });

    test('TTL expiry forgets a miss', () {
      cache.markNoPack('tt1', 1, 'debrid', rules, const Duration(hours: 1));
      expect(cache.recentlyNoPack('tt1', 1, 'debrid', rules), isTrue);
      now = now.add(const Duration(hours: 2));
      expect(cache.recentlyNoPack('tt1', 1, 'debrid', rules), isFalse);
    });

    test('season and provider are part of the key', () {
      cache.markNoPack('tt1', 1, 'debrid', rules, const Duration(hours: 1));
      expect(cache.recentlyNoPack('tt1', 2, 'debrid', rules), isFalse);
      expect(cache.recentlyNoPack('tt1', 1, 'torbox', rules), isFalse);
    });

    test('cap drops the oldest entry', () {
      cache.markNoPack('a', 1, 'debrid', rules, const Duration(hours: 1));
      now = now.add(const Duration(minutes: 1));
      cache.markNoPack('b', 1, 'debrid', rules, const Duration(hours: 1));
      now = now.add(const Duration(minutes: 1));
      cache.markNoPack('c', 1, 'debrid', rules, const Duration(hours: 1));
      now = now.add(const Duration(minutes: 1));
      cache.markNoPack('d', 1, 'debrid', rules, const Duration(hours: 1));
      expect(cache.debugEntries.length, 3);
      expect(cache.recentlyNoPack('a', 1, 'debrid', rules), isFalse);
      expect(cache.recentlyNoPack('d', 1, 'debrid', rules), isTrue);
    });
  });
}
