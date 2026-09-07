/// Pure click-time failover chain builder for [FailoverChainPolicy]. No
/// BuildContext, no widgets, no I/O: given the candidate rows the player was
/// launched with and the row the user clicked, decide the ORDER in which the
/// startup failover walks them. The player keeps resolving, probing and
/// decode-gating each candidate exactly as before.
///
/// Chain shape (the reference resolver's, every knob from the policy):
///
///  1. the clicked row;
///  2. siblings from the SAME debrid provider, nearest resolution first
///     (equal, then nearest below, then nearest above), capped;
///  3. rows from LATER providers in the user's provider order — only
///     providers after the clicked one — best resolution match first,
///     capped per provider;
///  4. anything recently served for this title that evidently didn't play is
///     moved to the very end (last resort) instead of dropped.
///
/// "Provider" here is the DEBRID/cloud provider that hosts a row, not the
/// engine/addon it came from (that axis is `QuickPlayRules.sourcePriority`).
/// See [providerOf] for how a row's provider is known at play time.
library;

import '../../models/failover_chain_policy.dart';
import '../../models/torrent.dart';
import '../../utils/source_quality.dart';
import '../cloud/cloud_provider_id.dart';
import 'playback_candidate_ranking.dart';

/// Read-only view of the demotion store the chain consults. Keyed by
/// [FailoverChain.linkKeyOf]; the caller scopes it to one title/episode.
abstract class RecentlyServedLinks {
  const RecentlyServedLinks();

  /// Whether [linkKey] was served for this title inside the demotion window
  /// without evidently playing.
  bool isDemoted(String linkKey);

  static const RecentlyServedLinks none = _NoRecentlyServed();
}

class _NoRecentlyServed extends RecentlyServedLinks {
  const _NoRecentlyServed();
  @override
  bool isDemoted(String linkKey) => false;
}

class FailoverChain {
  const FailoverChain._();

  /// Provider key for rows that are direct links with no recognizable debrid
  /// host — plain addon/CDN streams. Sorted after every known provider.
  static const String directProvider = 'direct';

  /// Provider key for torrent rows when the session has no resolver.
  static const String unknownProvider = 'unknown';

  /// Vertical resolution of a row: its name first, then the addon's stream
  /// label/description (a Torrentio-style "4K" label with a bare filename).
  static int resolutionOf(Torrent t) {
    final fromName = sourceResolutionForName(t.name);
    if (fromName != 0) return fromName;
    return sourceResolutionForName(t.badgeDescription ?? '');
  }

  /// Reference match rank: (0,0) equal, (1, target-cand) below, (2,
  /// cand-target) above — lexicographically smaller is a better match, so
  /// equal beats nearest-below beats nearest-above.
  static (int, int) matchRank({required int target, required int candidate}) {
    if (candidate == target) return (0, 0);
    if (candidate < target) return (1, target - candidate);
    return (2, candidate - target);
  }

  static int _compareRank((int, int) a, (int, int) b) {
    final tier = a.$1.compareTo(b.$1);
    return tier != 0 ? tier : a.$2.compareTo(b.$2);
  }

  /// Stable identity used by the demotion store. A direct row IS its URL;
  /// a torrent row is minted a fresh URL on every resolve, so it is keyed by
  /// infohash (falling back to magnet / .torrent URL). Null when the row has
  /// nothing stable, in which case it is never demoted.
  static String? linkKeyOf(Torrent t) {
    if (t.streamType != StreamType.torrent) {
      final url = t.directUrl?.trim();
      return (url == null || url.isEmpty) ? null : url;
    }
    if (t.hasRealInfoHash && t.infohash.isNotEmpty) {
      return 'infohash:${t.infohash.toLowerCase()}';
    }
    final magnet = t.magnetUrl?.trim();
    if (magnet != null && magnet.isNotEmpty) return magnet;
    final torrentUrl = t.torrentUrl?.trim();
    return (torrentUrl == null || torrentUrl.isEmpty) ? null : torrentUrl;
  }

  /// Which debrid provider serves [t] at play time.
  ///
  /// Torrent rows are resolved by the session's single resolver
  /// ([resolverProvider] — the player's `startupResolverProvider`), so they
  /// all share it. Direct rows already carry a host: debrid-cached addon
  /// links embed the service in the URL (`/realdebrid/`, `torbox`, …) or the
  /// stream label (`[RD+]`, `TB`, `PM`); anything else is [directProvider].
  /// Returns playback ids (`debrid`, `torbox`, …) so the result lines up with
  /// [FailoverChainPolicy.providerOrder].
  static String providerOf(Torrent t, {String? resolverProvider}) {
    if (t.streamType == StreamType.torrent) {
      final raw = resolverProvider?.trim() ?? '';
      if (raw.isEmpty) return unknownProvider;
      return CloudProviderId.tryParse(raw)?.playbackId ?? raw.toLowerCase();
    }
    final url = (t.directUrl ?? '').toLowerCase();
    final fromUrl = _providerFromUrl(url);
    if (fromUrl != null) return fromUrl;
    final label = (t.badgeDescription ?? '').toLowerCase();
    return _providerFromLabel(label) ?? directProvider;
  }

