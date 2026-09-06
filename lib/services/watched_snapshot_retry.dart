/// Retry transient local-storage failures without repeating tracker requests.
/// Exhaustion remains an error so the caller can log it and retry on activation.
Future<T> readWatchedSnapshotWithRetry<T>(
  Future<T> Function() read, {
  Duration retryDelay = const Duration(milliseconds: 200),
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } catch (_) {
      if (attempt == 2) rethrow;
      await Future<void>.delayed(retryDelay * (attempt + 1));
    }
  }
}
