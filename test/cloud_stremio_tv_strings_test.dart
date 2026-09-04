import 'dart:io';

import 'package:debrify/screens/stremio_tv/stremio_tv_dispatch.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/widgets/pipeline_loading_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

/// Fat-port fake that also implements hashed-cache so `is` checks hit
/// (P1 FakeCloudProvider does not implement [CloudCachedHashes]).
class _HashesCapFake extends FakeCloudProvider implements CloudCachedHashes {
  _HashesCapFake({required super.id});
}

class _CheckCacheCapFake extends FakeCloudProvider implements CloudCheckCache {
  _CheckCacheCapFake({required super.id});
}

void _installFakes({
  FakeCloudProvider? debrid,
  FakeCloudProvider? torbox,
  FakeCloudProvider? pikpak,
  FakeCloudProvider? premiumize,
  FakeCloudProvider? alldebrid,
}) {
  CloudProviderRegistry.instance = CloudProviderRegistry([
    debrid ?? FakeCloudProvider(id: CloudProviderId.debrid),
    torbox ?? FakeCloudProvider(id: CloudProviderId.torbox),
    pikpak ?? FakeCloudProvider(id: CloudProviderId.pikpak),
    premiumize ?? FakeCloudProvider(id: CloudProviderId.premiumize),
    alldebrid ?? FakeCloudProvider(id: CloudProviderId.alldebrid),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CloudProviderRegistry.debugReset);

  setUp(_installFakes);

  test('Stremio TV picker ids are playlistStoredProvider, not magicTvId', () {
    expect(CloudProviderId.debrid.playlistStoredProvider, 'realdebrid');
    expect(CloudProviderId.debrid.playbackId, 'debrid');
    expect(CloudProviderId.debrid.magicTvId, 'real_debrid');
    expect(CloudProviderId.debrid.catalogChoice.key, 'realdebrid');
    expect(CloudProviderId.tryParse('realdebrid'), CloudProviderId.debrid);
    expect(CloudProviderId.fromPlaybackId('realdebrid'), isNull);
    expect(CloudProviderId.fromMagicTvId('realdebrid'), isNull);
    expect(CloudProviderId.tryParse('auto'), isNull);
  });

  test(
    'FakeCloudProvider: cache-check is TorBox hashes or Premiumize flags',
    () {
      expect(StremioTvDispatch.hasCacheCheck('torbox'), isTrue);
      expect(StremioTvDispatch.hasCacheCheck('premiumize'), isTrue);
      expect(StremioTvDispatch.hasCacheCheck('realdebrid'), isFalse);
      expect(StremioTvDispatch.hasCacheCheck('alldebrid'), isFalse);
      expect(StremioTvDispatch.hasCacheCheck('pikpak'), isFalse);
      expect(StremioTvDispatch.hasCacheCheck('auto'), isFalse);
      expect(StremioTvDispatch.hasCacheCheck('mystery'), isFalse);
    },
  );

  test('capability is-checks win over FakeCloudProvider.supports table', () {
    _installFakes(
      debrid: _HashesCapFake(id: CloudProviderId.debrid),
      torbox: _CheckCacheCapFake(id: CloudProviderId.torbox),
    );
    expect(
      CloudPortFeature.forProvider(
        CloudProviderId.debrid,
      ).contains(CloudPortFeature.cachedHashes),
      isFalse,
    );
    expect(StremioTvDispatch.hasCacheCheck('realdebrid'), isTrue);
    expect(
      CloudPortFeature.forProvider(
        CloudProviderId.torbox,
      ).contains(CloudPortFeature.checkCache),
      isFalse,
    );
    expect(StremioTvDispatch.hasCacheCheck('torbox'), isTrue);
  });

  test('cache-check debug label: TorBox hashes, otherwise Premiumize', () {
    expect(StremioTvDispatch.cacheCheckDebugLabel('torbox'), 'TorBox');
    expect(StremioTvDispatch.cacheCheckDebugLabel('premiumize'), 'Premiumize');
    expect(StremioTvDispatch.cacheCheckDebugLabel('realdebrid'), 'Premiumize');
    expect(StremioTvDispatch.cacheCheckDebugLabel('auto'), 'Premiumize');
    expect(StremioTvDispatch.cacheCheckDebugLabel('pikpak'), 'Premiumize');
  });

  test('hashed-cache capability on a non-TorBox fake wins the debug label', () {
    _installFakes(debrid: _HashesCapFake(id: CloudProviderId.debrid));
    expect(StremioTvDispatch.cacheCheckDebugLabel('realdebrid'), 'Real-Debrid');
  });

  test('overlay auto/unknown is Debrid/DB, not catalog AUTO', () {
    final auto = StremioTvDispatch.overlayInfo('auto');
    expect(auto.label, 'Debrid');
    expect(auto.code, 'DB');
    expect(auto.color, PipelineLoadingOverlay.accent);
    expect(auto.cacheCheck, isFalse);

    final unknown = StremioTvDispatch.overlayInfo('mystery');
    expect(unknown.label, 'Debrid');
    expect(unknown.code, 'DB');
    expect(unknown.cacheCheck, isFalse);
  });

  test('overlay realdebrid hits RD via tryParse, not fromPlaybackId', () {
    final info = StremioTvDispatch.overlayInfo('realdebrid');
    expect(info.label, 'Real-Debrid');
    expect(info.code, 'RD');
    expect(info.cacheCheck, isFalse);
  });

  test('overlay torbox and premiumize enable the cache-check stage', () {
    expect(StremioTvDispatch.overlayInfo('torbox').cacheCheck, isTrue);
    expect(StremioTvDispatch.overlayInfo('torbox').label, 'TorBox');
    expect(StremioTvDispatch.overlayInfo('torbox').code, 'TB');
    expect(StremioTvDispatch.overlayInfo('premiumize').cacheCheck, isTrue);
    expect(StremioTvDispatch.overlayInfo('premiumize').label, 'Premiumize');
    expect(StremioTvDispatch.overlayInfo('premiumize').code, 'PM');
  });

  test(
    'Stremio TV screens have no provider-id string literals outside comments',
    () {
      final files = Directory('lib/screens/stremio_tv')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      final leftover = <String>[];
      for (final file in files) {
        final source = file.readAsStringSync();
        final withoutBlock = source.replaceAll(
          RegExp(r'/\*.*?\*/', dotAll: true),
          '',
        );
        final withoutLine = withoutBlock
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        final hits = RegExp(
          r"'(realdebrid|real_debrid|torbox|premiumize|alldebrid|pikpak)'",
        ).allMatches(withoutLine).map((m) => m.group(0)).toList();
        if (hits.isNotEmpty) {
          leftover.add('${file.path}: $hits');
        }
      }
      expect(leftover, isEmpty, reason: 'string-match leftovers: $leftover');
      final screen = File(
        'lib/screens/stremio_tv/stremio_tv_screen.dart',
      ).readAsStringSync();
      expect(screen.contains('StremioTvDispatch.overlayInfo'), isTrue);
      expect(screen.contains('StremioTvDispatch.cacheCheckDebugLabel'), isTrue);
    },
  );
}
