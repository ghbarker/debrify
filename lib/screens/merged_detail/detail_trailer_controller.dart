import 'package:flutter/material.dart';

import '../../models/playlist_view_mode.dart';
import '../../models/stremio_addon.dart';
import '../../services/imdb_trailer_service.dart';
import '../../services/storage/ambient_trailer_prefs.dart'
    show AmbientTrailerPrefs, AmbientTrailerSurface;
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/youtube_service.dart';
import '../../widgets/detail/detail_style.dart';
import '../../widgets/hero_trailer_backdrop.dart';

/// Everything the trailer lifecycle reads off its host, re-read on every access
/// so an enriched title or a rebuilt host is seen exactly as the State's own
/// `widget.`/`_item` reads used to see it.
class DetailTrailerInputs {
  const DetailTrailerInputs({
    required this.routeItem,
    required this.item,
    required this.isTelevision,
    required this.leftEntryFocusNode,
    this.metaEnricher,
  });

  /// The item the route was opened with. The trailer id and the enrichment
  /// lookup deliberately read this rather than the enriched copy.
  final StremioMeta routeItem;

  /// The live item — enriched when enrichment has landed.
  final StremioMeta item;

  final bool isTelevision;

  /// The stable LEFT-crossing target, re-anchored when a fullscreen trailer
  /// closes on TV.
  final FocusNode leftEntryFocusNode;

  final Future<StremioMeta?> Function(String imdbId, String type)? metaEnricher;
}

/// The merged detail page's trailer lifecycle: resolving the YouTube id, the
/// OTT ambient-autoplay pipeline behind the backdrop, promoting that same
/// player to fullscreen, and the standalone fallback launch.
///
/// A [ChangeNotifier] rather than a widget because the state is read from three
/// places at once (the backdrop, the Trailer ghost button, and the "Trailer
/// playing" chip); the host listens once and rebuilds, exactly as its
/// `setState` calls used to.
class DetailTrailerController extends ChangeNotifier {
  DetailTrailerController({
    required this.read,
    @visibleForTesting this.streamResolver,
    @visibleForTesting this.standaloneLauncher,
  });

  /// Live view of the host's configuration. Called at every use rather than
  /// captured, so it behaves like the `widget.…` reads it replaces.
  final DetailTrailerInputs Function() read;

  /// Test seam for the YouTube → IMDb stream resolve. Production always uses
  /// the services.
  final Future<YoutubeResolvedStreams?> Function(String ytId)? streamResolver;

  /// Test seam for the standalone player launch (the fallback path).
  /// Production always pushes the real player route.
  final Future<void> Function(BuildContext context, VideoPlayerLaunchArgs args)?
  standaloneLauncher;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Trailer YouTube ID, resolved from Cinemeta meta. Null until loaded / when
  /// the title has no trailer — the Trailer button only shows once this is set.
  String? _ytId;
  String? get ytId => _ytId;

  /// Guards against a double-launch while a trailer's streams resolve.
  bool _loading = false;
  bool get loading => _loading;

  /// Whether OTT-style trailer autoplay behind the backdrop is on (settings).
  /// Always false on Android TV — the Home hero owns ambient trailers there.
  bool _autoplayEnabled = false;
  bool get autoplayEnabled => _autoplayEnabled;

  /// Ambient loop volume (0–100) from settings; 0 when the sound toggle is off.
  /// Read alongside [autoplayEnabled] and applied when the backdrop opens its
  /// engine (which can't happen before the streams resolve), so it's always in
  /// place by then. Promoting to fullscreen still plays at full volume — the
  /// backdrop handles that, muted ambient or not.
  double _ambientVolume = 70;
  double get ambientVolume => _ambientVolume;

  /// Resolved trailer streams, pre-fetched for the ambient backdrop.
  YoutubeResolvedStreams? _streams;
  YoutubeResolvedStreams? get streams => _streams;

  /// Handle to the backdrop so the Trailer button can promote the *same* player
  /// to fullscreen in place (seamless — no second decoder, no re-buffer).
  final GlobalKey<HeroTrailerBackdropState> backdropKey = GlobalKey();

  /// Whether the trailer is currently brought forward to fullscreen.
  bool _foreground = false;
  bool get foreground => _foreground;

  /// A Trailer press is waiting on the backdrop to produce frames before it
  /// promotes (see [play]). Distinct from [foreground] so the page doesn't fade
  /// out onto a still-buffering surface.
  bool _promotePending = false;

  /// The backdrop must hold a live player: either the trailer is fullscreen or
  /// a press is waiting to make it so. The host feeds the backdrop its stream
  /// and keeps it enabled while this holds, REGARDLESS of the autoplay setting
  /// and the Showcase scroll depth — with autoplay off there is no ambient
  /// loop, and this is what lets the same surface still carry an explicit
  /// watch. Drops with [exitForeground], and the backdrop falls back to
  /// whatever the ambient rules say (loop on, or torn down).
  bool get foregroundRequested => _foreground || _promotePending;

