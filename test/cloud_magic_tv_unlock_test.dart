import 'package:debrify/services/cloud/alldebrid_cloud_provider.dart';
import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_magic_tv_unlock.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/pikpak_cloud_provider.dart';
import 'package:debrify/services/cloud/premiumize_cloud_provider.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

/// Fat-port fake plus the RD Magic TV capability so registry `is` checks hit.
/// [FakeCloudProvider] does not implement [CloudMagicTvRdUnlock] (no fat-port
/// throw-stub for this feature).
class _RdUnlockFake extends FakeCloudProvider implements CloudMagicTvRdUnlock {
  _RdUnlockFake() : super(id: CloudProviderId.debrid);

  Map<String, dynamic> unrestrictResult = const {
    'download': 'https://rd/dl',
    'filesize': 80 * 1024 * 1024,
  };
  Map<String, dynamic> preferVideosResult = const {
    'downloadLink': 'https://rd/play',
    'torrentId': 'tid',
    'links': <String>['https://rd/locked'],
  };
  int unrestrictCount = 0;
  int preferVideosCount = 0;
  String? lastLink;

  @override
  Future<Map<String, dynamic>> unrestrictLink(String link) async {
    unrestrictCount++;
    lastLink = link;
    return unrestrictResult;
  }

  @override
  Future<Map<String, dynamic>> addTorrentPreferVideos(String magnet) async {
    preferVideosCount++;
    lastMagnet = magnet;
    return preferVideosResult;
  }
}

class _AdUnlockFake extends FakeCloudProvider implements CloudMagicTvAdUnlock {
  _AdUnlockFake() : super(id: CloudProviderId.alldebrid);

  String unlockResult = 'https://ad/play';
  int adUnlockCount = 0;
  String? lastLocked;

  @override
  Future<String> unlockLink(String lockedLink) async {
    adUnlockCount++;
    lastLocked = lockedLink;
    return unlockResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'magic-tv-unlock-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('unsupported providers are not Magic TV unlock capabilities', () {
    expect(const TorboxCloudProvider(), isNot(isA<CloudMagicTvRdUnlock>()));
    expect(const TorboxCloudProvider(), isNot(isA<CloudMagicTvAdUnlock>()));
    expect(const PremiumizeCloudProvider(), isNot(isA<CloudMagicTvRdUnlock>()));
    expect(const PikPakCloudProvider(), isNot(isA<CloudMagicTvAdUnlock>()));
    expect(
      const RealDebridCloudProvider().supports(
        CloudPortFeature.magicTvRdUnlock,
      ),
      isTrue,
    );
    expect(
      const AllDebridCloudProvider().supports(CloudPortFeature.magicTvAdUnlock),
      isTrue,
    );
  });

  test(
    'missing RD key throws CloudMissingApiKey — port hides apiKey',
    () async {
      await expectLater(
        const RealDebridCloudProvider().unrestrictLink('https://rd/locked'),
        throwsA(isA<CloudMissingApiKey>()),
      );
      await expectLater(
        const RealDebridCloudProvider().addTorrentPreferVideos(
          'magnet:?xt=urn:btih:abc',
        ),
        throwsA(isA<CloudMissingApiKey>()),
      );
      await expectLater(
        CloudProviderRegistry.instance.unrestrictLink('https://rd/locked'),
        throwsA(isA<CloudMissingApiKey>()),
      );
    },
  );

  test(
    'missing AD key throws CloudMissingApiKey — port hides apiKey',
    () async {
      await expectLater(
        const AllDebridCloudProvider().unlockLink('https://ad/locked'),
        throwsA(isA<CloudMissingApiKey>()),
      );
      await expectLater(
        CloudProviderRegistry.instance.unlockLink('https://ad/locked'),
        throwsA(isA<CloudMissingApiKey>()),
      );
    },
  );

  test('saved RD key is read via CloudCredentials, not a method arg', () async {
    await StorageService.saveApiKey('rd-from-prefs');
    // Key is present so the adapter will call HTTP. We only pin that the
    // port method takes a link, not an apiKey — the missing-key path above
    // already proved the lookup. With a key, unrestrict hits the network;
    // accept any exception that is not CloudMissingApiKey.
    try {
      await const RealDebridCloudProvider().unrestrictLink('https://rd/locked');
      fail('expected HTTP/network error with a saved key');
    } on CloudMissingApiKey {
      fail('port looked up an empty key despite saveApiKey');
    } catch (_) {
      // Origin DebridService.unrestrictLink throws on network/HTTP.
    }
  });

  test('registry without RD adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.torbox),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.unrestrictLink('https://rd/locked'),
      throwsA(isA<CloudUnsupported>()),
    );
    await expectLater(
      CloudProviderRegistry.instance.addTorrentPreferVideos('magnet:x'),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry without AD adapter throws CloudUnsupported', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
    ]);
    await expectLater(
      CloudProviderRegistry.instance.unlockLink('https://ad/locked'),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test(
    'registry RD fake returns the Magic TV unrestrict / PreferVideos maps',
    () async {
      final rd = _RdUnlockFake();
      CloudProviderRegistry.instance = CloudProviderRegistry([
        rd,
        FakeCloudProvider(id: CloudProviderId.alldebrid),
      ]);
      final unrestrict = await CloudProviderRegistry.instance.unrestrictLink(
        'https://rd/locked',
      );
      expect(unrestrict['download'], 'https://rd/dl');
      expect(unrestrict['filesize'], 80 * 1024 * 1024);
      expect(rd.unrestrictCount, 1);
      expect(rd.lastLink, 'https://rd/locked');

      final added = await CloudProviderRegistry.instance.addTorrentPreferVideos(
        'magnet:?xt=urn:btih:abc',
      );
      expect(added['downloadLink'], 'https://rd/play');
      expect(added['torrentId'], 'tid');
      expect(added['links'], ['https://rd/locked']);
      expect(rd.preferVideosCount, 1);
      expect(rd.lastMagnet, 'magnet:?xt=urn:btih:abc');
    },
  );

  test('registry AD fake returns the Magic TV unlock String', () async {
    final ad = _AdUnlockFake();
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.debrid),
      ad,
    ]);
    expect(
      await CloudProviderRegistry.instance.unlockLink('https://ad/locked'),
      'https://ad/play',
    );
    expect(ad.adUnlockCount, 1);
    expect(ad.lastLocked, 'https://ad/locked');
  });

  test('plain FakeCloudProvider is not the Magic TV unlock capability', () {
    final fake = FakeCloudProvider(id: CloudProviderId.debrid);
    expect(fake, isNot(isA<CloudMagicTvRdUnlock>()));
    expect(fake.supports(CloudPortFeature.magicTvRdUnlock), isTrue);
    expect(fake.supports(CloudPortFeature.magicTvAdUnlock), isFalse);
  });
}
