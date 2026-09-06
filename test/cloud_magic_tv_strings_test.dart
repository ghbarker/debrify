import 'dart:io';

import 'package:debrify/screens/magic_tv_screen.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/magic_tv_prepare_args.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

/// Fat-port fake that also implements the prepare capability so `is` checks
/// hit (P1 FakeCloudProvider does not implement [CloudMagicTvPrepare]).
class _PrepareCapFake extends FakeCloudProvider implements CloudMagicTvPrepare {
  _PrepareCapFake({required super.id})
    : super(
        magicTvResult: const MagicTvPrepared(
          streamUrl: 'https://cap/tv',
          title: 'ep',
          hasMore: false,
        ),
      );
}

class _LockedCapFake extends FakeCloudProvider
    implements CloudMagicTvLockedLinks {
  _LockedCapFake({required super.id});
}

class _HashesCapFake extends FakeCloudProvider implements CloudCachedHashes {
  _HashesCapFake({required super.id});
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

const _watchFlowPaths = <String>[
  'lib/services/debrify_tv/queue_prefetcher.dart',
  'lib/screens/debrify_tv/channel_switch_flow.dart',
  'lib/screens/debrify_tv/watch/alldebrid_watch_flow.dart',
  'lib/screens/debrify_tv/watch/pikpak_watch_flow.dart',
  'lib/screens/debrify_tv/watch/premiumize_watch_flow.dart',
  'lib/screens/debrify_tv/watch/provider_watch_flow.dart',
  'lib/screens/debrify_tv/watch/real_debrid_watch_flow.dart',
  'lib/screens/debrify_tv/watch/torbox_watch_flow.dart',
  'lib/screens/debrify_tv/watch/windowed_watch_queue.dart',
  'lib/screens/debrify_tv/watch/quick_windowed_watch_programme.dart',
  'lib/screens/debrify_tv/watch/cached_windowed_watch_programme.dart',
];

List<String?> _providerLiteralHits(String source) {
  final withoutBlock = source.replaceAll(
    RegExp(r'/\*.*?\*/', dotAll: true),
    '',
  );
  final withoutLine = withoutBlock
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  return RegExp(
    r"'(realdebrid|real_debrid|torbox|premiumize|alldebrid|pikpak)'",
  ).allMatches(withoutLine).map((m) => m.group(0)).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CloudProviderRegistry.debugReset);

  setUp(_installFakes);

  test(
    'Magic TV chip ids are magicTvId, not playback or playlist spellings',
    () {
      expect(CloudProviderId.debrid.magicTvId, 'real_debrid');
      expect(CloudProviderId.debrid.playbackId, 'debrid');
      expect(CloudProviderId.debrid.playlistStoredProvider, 'realdebrid');
      expect(
        CloudProviderId.fromMagicTvId('real_debrid'),
        CloudProviderId.debrid,
      );
      expect(CloudProviderId.fromMagicTvId('debrid'), isNull);
      expect(CloudProviderId.fromMagicTvId('realdebrid'), isNull);
      expect(CloudProviderId.fromMagicTvId('rd'), isNull);
    },
  );

  test('watchId unknown and playback spelling fall through to Real-Debrid', () {
    expect(MagicTvDispatch.watchId('real_debrid'), CloudProviderId.debrid);
    expect(MagicTvDispatch.watchId('torbox'), CloudProviderId.torbox);
    expect(MagicTvDispatch.watchId('pikpak'), CloudProviderId.pikpak);
    expect(MagicTvDispatch.watchId('premiumize'), CloudProviderId.premiumize);
    expect(MagicTvDispatch.watchId('alldebrid'), CloudProviderId.alldebrid);
    expect(MagicTvDispatch.watchId('mystery'), CloudProviderId.debrid);
    expect(MagicTvDispatch.watchId('debrid'), CloudProviderId.debrid);
    expect(MagicTvDispatch.watchId('realdebrid'), CloudProviderId.debrid);
  });

  test('FakeCloudProvider: prepare vs locked-links vs cached-hashes', () {
    expect(MagicTvDispatch.usesPrepare('real_debrid'), isFalse);
    expect(MagicTvDispatch.usesLockedLinks('real_debrid'), isTrue);
    expect(MagicTvDispatch.usesCachedHashes('real_debrid'), isFalse);

    expect(MagicTvDispatch.usesPrepare('alldebrid'), isFalse);
    expect(MagicTvDispatch.usesLockedLinks('alldebrid'), isTrue);
    expect(MagicTvDispatch.usesCachedHashes('alldebrid'), isFalse);

    expect(MagicTvDispatch.usesPrepare('torbox'), isTrue);
    expect(MagicTvDispatch.usesLockedLinks('torbox'), isFalse);
    expect(MagicTvDispatch.usesCachedHashes('torbox'), isTrue);

    expect(MagicTvDispatch.usesPrepare('pikpak'), isTrue);
    expect(MagicTvDispatch.usesLockedLinks('pikpak'), isFalse);
    expect(MagicTvDispatch.usesCachedHashes('pikpak'), isFalse);

    expect(MagicTvDispatch.usesPrepare('premiumize'), isTrue);
    expect(MagicTvDispatch.usesLockedLinks('premiumize'), isFalse);
    expect(MagicTvDispatch.usesCachedHashes('premiumize'), isFalse);

    expect(MagicTvDispatch.usesPrepare('mystery'), isFalse);
    expect(MagicTvDispatch.usesLockedLinks('debrid'), isFalse);
  });