  /// The ambient backdrop trailer is live with frames on screen — the Trailer
  /// button reads "Watch Trailer" to say "it's playing, tap to view".
  bool _ambientPlaying = false;
  bool get ambientPlaying => _ambientPlaying;

  /// Autoplay pipeline in flight (stream resolve → buffer → first frame) — the
  /// Trailer button shows a spinner.
  bool _resolving = false;
  bool get resolving => _resolving;

  /// The backdrop's own report. First frames clear the spinner; a stop clears
  /// the "Watch Trailer" affordance.
  void setAmbientPlaying(bool playing) {
    if (_disposed) return;
    _ambientPlaying = playing;
    _resolving = false;
    notifyListeners();
  }

  /// Resolve the trailer's YouTube ID from Cinemeta. Runs independently of the
  /// host's meta enrichment (which short-circuits for already-rich items and so
  /// can't be relied on to carry the trailer). The `fetchMetaDetails` result is
  /// cached in `StremioService`, so this shares that fetch rather than doubling
  /// network. Silent on failure — the button simply never appears.
  Future<void> load(BuildContext context) async {
    // Resolve the trailer id: prefer what the item arrived with, else ask the
    // metadata addon (Cinemeta).
    final inputs = read();
    String? ytId = inputs.routeItem.trailerYtId;
    if (ytId == null || ytId.isEmpty) {
      final enrich = inputs.metaEnricher;
      final imdbId = inputs.routeItem.effectiveImdbId;
      if (enrich != null && imdbId != null) {
        try {
          final full = await enrich(imdbId, inputs.routeItem.type);
          ytId = full?.trailerYtId;
        } catch (_) {}
      }
    }
    if (ytId == null || ytId.isEmpty || _disposed) return;
    _ytId = ytId;
    notifyListeners();

    // OTT autoplay: honour the setting, then pre-resolve the stream (also reused
    // by the Trailer button). Silent on failure — the poster simply stays.
    final autoplay = await StorageService.getDetailTrailerAutoplayEnabled();
    // The ambient sound pair is shared with the TV hero (one live surface per
    // platform), so off-TV it governs this backdrop. Read unconditionally so
    // all three land in the one notification below — [autoplay] is false on TV
    // anyway, and these are two prefs reads.
    final soundOn = await AmbientTrailerPrefs.getAmbientTrailerAudioEnabled(
      AmbientTrailerSurface.detail,
    );
    final volume = await AmbientTrailerPrefs.getAmbientTrailerVolume(
      AmbientTrailerSurface.detail,
    );
    if (_disposed || !context.mounted) return;
    // The backdrop refuses to autoplay under OS reduced-motion — skip the whole
    // pipeline (no resolve, no spinner) rather than spin forever waiting for a
    // player that will never start.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final willAutoplay = autoplay && !reduceMotion;
    _autoplayEnabled = autoplay;
    _ambientVolume = soundOn ? volume.toDouble() : 0;
    // Spinner from here until the backdrop reports first frames (or fails).
    _resolving = willAutoplay;
    notifyListeners();
    if (!willAutoplay) return;
    final streams = await _resolveStreams(ytId);
    if (_disposed) return;
    final playable = streams?.playUrl?.isNotEmpty ?? false;
    _streams = streams;
    // No playable stream → the backdrop never starts, so stop the spinner
    // here; on success the backdrop's onPlayingChanged(true) clears it once
    // frames actually flow.
    if (!playable) _resolving = false;
    notifyListeners();
    if (!playable) return;
    // Safety net: a stream that opens but never renders a first frame would
    // otherwise leave the spinner up forever.
    Future.delayed(const Duration(seconds: 25), () {
      if (!_disposed && _resolving) {
        _resolving = false;
        notifyListeners();
      }
    });
  }

  /// YouTube first, then IMDb's own trailer MP4s as the backup source for when
  /// YouTube resolution is blocked (regional client kills) — the same ladder
  /// for the ambient prefetch and the Trailer press, so a blocked YouTube can
  /// neither keep the backdrop still nor reduce the button to a "Couldn't
  /// load trailer" snackbar when IMDb hosts the same clip. Never throws; null
  /// (or an unplayable result) means nothing to play.
  Future<YoutubeResolvedStreams?> _resolveStreams(String ytId) async {
    final override = streamResolver;
    if (override != null) return override(ytId);
    YoutubeResolvedStreams? streams;
    try {
      streams = await YoutubeService.resolveStreams(ytId);
    } catch (_) {
      streams = null;
    }
    if (streams == null || !(streams.playUrl?.isNotEmpty ?? false)) {
      final imdbId = read().item.effectiveImdbId;
      if (imdbId != null) {
        streams = await ImdbTrailerService.resolveTrailer(imdbId);
      }
    }
    return streams;
  }

