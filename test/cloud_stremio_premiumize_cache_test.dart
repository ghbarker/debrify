import 'package:debrify/services/cloud/cloud_exceptions.dart';
import 'package:debrify/services/cloud/cloud_port_feature.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/premiumize_cloud_provider.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 'stremio-pm-cache-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(() {
    CloudProviderRegistry.debugReset();
    ProfileRuntime.debugReset();
  });

  test('only Premiumize supports checkCache; not cachedHashes', () {
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.checkCache),
      isTrue,
    );
    expect(
      const PremiumizeCloudProvider().supports(CloudPortFeature.cachedHashes),
      isFalse,
    );
    expect(
      const TorboxCloudProvider().supports(CloudPortFeature.checkCache),
      isFalse,
    );
  });

  test('production RD checkCache throws CloudUnsupported', () {
    expect(
      () => const RealDebridCloudProvider().checkCache(const ['abc']),
      throwsA(isA<CloudUnsupported>()),
    );
  });

  test('missing Premiumize key throws CloudMissingApiKey', () async {
    await expectLater(
      const PremiumizeCloudProvider().checkCache(const ['abc']),
      throwsA(isA<CloudMissingApiKey>()),
    );
  });

  test('registry with no Premiumize adapter returns empty flags', () async {
    CloudProviderRegistry.instance = CloudProviderRegistry([
      FakeCloudProvider(id: CloudProviderId.torbox),
    ]);
    expect(
      await CloudProviderRegistry.instance.checkCache(const ['abc']),
      isEmpty,
    );
  });

  test('registry returns positional bools, not a hash set', () async {
    final premiumize = FakeCloudProvider(
      id: CloudProviderId.premiumize,
      cacheFlags: const [false, true],
    );
    final torbox = FakeCloudProvider(
      id: CloudProviderId.torbox,
      cachedHashes: const {'abc'},
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([
      premiumize,
      torbox,
    ]);
    expect(
      await CloudProviderRegistry.instance.checkCache(const ['aaa', 'bbb']),
      [false, true],
    );
    expect(premiumize.lastCacheQuery, ['aaa', 'bbb']);
    expect(torbox.checkCacheCount, 0);
    expect(premiumize.cachedHashesCount, 0);
  });
}
