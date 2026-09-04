import 'package:debrify/services/cloud/alldebrid_cloud_provider.dart';
import 'package:debrify/services/cloud/cloud_capabilities.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/pikpak_cloud_provider.dart';
import 'package:debrify/services/cloud/premiumize_cloud_provider.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supports is the feature map, not a null return', () {
    expect(
      const RealDebridCloudProvider().supports(CloudPortFeature.magicTvPrepare),
      isFalse,
    );
    expect(
      const RealDebridCloudProvider().supports(
        CloudPortFeature.magicTvLockedLinks,
      ),
      isTrue,
    );
    expect(
      const AllDebridCloudProvider().supports(CloudPortFeature.magicTvPrepare),
      isFalse,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.magicTvLockedLinks),
      isFalse,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.playlistEntry),
      isFalse,
    );
    expect(
      const PikPakCloudProvider().supports(CloudPortFeature.playlistEntry),
      isFalse,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.cachedHashes),
      isTrue,
    );
    expect(
      const RealDebridCloudProvider().supports(CloudPortFeature.cachedHashes),
      isFalse,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.checkCache),
      isTrue,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.checkCache),
      isFalse,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.zipPermalink),
      isTrue,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.zipPermalink),
      isFalse,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.fileDownloadLink),
      isTrue,
    );
    expect(
      const PremiumizeCloudProvider().supports(
        CloudPortFeature.fileDownloadLink,
      ),
      isFalse,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.webZipPermalink),
      isTrue,
    );
    expect(
      const PremiumizeCloudProvider().supports(
        CloudPortFeature.webZipPermalink,
      ),
      isFalse,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.cloudTransfer),
      isTrue,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.cloudTransfer),
      isFalse,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.transferZip),
      isTrue,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.transferZip),
      isFalse,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.magnetTorrent),
      isTrue,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.magnetTorrent),
      isFalse,
    );
    expect(CloudPortFeature.forProvider(CloudProviderId.torbox), {
      CloudPortFeature.playlistEntry,
      CloudPortFeature.magicTvPrepare,
      CloudPortFeature.cachedHashes,
      CloudPortFeature.zipPermalink,
      CloudPortFeature.fileDownloadLink,
      CloudPortFeature.webZipPermalink,
      CloudPortFeature.queueUncached,
      CloudPortFeature.magnetTorrent,
    });
    expect(CloudPortFeature.forProvider(CloudProviderId.premiumize), {
      CloudPortFeature.magicTvPrepare,
      CloudPortFeature.checkCache,
      CloudPortFeature.cloudTransfer,
      CloudPortFeature.transferZip,
      CloudPortFeature.queueUncached,
    });
  });

  test('feature table is derived from adapter is-checks', () {
    const adapters = [
      RealDebridCloudProvider(),
      TorboxCloudProvider(),
      PremiumizeCloudProvider(),
      AllDebridCloudProvider(),
      PikPakCloudProvider(),
    ];
    for (final adapter in adapters) {
      expect(
        CloudPortFeature.of(adapter),
        CloudPortFeature.forProvider(adapter.id),
        reason: adapter.id.name,
      );
    }
    expect(const RealDebridCloudProvider(), isA<CloudPlaylist>());
    expect(const RealDebridCloudProvider(), isA<CloudMagicTvLockedLinks>());
    expect(const RealDebridCloudProvider(), isNot(isA<CloudMagicTvPrepare>()));
    expect(const RealDebridCloudProvider(), isNot(isA<CloudCachedHashes>()));
    expect(const TorboxCloudProvider(), isA<CloudCachedHashes>());
    expect(const TorboxCloudProvider(), isA<CloudMagicTvPrepare>());
    expect(const TorboxCloudProvider(), isNot(isA<CloudMagicTvLockedLinks>()));
    expect(const PremiumizeCloudProvider(), isA<CloudCheckCache>());
    expect(const PremiumizeCloudProvider(), isNot(isA<CloudPlaylist>()));
    expect(const PikPakCloudProvider(), isA<CloudMagicTvPrepare>());
    expect(const PikPakCloudProvider(), isNot(isA<CloudPlaylist>()));
  });
}