  void exitForeground(BuildContext context) {
    if (!_foreground) return;
    _foreground = false;
    notifyListeners();
    // TV: the page content was focus-excluded while the trailer was fullscreen,
    // so nothing holds focus now — re-anchor the remote on the primary action.
    if (read().isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !context.mounted) return;
        // The left-entry node only has a holder when Play or the source pill is
        // present; if neither is (edge config), fall back to traversal so the
        // remote isn't stranded rather than no-op on an unattached node.
        final leftEntry = read().leftEntryFocusNode;
        if (detailNodeMounted(leftEntry)) {
          leftEntry.requestFocus();
        } else {
          FocusScope.of(context).nextFocus();
        }
      });
    }
  }

  /// Trailer button. Always ends in full-page IN-APP playback off-TV — the
  /// backdrop's own player brought forward (unmuted, controls, Back/Escape
  /// settles it back into the page):
  ///
  ///  1. Frames already on screen ([HeroTrailerBackdropState.canPromote]) →
  ///     promote the *same* player in place. No second decoder, no re-buffer.
  ///  2. Otherwise resolve the stream fresh, hand it to the backdrop (which
  ///     starts its engine even with autoplay off — see [foregroundRequested])
  ///     and park on [HeroTrailerBackdropState.whenPromotable]; the first
  ///     rendered frame promotes. A "Loading trailer…" snackbar covers the wait
  ///     so the press never looks ignored.
  ///
  /// The standalone player remains ONLY for the documented exceptions: TV
  /// (native Exo underlay — its video isn't Flutter pixels), OS reduced motion
  /// (the backdrop never starts a player under it), no backdrop mounted, and an
  /// engine that fails or never renders a frame within the wait.
  ///
  /// Streams are always re-resolved on a press that can't promote at once:
  /// googlevideo URLs carry an `expire` param and go dead after a few hours, so
  /// a page left open would otherwise hand a stale URL to a fresh engine. The
  /// resolve is cached with a TTL, so a live prefetch costs nothing extra.
  Future<void> play(BuildContext context) async {
    final backdrop = backdropKey.currentState;
    if (backdrop != null && backdrop.canPromote) {
      _foreground = true;
      notifyListeners();
      return;
    }

    final ytId = _ytId;
    if (ytId == null || _loading) return;

    // Decide the path BEFORE the resolve: asking the backdrop also lifts its
    // per-visit playback latches so the URL it's about to receive can start.
    final inPlace =
        backdrop != null &&
        !read().isTelevision &&
        backdrop.requestForegroundStart();

    _loading = true;
    _promotePending = inPlace;
    notifyListeners();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading trailer…'),
            ],
          ),
          duration: Duration(seconds: 20),
        ),
      );
    }

    try {
      final streams = await _resolveStreams(ytId);
      if (_disposed || !context.mounted) return;

      final playUrl = streams?.playUrl;
      if (playUrl == null || playUrl.isEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Couldn\'t load trailer')));
        return;
      }

      if (inPlace) {
        // The host reads [streams] + [foregroundRequested] and feeds the
        // backdrop on this notification; a new URL restarts a live engine on
        // the fresh media, a first URL starts one.
        _streams = streams;
        notifyListeners();
        final ready = await backdrop.whenPromotable();
        if (_disposed || !context.mounted) return;
        if (ready && backdrop.canPromote) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          _foreground = true;
          return;
        }
        // The wait can end because something covered this page (Play pressed,
        // the content player launching tears the trailer down) — never stack
        // a trailer route on top of that.
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _loading = false;
      _promotePending = false;
      notifyListeners();
      await _launchStandalone(context, streams!);
    } finally {
      // One notification settles every exit: promoted (foreground set above),
      // failed, or handed to the standalone player.
      if (!_disposed) {
        _loading = false;
        _promotePending = false;
        notifyListeners();
      }
    }
  }

  Future<void> _launchStandalone(
    BuildContext context,
    YoutubeResolvedStreams streams,
  ) {
    final args = VideoPlayerLaunchArgs(
      videoUrl: streams.playUrl!,
      audioUrl: streams.audioUrl,
      fallbackUrl: streams.muxedPlaybackFallback,
      title: '${read().item.name} — Trailer',
      viewMode: PlaylistViewMode.sorted,
    );
    final override = standaloneLauncher;
    if (override != null) return override(context, args);
    return VideoPlayerLauncher.push(
      context,
      args,
      // Watching the trailer must not suppress the ambient trailer backdrop.
      isTrailer: true,
    );
  }
}
