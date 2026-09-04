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
      CloudPortFeature.forProvider(CloudProviderId.torbox),
      {
        CloudPortFeature.playlistEntry,
        CloudPortFeature.magicTvPrepare,
        CloudPortFeature.cachedHashes,
      },
    );
  });
}
