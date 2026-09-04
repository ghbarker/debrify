/// Provider-specific playback failures that the host UI maps to friendly
/// dialogs (not-cached keep-downloading, PikPak still processing, …).
library;

import 'cloud_port_feature.dart';
import 'cloud_provider_id.dart';

class TorboxNotCached implements Exception {
  const TorboxNotCached();
}

class PremiumizeNotCached implements Exception {
  const PremiumizeNotCached();
}

class PikPakStillProcessing implements Exception {
  const PikPakStillProcessing();
}

class PikPakFailed implements Exception {
  const PikPakFailed();
}

/// This adapter does not implement [feature]. Distinct from a miss.
class CloudUnsupported implements Exception {
  const CloudUnsupported(this.id, this.feature);
  final CloudProviderId id;
  final CloudPortFeature feature;

  @override
  String toString() => 'CloudUnsupported(${id.name}, $feature)';
}

/// Missing file/hash/path metadata. Player-screen unlock rethrows this
/// unwrapped; it is not `$brand link failed`.
class CloudMetadataMissing implements Exception {
  const CloudMetadataMissing(this.message);
  final String message;

  @override
  String toString() => 'Exception: $message';
}

/// Missing API key. Player-screen unlock rethrows this unwrapped.
class CloudMissingApiKey implements Exception {
  const CloudMissingApiKey(this.message);
  final String message;

  @override
  String toString() => 'Exception: $message';
}