  test('capability is-checks win over FakeCloudProvider.supports table', () {
    _installFakes(
      debrid: _PrepareCapFake(id: CloudProviderId.debrid),
      torbox: _LockedCapFake(id: CloudProviderId.torbox),
      premiumize: _HashesCapFake(id: CloudProviderId.premiumize),
    );
    expect(
      CloudPortFeature.forProvider(
        CloudProviderId.debrid,
      ).contains(CloudPortFeature.magicTvPrepare),
      isFalse,
    );
    expect(MagicTvDispatch.usesPrepare('real_debrid'), isTrue);
    expect(
      CloudPortFeature.forProvider(
        CloudProviderId.torbox,
      ).contains(CloudPortFeature.magicTvLockedLinks),
      isFalse,
    );
    expect(MagicTvDispatch.usesLockedLinks('torbox'), isTrue);
    expect(
      CloudPortFeature.forProvider(
        CloudProviderId.premiumize,
      ).contains(CloudPortFeature.cachedHashes),
      isFalse,
    );
    expect(MagicTvDispatch.usesCachedHashes('premiumize'), isTrue);
  });

  test('isSelectable unknown falls through to Real-Debrid availability', () {
    expect(
      MagicTvDispatch.isSelectable(
        'torbox',
        realDebrid: false,
        torbox: true,
        pikpak: false,
        premiumize: false,
        allDebrid: false,
      ),
      isTrue,
    );
    expect(
      MagicTvDispatch.isSelectable(
        'mystery',
        realDebrid: true,
        torbox: false,
        pikpak: false,
        premiumize: false,
        allDebrid: false,
      ),
      isTrue,
    );
    expect(
      MagicTvDispatch.isSelectable(
        'alldebrid',
        realDebrid: true,
        torbox: true,
        pikpak: true,
        premiumize: true,
        allDebrid: false,
      ),
      isFalse,
    );
  });

  test(
    'next-channel quirks: Premiumize and AllDebrid omitted on some launches',
    () {
      const exceptAd = MagicTvNextChannelQuirk.exceptAllDebrid;
      const rdTbPp = MagicTvNextChannelQuirk.rdTorboxPikPak;
      const allKnown = MagicTvNextChannelQuirk.allKnown;

      expect(
        MagicTvDispatch.allowsNextChannel('real_debrid', exceptAd),
        isTrue,
      );
      expect(MagicTvDispatch.allowsNextChannel('torbox', exceptAd), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('pikpak', exceptAd), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('premiumize', exceptAd), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('alldebrid', exceptAd), isFalse);

      expect(MagicTvDispatch.allowsNextChannel('real_debrid', rdTbPp), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('torbox', rdTbPp), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('pikpak', rdTbPp), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('premiumize', rdTbPp), isFalse);
      expect(MagicTvDispatch.allowsNextChannel('alldebrid', rdTbPp), isFalse);

      expect(
        MagicTvDispatch.allowsNextChannel('real_debrid', allKnown),
        isTrue,
      );
      expect(MagicTvDispatch.allowsNextChannel('premiumize', allKnown), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('alldebrid', allKnown), isTrue);
      expect(MagicTvDispatch.allowsNextChannel('debrid', allKnown), isFalse);
      expect(MagicTvDispatch.allowsNextChannel('mystery', exceptAd), isFalse);
    },
  );

  test(
    'locked-links capability is the channel-switch prefetch restart gate',
    () {
      expect(MagicTvDispatch.usesLockedLinks('real_debrid'), isTrue);
      expect(MagicTvDispatch.usesLockedLinks('alldebrid'), isTrue);
      expect(MagicTvDispatch.usesLockedLinks('torbox'), isFalse);
      expect(MagicTvDispatch.usesLockedLinks('pikpak'), isFalse);
      expect(MagicTvDispatch.usesLockedLinks('premiumize'), isFalse);
    },
  );

  test(
    'Magic TV screen has no provider-id string literals outside comments',
    () {
      // Supplemental inventory follows the host's six relocated flow bodies.
      final source = ['lib/screens/magic_tv_screen.dart', ..._watchFlowPaths]
          .map((path) => File(path).readAsStringSync())
          .join('\n');
      final hits = _providerLiteralHits(source);
      expect(hits, isEmpty, reason: 'string-match leftovers: $hits');
      expect(source.contains('MagicTvDispatch.watchId'), isTrue);
      expect(source.contains('MagicTvDispatch.usesLockedLinks'), isTrue);
      expect(source.contains('MagicTvDispatch.usesCachedHashes'), isTrue);
      expect(source.contains('MagicTvDispatch.allowsNextChannel'), isTrue);
      expect(source.contains('CloudProviderId.fromMagicTvId'), isTrue);
    },
  );
  test('provider literal drift in every watch flow trips the inventory', () {
    for (final path in _watchFlowPaths) {
      final source = File(path).readAsStringSync();
      expect(_providerLiteralHits(source), isEmpty, reason: path);
      for (final id in ['realdebrid', 'real_debrid', 'torbox',
        'premiumize', 'alldebrid', 'pikpak']) {
        expect(_providerLiteralHits("$source\nfinal drift = '$id';\n"),
            contains("'$id'"), reason: '$path: $id');
      }
    }
  });

}
