/// Resolution encoded in a source/release name.
enum SourceQuality { ultraHd, fullHd, hd, sd }

/// Detects the displayed resolution of a source name.
///
/// Explicit pixel resolutions are authoritative. Loose marketing/source
/// tokens such as `4K` and `UHD` are only fallbacks, and must be standalone
/// tokens so release groups such as `DS4K` and `RM4k` are not misclassified.
SourceQuality? sourceQualityForName(String name) {
  if (name.isEmpty) return null;

  bool has(String pattern) => RegExp(
    r'(?:^|[^A-Za-z0-9])(?:' + pattern + r')(?=$|[^A-Za-z0-9])',
    caseSensitive: false,
  ).hasMatch(name);

  if (has(r'2160p')) return SourceQuality.ultraHd;
  if (has(r'1080p|1080i')) return SourceQuality.fullHd;
  if (has(r'720p|720i')) return SourceQuality.hd;
  if (has(r'480p|576p|360p')) return SourceQuality.sd;

  if (has(r'FHD|Full[ .-]?HD')) return SourceQuality.fullHd;
  if (has(r'4K|UHD')) return SourceQuality.ultraHd;
  return null;
}

String? sourceQualityBadgeForName(String name) =>
    switch (sourceQualityForName(name)) {
      SourceQuality.ultraHd => '4K',
      SourceQuality.fullHd => '1080p',
      SourceQuality.hd => '720p',
      SourceQuality.sd => '480p',
      null => null,
    };

/// Numeric vertical resolution encoded in a stream/release name, for the
/// failover chain's "nearest resolution" ordering — the reference resolver's
/// rule verbatim: `(2160|1440|1080|720|576|480)\s*p` wins, else a standalone
/// `4K`/`UHD` token means 2160, else 0 (unknown). Coarser than
/// [sourceQualityForName] on purpose (1440p is its own rung; unknown is 0
/// rather than null) so distances between candidates are plain integers.
int sourceResolutionForName(String name) {
  if (name.isEmpty) return 0;
  final explicit = RegExp(
    r'(2160|1440|1080|720|576|480)\s*p',
    caseSensitive: false,
  ).firstMatch(name);
  if (explicit != null) return int.parse(explicit.group(1)!);
  final uhd = RegExp(
    r'(?:^|[^A-Za-z0-9])(?:4K|UHD)(?=$|[^A-Za-z0-9])',
    caseSensitive: false,
  );
  return uhd.hasMatch(name) ? 2160 : 0;
}
