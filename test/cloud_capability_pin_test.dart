import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/alldebrid_cloud_provider.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_credentials.dart';
import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/magic_tv_prepare_args.dart';
import 'package:debrify/services/cloud/pikpak_cloud_provider.dart';
import 'package:debrify/services/cloud/premiumize_cloud_provider.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Torrent _t() => Torrent(
  rowid: 0,
  infohash: 'abc',
  name: 'Show.S01E01.mkv',
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'test',
);

MagicTvPrepareRequest _req() => MagicTvPrepareRequest(
  torrent: _t(),
  log: (_) {},
  seenKeys: <String>{},
  sizeMatchesBytes: (_) => true,
  hasSizeFilter: false,
  minVideoSizeBytes: 50 * 1024 * 1024,
);

/// Pins pre-P1 quirks: feature table vs throw-stubs, playlist null vs
/// unsupported, and the credential dialects.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'capability-pin-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(ProfileRuntime.debugReset);

  test('feature table: playlist vs Magic TV vs cache dialects', () {
    expect(CloudPortFeature.forProvider(CloudProviderId.debrid), {
      CloudPortFeature.playlistEntry,
      CloudPortFeature.magicTvLockedLinks,
      CloudPortFeature.magicTvRdUnlock,
    });
    expect(CloudPortFeature.forProvider(CloudProviderId.alldebrid), {
      CloudPortFeature.playlistEntry,
      CloudPortFeature.magicTvLockedLinks,
      CloudPortFeature.magicTvAdUnlock,
    });
    expect(CloudPortFeature.forProvider(CloudProviderId.pikpak), {
      CloudPortFeature.magicTvPrepare,
    });
    expect(
      const RealDebridCloudProvider().supports(CloudPortFeature.playlistEntry),
      isTrue,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.playlistEntry),
      isFalse,
    );
    expect(
      const PikPakCloudProvider().supports(CloudPortFeature.magicTvPrepare),
      isTrue,
    );
    expect(
      const AllDebridCloudProvider().supports(CloudPortFeature.magicTvPrepare),
      isFalse,
    );
  });

  test(
    'unsupported playlist is CloudUnsupported, empty RD link is null',
    () async {
      expect(
        () => const PremiumizeCloudProvider().resolvePlaylistEntry(
          const PlaylistEntry(url: '', title: 'a', premiumizePath: '/x'),
        ),
        throwsA(isA<CloudUnsupported>()),
      );
      expect(
        () => const PikPakCloudProvider().resolvePlaylistEntry(
          const PlaylistEntry(url: '', title: 'a', pikpakFileId: 'file'),
        ),
        throwsA(isA<CloudUnsupported>()),
      );
      expect(
        await const RealDebridCloudProvider().resolvePlaylistEntry(
          const PlaylistEntry(url: '', title: 'a'),
        ),
        isNull,
      );
      expect(
        await const RealDebridCloudProvider().resolvePlaylist(
          const PlaylistEntry(url: '', title: 'a', restrictedLink: ''),
        ),
        isA<CloudPlaylistMiss>(),
      );
      expect(const PremiumizeCloudProvider(), isNot(isA<CloudPlaylist>()));
      expect(const PikPakCloudProvider(), isNot(isA<CloudPlaylist>()));
    },
  );

  test('unsupported Magic TV methods throw CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().prepareMagicTv(_req()),
      throwsA(isA<CloudUnsupported>()),
    );
    expect(
      () => const TorboxCloudProvider().prepareMagicTvLockedLinks(_req()),
      throwsA(isA<CloudUnsupported>()),
    );
    expect(
      () => const AllDebridCloudProvider().prepareMagicTv(_req()),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test(
    'credential dialects: playback key-only, magnet key+toggle, picker split',
    () async {
      await StorageService.saveApiKey('rd-key');
      await StorageService.setRealDebridIntegrationEnabled(false);
      expect(
        await CloudCredentials.configured(
          CloudProviderId.debrid,
          CloudSurface.playback,
        ),
        isTrue,
      );
      expect(
        await CloudCredentials.configured(
          CloudProviderId.debrid,
          CloudSurface.magnet,
        ),
        isFalse,
      );
      expect(
        await CloudCredentials.configured(
          CloudProviderId.debrid,
          CloudSurface.stremioPicker,
        ),
        isTrue,
      );

      await StorageService.savePremiumizeApiKey('pm-key');
      await StorageService.setPremiumizeIntegrationEnabled(false);
      expect(
        await CloudCredentials.configured(
          CloudProviderId.premiumize,
          CloudSurface.playback,
        ),
        isTrue,
      );
      expect(
        await CloudCredentials.configured(
          CloudProviderId.premiumize,
          CloudSurface.stremioPicker,
        ),
        isFalse,
      );
      expect(
        await CloudCredentials.configured(
          CloudProviderId.premiumize,
          CloudSurface.stremioResolve,
        ),
        isFalse,
      );
      await StorageService.setPremiumizeIntegrationEnabled(true);
      expect(
        await CloudCredentials.configured(
          CloudProviderId.premiumize,
          CloudSurface.stremioResolve,
        ),
        isTrue,
      );
    },
  );
}
