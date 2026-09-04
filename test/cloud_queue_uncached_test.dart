import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/premiumize_cloud_provider.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_cloud_provider.dart';

void main() {
  tearDown(CloudProviderRegistry.debugReset);

  test('TorBox and Premiumize support queueUncached; RD does not', () {
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.queueUncached),
      isTrue,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.queueUncached),
      isTrue,
    );
    expect(
      const RealDebridCloudProvider().supports(CloudPortFeature.queueUncached),
      isFalse,
    );
  });

  test('production RD queueUncachedMagnet throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().queueUncachedMagnet('magnet:x'),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('registry no-ops RD and unknown ids without calling adapters', () async {
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    final torbox = FakeCloudProvider(id: CloudProviderId.torbox);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid, torbox]);
    await CloudProviderRegistry.instance.queueUncachedMagnet('debrid', 'magnet:x');
    await CloudProviderRegistry.instance.queueUncachedMagnet('nope', 'magnet:x');
    expect(debrid.queueUncachedCount, 0);
    expect(torbox.queueUncachedCount, 0);
  });

  test('registry queues TorBox and Premiumize only', () async {
    final torbox = FakeCloudProvider(id: CloudProviderId.torbox);
    final premiumize = FakeCloudProvider(id: CloudProviderId.premiumize);
    CloudProviderRegistry.instance = CloudProviderRegistry([
      torbox,
      premiumize,
    ]);
    await CloudProviderRegistry.instance.queueUncachedMagnet('torbox', 'magnet:tb');
    await CloudProviderRegistry.instance.queueUncachedMagnet(
      'premiumize',
      'magnet:pm',
    );
    expect(torbox.queueUncachedCount, 1);
    expect(torbox.lastTransferMagnet, 'magnet:tb');
    expect(premiumize.queueUncachedCount, 1);
    expect(premiumize.lastTransferMagnet, 'magnet:pm');
  });
}
