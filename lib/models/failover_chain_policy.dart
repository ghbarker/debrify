/// User-configurable click-time failover chain (Quick Play → "Failover
/// chain"). Mirrors the shape of a resolver-server chain:
///
///  1. the clicked stream plays first;
///  2. then siblings from the SAME debrid provider, nearest resolution first
///     (same or nearest below, then nearest above), capped at [maxSiblings];
///  3. then streams from LATER providers in [providerOrder] (only providers
///     after the clicked one), best resolution match first, capped at
///     [maxPerLaterProvider] per provider;
///  4. an optional liveness probe (`Range: bytes=0-0`) before each candidate,
///     skipped for [neverProbeProviders] where a probe costs something;
///  5. links served for this title within [demotionWindowMinutes] that
///     evidently didn't play are demoted to last resort.
///
/// [enabled] defaults to false so existing failover behaviour is untouched
/// until the user opts in. Every knob is per Quick Play tab (movie/series),
/// persisted inside [QuickPlayRules].
///
/// Layering: models import no services, so the provider ids here are plain
/// strings — [defaultProviderOrder] mirrors
/// `CloudProviderId.playbackPrecedence` (pinned by test).
library;

enum FailoverResolutionMatch {
  /// Same resolution, then nearest below, then nearest above (default).
  nearestBelowFirst,

  /// Only candidates whose parsed resolution equals the clicked one.
  exactOnly,

  /// Resolution is not considered; provider grouping still applies.
  ignore,
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

class FailoverChainPolicy {
  /// Playback ids, in `CloudProviderId.playbackPrecedence` order.
  static const List<String> defaultProviderOrder = [
    'debrid',
    'torbox',
    'premiumize',
    'alldebrid',
    'pikpak',
  ];

  /// Providers where a probe COSTS something: Premiumize mints a link per
  /// probe; PikPak queues a real download. Served blind by default.
  static const Set<String> defaultNeverProbeProviders = {
    'premiumize',
    'pikpak',
  };

  static const int maxCap = 10;
  static const int minProbeTimeoutSeconds = 1;
  static const int maxProbeTimeoutSeconds = 30;
  static const int maxDemotionWindowMinutes = 24 * 60;

  final bool enabled;
  final List<String> providerOrder;

  /// Same-provider siblings tried after the clicked stream (0–10).
  final int maxSiblings;

  /// Candidates tried per later provider (0–10).
  final int maxPerLaterProvider;
  final FailoverResolutionMatch resolutionMatch;
  final bool probeEnabled;

  /// Per-request probe timeout (1–30 s); one retry on timeout.
  final int probeTimeoutSeconds;
  final Set<String> neverProbeProviders;

  /// 0 turns demotion off.
  final int demotionWindowMinutes;

  const FailoverChainPolicy._({
    required this.enabled,
    required this.providerOrder,
    required this.maxSiblings,
    required this.maxPerLaterProvider,
    required this.resolutionMatch,
    required this.probeEnabled,
    required this.probeTimeoutSeconds,
    required this.neverProbeProviders,
    required this.demotionWindowMinutes,
  });

  /// Clamps every numeric knob; a corrupted pref can never yield an
  /// out-of-range chain. [providerOrder] is normalized: unknown ids dropped,
  /// duplicates removed, missing known ids appended in default order.
  factory FailoverChainPolicy({
    bool enabled = false,
    List<String> providerOrder = defaultProviderOrder,
    int maxSiblings = 3,
    int maxPerLaterProvider = 3,
    FailoverResolutionMatch resolutionMatch =
        FailoverResolutionMatch.nearestBelowFirst,
    bool probeEnabled = true,
    int probeTimeoutSeconds = 5,
    Set<String> neverProbeProviders = defaultNeverProbeProviders,
    int demotionWindowMinutes = 10,
  }) => FailoverChainPolicy._(
    enabled: enabled,
    providerOrder: normalizeProviderOrder(providerOrder),
    maxSiblings: maxSiblings.clamp(0, maxCap).toInt(),
    maxPerLaterProvider: maxPerLaterProvider.clamp(0, maxCap).toInt(),
    resolutionMatch: resolutionMatch,
    probeEnabled: probeEnabled,
    probeTimeoutSeconds: probeTimeoutSeconds
        .clamp(minProbeTimeoutSeconds, maxProbeTimeoutSeconds)
        .toInt(),
    neverProbeProviders: Set.unmodifiable(
      neverProbeProviders.where(defaultProviderOrder.contains),
    ),
    demotionWindowMinutes: demotionWindowMinutes
        .clamp(0, maxDemotionWindowMinutes)
        .toInt(),
  );

