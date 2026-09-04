import 'package:debrify/services/cloud/alldebrid_cloud_provider.dart';
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
    expect(
      CloudPortFeature.forProvider(CloudProviderId.torbox),
      {
        CloudPortFeature.playlistEntry,
        CloudPortFeature.magicTvPrepare,
        CloudPortFeature.cachedHashes,
        CloudPortFeature.zipPermalink,
        CloudPortFeature.fileDownloadLink,
        CloudPortFeature.queueUncached,
        CloudPortFeature.magnetTorrent,
      },
    );
    expect(
      CloudPortFeature.forProvider(CloudProviderId.premiumize),
      {
        CloudPortFeature.magicTvPrepare,
        CloudPortFeature.checkCache,
        CloudPortFeature.cloudTransfer,
        CloudPortFeature.transferZip,
        CloudPortFeature.queueUncached,
      },
    );
  });
}