  static String? _providerFromUrl(String url) {
    if (url.isEmpty) return null;
    if (url.contains('real-debrid') ||
        url.contains('realdebrid') ||
        url.contains('/rd/')) {
      return CloudProviderId.debrid.playbackId;
    }
    if (url.contains('torbox')) return CloudProviderId.torbox.playbackId;
    if (url.contains('premiumize')) {
      return CloudProviderId.premiumize.playbackId;
    }
    if (url.contains('alldebrid') || url.contains('debrid.it')) {
      return CloudProviderId.alldebrid.playbackId;
    }
    if (url.contains('pikpak') || url.contains('mypikpak')) {
      return CloudProviderId.pikpak.playbackId;
    }
    return null;
  }

  static final RegExp _rdTag = RegExp(
    r'(^|[^a-z0-9])(rd\+?|realdebrid|real-debrid)(?=$|[^a-z0-9])',
  );
  static final RegExp _tbTag = RegExp(
    r'(^|[^a-z0-9])(tb\+?|torbox)(?=$|[^a-z0-9])',
  );
  static final RegExp _pmTag = RegExp(
    r'(^|[^a-z0-9])(pm\+?|premiumize)(?=$|[^a-z0-9])',
  );
  static final RegExp _adTag = RegExp(
    r'(^|[^a-z0-9])(ad\+?|alldebrid)(?=$|[^a-z0-9])',
  );
  static final RegExp _ppTag = RegExp(
    r'(^|[^a-z0-9])(pp\+?|pikpak)(?=$|[^a-z0-9])',
  );

  static String? _providerFromLabel(String label) {
    if (label.isEmpty) return null;
    if (_rdTag.hasMatch(label)) return CloudProviderId.debrid.playbackId;
    if (_tbTag.hasMatch(label)) return CloudProviderId.torbox.playbackId;
    if (_pmTag.hasMatch(label)) return CloudProviderId.premiumize.playbackId;
    if (_adTag.hasMatch(label)) return CloudProviderId.alldebrid.playbackId;
    if (_ppTag.hasMatch(label)) return CloudProviderId.pikpak.playbackId;
    return null;
  }

  /// Ordered indices into [candidates] to attempt, clicked row first.
  ///
  /// With `policy.enabled == false` the result is the legacy walk verbatim:
  /// [clickedIndex], then every following index (the linear startup ladder),
  /// untouched by caps, providers or demotion — callers can use one loop.
  ///
  /// Rows that cannot be auto-played ([isPlayable] — external links, rows
  /// without acquisition data or a URL) are skipped, except the clicked row,
  /// whose launch URL the player already holds.
  static List<int> build({
    required List<Torrent> candidates,
    required int clickedIndex,
    required FailoverChainPolicy policy,
    String? resolverProvider,
    RecentlyServedLinks recentlyServed = RecentlyServedLinks.none,
    bool Function(Torrent) isPlayable =
        PlaybackCandidateRanking.isAutoPlayableCandidate,
  }) {
    if (candidates.isEmpty) return const [];
    final clicked = clickedIndex.clamp(0, candidates.length - 1);
    if (!policy.enabled) {
      return [for (var i = clicked; i < candidates.length; i++) i];
    }

    final order = policy.providerOrder;
    int providerRank(String provider) {
      final i = order.indexOf(provider);
      return i < 0 ? order.length : i;
    }

    final clickedRow = candidates[clicked];
    final target = resolutionOf(clickedRow);
    final clickedProvider = providerOf(
      clickedRow,
      resolverProvider: resolverProvider,
    );
    final clickedRank = providerRank(clickedProvider);

    (int, int) rankOf(Torrent t) => switch (policy.resolutionMatch) {
      FailoverResolutionMatch.ignore => (0, 0),
      _ => matchRank(target: target, candidate: resolutionOf(t)),
    };

    final siblings = <int>[];
    // Later providers keep first-seen order among unlisted keys; listed keys
    // are visited in the user's order below.
    final later = <String, List<int>>{};
    for (var i = 0; i < candidates.length; i++) {
      if (i == clicked) continue;
      final t = candidates[i];
      if (t.streamType == StreamType.externalUrl || !isPlayable(t)) continue;
      if (policy.resolutionMatch == FailoverResolutionMatch.exactOnly &&
          resolutionOf(t) != target) {
        continue;
      }
      final provider = providerOf(t, resolverProvider: resolverProvider);
      if (provider == clickedProvider) {
        siblings.add(i);
        continue;
      }
      final rank = providerRank(provider);
      // Unlisted providers (direct/unknown) sit after every listed one, so
      // they are "later" for any listed click and never "later" than each
      // other or than an unlisted click.
      if (rank > clickedRank) {
        later.putIfAbsent(provider, () => <int>[]).add(i);
      }
    }

    int byMatchThenIndex(int a, int b) {
      final r = _compareRank(rankOf(candidates[a]), rankOf(candidates[b]));
      return r != 0 ? r : a.compareTo(b);
    }

    siblings.sort(byMatchThenIndex);
    final chain = <int>[clicked, ...siblings.take(policy.maxSiblings)];

    final laterKeys = <String>[
      ...order.where(later.containsKey),
      ...later.keys.where((k) => !order.contains(k)),
    ];
    for (final key in laterKeys) {
      final rows = later[key]!..sort(byMatchThenIndex);
      chain.addAll(rows.take(policy.maxPerLaterProvider));
    }

    if (policy.demotionWindowMinutes <= 0) return chain;
    final kept = <int>[];
    final demoted = <int>[];
    for (final i in chain) {
      final key = linkKeyOf(candidates[i]);
      (key != null && recentlyServed.isDemoted(key) ? demoted : kept).add(i);
    }
    return [...kept, ...demoted];
  }
}