  /// Shipped defaults — const so `QuickPlayRules` can stay a const class.
  /// Keep in sync with the factory's default arguments (pinned by test).
  static const FailoverChainPolicy defaults = FailoverChainPolicy._(
    enabled: false,
    providerOrder: defaultProviderOrder,
    maxSiblings: 3,
    maxPerLaterProvider: 3,
    resolutionMatch: FailoverResolutionMatch.nearestBelowFirst,
    probeEnabled: true,
    probeTimeoutSeconds: 5,
    neverProbeProviders: defaultNeverProbeProviders,
    demotionWindowMinutes: 10,
  );

  static List<String> normalizeProviderOrder(List<String> raw) {
    final out = <String>[];
    for (final id in raw) {
      if (defaultProviderOrder.contains(id) && !out.contains(id)) out.add(id);
    }
    for (final id in defaultProviderOrder) {
      if (!out.contains(id)) out.add(id);
    }
    return List.unmodifiable(out);
  }

  bool get isDefault => this == defaults;

  FailoverChainPolicy copyWith({
    bool? enabled,
    List<String>? providerOrder,
    int? maxSiblings,
    int? maxPerLaterProvider,
    FailoverResolutionMatch? resolutionMatch,
    bool? probeEnabled,
    int? probeTimeoutSeconds,
    Set<String>? neverProbeProviders,
    int? demotionWindowMinutes,
  }) => FailoverChainPolicy(
    enabled: enabled ?? this.enabled,
    providerOrder: providerOrder ?? this.providerOrder,
    maxSiblings: maxSiblings ?? this.maxSiblings,
    maxPerLaterProvider: maxPerLaterProvider ?? this.maxPerLaterProvider,
    resolutionMatch: resolutionMatch ?? this.resolutionMatch,
    probeEnabled: probeEnabled ?? this.probeEnabled,
    probeTimeoutSeconds: probeTimeoutSeconds ?? this.probeTimeoutSeconds,
    neverProbeProviders: neverProbeProviders ?? this.neverProbeProviders,
    demotionWindowMinutes: demotionWindowMinutes ?? this.demotionWindowMinutes,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'providerOrder': providerOrder,
    'maxSiblings': maxSiblings,
    'maxPerLaterProvider': maxPerLaterProvider,
    'resolutionMatch': resolutionMatch.name,
    'probeEnabled': probeEnabled,
    'probeTimeoutSeconds': probeTimeoutSeconds,
    'neverProbeProviders': neverProbeProviders.toList()..sort(),
    'demotionWindowMinutes': demotionWindowMinutes,
  };

  /// Missing or malformed fields fall back to the shipped default for that
  /// field, so a profile saved by an older build (no `failoverChain` at all)
  /// decodes to [defaults].
  factory FailoverChainPolicy.fromJson(Map<String, dynamic>? json) {
    final d = defaults;
    if (json == null) return d;
    int integer(String key, int fallback) {
      final raw = json[key];
      return raw is num ? raw.round() : fallback;
    }

    bool boolean(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    List<String>? strings(String key) {
      final raw = json[key];
      if (raw is! List) return null;
      return raw.whereType<String>().toList(growable: false);
    }

    return FailoverChainPolicy(
      enabled: boolean('enabled', d.enabled),
      providerOrder: strings('providerOrder') ?? d.providerOrder,
      maxSiblings: integer('maxSiblings', d.maxSiblings),
      maxPerLaterProvider: integer(
        'maxPerLaterProvider',
        d.maxPerLaterProvider,
      ),
      resolutionMatch: _enumValue(
        FailoverResolutionMatch.values,
        json['resolutionMatch'],
        d.resolutionMatch,
      ),
      probeEnabled: boolean('probeEnabled', d.probeEnabled),
      probeTimeoutSeconds: integer(
        'probeTimeoutSeconds',
        d.probeTimeoutSeconds,
      ),
      neverProbeProviders:
          strings('neverProbeProviders')?.toSet() ?? d.neverProbeProviders,
      demotionWindowMinutes: integer(
        'demotionWindowMinutes',
        d.demotionWindowMinutes,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FailoverChainPolicy &&
      enabled == other.enabled &&
      _listEquals(providerOrder, other.providerOrder) &&
      maxSiblings == other.maxSiblings &&
      maxPerLaterProvider == other.maxPerLaterProvider &&
      resolutionMatch == other.resolutionMatch &&
      probeEnabled == other.probeEnabled &&
      probeTimeoutSeconds == other.probeTimeoutSeconds &&
      _setEquals(neverProbeProviders, other.neverProbeProviders) &&
      demotionWindowMinutes == other.demotionWindowMinutes;

  @override
  int get hashCode => Object.hash(
    enabled,
    Object.hashAll(providerOrder),
    maxSiblings,
    maxPerLaterProvider,
    resolutionMatch,
    probeEnabled,
    probeTimeoutSeconds,
    Object.hashAllUnordered(neverProbeProviders),
    demotionWindowMinutes,
  );
}
