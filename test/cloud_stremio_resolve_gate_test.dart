import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/cloud/cloud_credentials.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/stremio_tv_resolve_gate.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Torrent _t({String name = 'Show.S01E01.mkv', String hash = 'abc'}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: name,
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var torboxLoads = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'stremio-gate-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    torboxLoads = 0;
  });

  tearDown(ProfileRuntime.debugReset);

  Future<Set<String>> cached(Set<String> hashes) async {
    torboxLoads++;
    return hashes;
  }

  test('ids are realdebrid, not playback debrid', () async {
    expect(CloudProviderId.fromPlaybackId('realdebrid'), isNull);
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'realdebrid',
        selected: 'auto',
        torrent: _t(),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({}),
      ),
      isTrue,
    );
    expect(torboxLoads, 0);
  });

  test('RD skip-blocked is a name gate, not isStremioAvailable', () async {
    await StorageService.saveApiKey('rd-key');
    expect(
      await CloudCredentials.isStremioAvailable(CloudProviderId.debrid),
      isTrue,
    );
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'realdebrid',
        selected: 'auto',
        torrent: _t(name: 'Movie.WEB-DL.1080p.mkv'),
        skipBlockedRd: true,
        torboxCachedHashes: () => cached({}),
      ),
      isFalse,
    );
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'realdebrid',
        selected: 'auto',
        torrent: _t(name: 'Movie.WEB-DL.1080p.mkv'),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({}),
      ),
      isTrue,
    );
  });

  test('explicit TorBox skips the cache loader; auto requires membership', () async {
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'torbox',
        selected: 'torbox',
        torrent: _t(hash: 'abc'),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({'abc'}),
      ),
      isTrue,
    );
    expect(torboxLoads, 0);
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'torbox',
        selected: 'auto',
        torrent: _t(hash: 'ABC'),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({'abc'}),
      ),
      isTrue,
    );
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'torbox',
        selected: 'auto',
        torrent: _t(hash: 'abc'),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({}),
      ),
      isFalse,
    );
  });

  test('PM/AD are toggle-only; picker still wants a key', () async {
    await StorageService.setPremiumizeIntegrationEnabled(true);
    expect(
      await CloudCredentials.isStremioAvailable(CloudProviderId.premiumize),
      isFalse,
    );
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'premiumize',
        selected: 'auto',
        torrent: _t(),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({}),
      ),
      isTrue,
    );
    await StorageService.setAllDebridIntegrationEnabled(false);
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'alldebrid',
        selected: 'auto',
        torrent: _t(),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({}),
      ),
      isFalse,
    );
  });

  test('PikPak and unknown providers always attempt', () async {
    expect(
      await StremioTvResolveGate.canAttempt(
        provider: 'pikpak',
        selected: 'auto',
        torrent: _t(),
        skipBlockedRd: false,
        torboxCachedHashes: () => cached({}),
      ),
      isTrue,
    );
    expect(
      await CloudCredentials.isStremioAvailable(CloudProviderId.pikpak),
      isFalse,
    );
  });
}
