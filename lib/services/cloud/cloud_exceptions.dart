/// Provider-specific playback failures that the host UI maps to friendly
/// dialogs (not-cached keep-downloading, PikPak still processing, …).
library;

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
