import 'dart:async';

import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/pack_negative_cache.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // ignore: invalid_use_of_visible_for_testing_member
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  PackNegativeCache.debugReset();
  CloudProviderRegistry.debugReset();
  await testMain();
}
