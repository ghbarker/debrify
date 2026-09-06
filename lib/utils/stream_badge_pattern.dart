/// Compile a badges.json pattern. A leading `(?i)` becomes case-insensitive
/// matching (Dart's RegExp has no inline flags); anything Dart rejects
/// yields null rather than an exception, so one bad rule never breaks a
/// ruleset.
RegExp? compileBadgePattern(String pattern) {
  var source = pattern.trim();
  var caseSensitive = true;
  while (source.startsWith('(?i)')) {
    caseSensitive = false;
    source = source.substring(4);
  }
  if (source.isEmpty) return null;
  try {
    return RegExp(source, caseSensitive: caseSensitive);
  } catch (_) {
    return null;
  }
}
