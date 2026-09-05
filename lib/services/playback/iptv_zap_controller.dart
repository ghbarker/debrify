import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/iptv_playlist.dart';
import '../../screens/video_player/widgets/iptv_channel_sheet.dart'
    show IptvGuideContext, iptvChannelFromBrowsePayload;
import '../../screens/video_player/widgets/iptv_zap_banner.dart';
import '../../screens/video_player/widgets/player_guide_style.dart';
import '../../widgets/iptv/styles/iptv_style.dart';
import '../iptv_epg_service.dart';
import '../storage_service.dart';
import '../../utils/iptv_player_paging.dart';

/// Live player state the moved IPTV zap / catch-up functions read and write.
///
/// Implemented by the player State. Named without host `_` prefixes so this
/// file compiles with those members removed (gate g).
abstract class IptvZapSession {
  bool get isMounted;
  BuildContext get hostContext;

  /// Origin `widget.iptvChannels`.
  List<IptvChannel>? get launchChannels;

  int get currentIptvIndex;
  set currentIptvIndex(int value);

  /// Origin `_iptvSwitchTicket`.
  int get iptvSwitchTicket;

  /// Origin `widget.iptvSourceId`.
  String? get iptvSourceId;

  /// Origin `widget.iptvSourceName`.
  String? get iptvSourceName;

  /// Origin `widget.iptvCategories`.
  List<String>? get iptvCategories;

  /// Origin `widget.iptvSelectedCategory`.
  String? get iptvSelectedCategory;

  /// Origin `widget.iptvContentType`.
  String? get iptvContentType;

  /// Origin `widget.iptvBrowseProvider`.
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  get iptvBrowseProvider;

  bool get controlsVisible;
  bool get showIptvChannelSheet;
  bool get showSourceSheet;
  bool get showChannelGuide;

  PlayerGuideStyle get playerGuideStyle;
  IptvStyleTokens? get playerGuideTokens;
  bool get recordingActiveNow;

  void runSetState(VoidCallback updates);

  /// Host `_switchToIptvChannel` — media open, recording stop, identity.
  Future<void> onSwitch(IptvChannel channel, {bool quietRecovery = false});

  /// Origin `_showIptvChannelSheetOverlay` setState.
  void openIptvChannelSheet();

  /// Origin `_hideIptvChannelSheet` setState.
  void closeIptvChannelSheet();

  /// Origin `_iptvErrorsMuted`.
  bool get iptvErrorsMuted;

  /// Origin `_iptvDiag.onError`.
  void noteTuneError(String error);

  /// Origin `_iptvLiveRecovery.onError()`.
  bool tryLiveRecoveryOnError();
}

/// One page of a live IPTV category, as the browse provider returns it.
///
/// [offset] is the page's absolute position inside [category] and [total] is
/// how many channels that category holds — the pair that tells the end of a
/// loaded window apart from the end of the category itself.
class _IptvZapPage {
  final List<IptvChannel> channels;
  final int offset;
  final int total;
  final String? sourceId;
  final String? category;
  final List<String> categories;

  const _IptvZapPage({
    required this.channels,
    required this.offset,
    required this.total,
    required this.sourceId,
    required this.category,
    required this.categories,
  });
}

/// Monotonic ownership gate for asynchronous IPTV replay lookups.
///
/// Starting or cancelling a request makes every older ticket stale, preventing
/// a slow catch-up probe from taking playback back after a newer user action.
class IptvCatchupRequestGate {
  int _generation = 0;
  int? _activeTicket;

  int begin() {
    final ticket = ++_generation;
    _activeTicket = ticket;
    return ticket;
  }

  bool isCurrent(int ticket) =>
      _activeTicket == ticket && _generation == ticket;

  bool complete(int ticket) {
    if (!isCurrent(ticket)) return false;
    _activeTicket = null;
    return true;
  }

  bool cancel() {
    if (_activeTicket == null) return false;
    _generation++;
    _activeTicket = null;
    return true;
  }
}

/// Launch-payload façade so moved bodies keep `widget.iptv*` reads (gate g:
/// this is not the host widget).
/// Origin `widget.iptv*` launch payload the moved bodies still read.
class IptvZapLaunchView {
  IptvZapLaunchView(this.session);
  final IptvZapSession session;

  List<IptvChannel>? get iptvChannels => session.launchChannels;
  String? get iptvSourceId => session.iptvSourceId;
  String? get iptvSourceName => session.iptvSourceName;
  List<String>? get iptvCategories => session.iptvCategories;
  String? get iptvSelectedCategory => session.iptvSelectedCategory;
  String? get iptvContentType => session.iptvContentType;
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  get iptvBrowseProvider => session.iptvBrowseProvider;
}

/// Origin `_controlsVisible.value` reads.
class _ControlsVisibleFacade {
  const _ControlsVisibleFacade(this.value);
  final bool value;
}

/// Player IPTV zap ring, page cache, prefetch, catch-up, and zap banner.
///
/// Bodies moved from `_VideoPlayerScreenState`. Mutations go through
/// [IptvZapSession]. Overlay reads banner [ValueNotifier]s via host getters.
class IptvZapController {
  IptvZapController(this.session) : widget = IptvZapLaunchView(session);

  final IptvZapSession session;
  final IptvZapLaunchView widget;

  bool get mounted => session.isMounted;
  BuildContext get context => session.hostContext;
  void setState(VoidCallback updates) => session.runSetState(updates);

  /// The IPTV channel currently playing, or null
  /// when not in an IPTV context or the index is out of range.
  IptvChannel? get _currentIptvChannel {
    final chans = _effectiveIptvChannels;
    if (chans == null ||
        _currentIptvIndex < 0 ||
        _currentIptvIndex >= chans.length) {
      return null;
    }
    return chans[_currentIptvIndex];
  }

  IptvChannel? get currentChannel => _currentIptvChannel;

  int get _currentIptvIndex => session.currentIptvIndex;
  set _currentIptvIndex(int value) => session.currentIptvIndex = value;
  int get _iptvSwitchTicket => session.iptvSwitchTicket;
  _ControlsVisibleFacade get _controlsVisible =>
      _ControlsVisibleFacade(session.controlsVisible);
  bool get _showIptvChannelSheet => session.showIptvChannelSheet;
  bool get _showSourceSheet => session.showSourceSheet;
  bool get _showChannelGuide => session.showChannelGuide;
  PlayerGuideStyle get _playerGuideStyle => session.playerGuideStyle;
  IptvStyleTokens? get _playerGuideTokens => session.playerGuideTokens;
  bool get _recordingActiveNow => session.recordingActiveNow;

  /// Origin `_showIptvZapBanner`.
  final ValueNotifier<bool> showBanner = ValueNotifier(false);

  /// Origin `_iptvZapFloatingMounted`.
  final ValueNotifier<bool> floatingMounted = ValueNotifier(false);

  /// Origin `_iptvZapChannel`.
  final ValueNotifier<IptvChannel?> channel = ValueNotifier(null);

  /// Origin `_iptvZapEpg`.
  final ValueNotifier<EpgNowNext?> epg = ValueNotifier(null);

  /// Origin `_iptvZapEpgLoading`.
  final ValueNotifier<bool> epgLoading = ValueNotifier(false);

  /// Origin `_iptvZapClock`.
  final ValueNotifier<DateTime> clock = ValueNotifier(DateTime.now());

  bool get _showIptvZapBanner => showBanner.value;
  set _showIptvZapBanner(bool value) => showBanner.value = value;
  bool get _iptvZapFloatingMounted => floatingMounted.value;
  set _iptvZapFloatingMounted(bool value) => floatingMounted.value = value;
  IptvChannel? get _iptvZapChannel => channel.value;
  set _iptvZapChannel(IptvChannel? value) => channel.value = value;
  EpgNowNext? get _iptvZapEpg => epg.value;
  set _iptvZapEpg(EpgNowNext? value) => epg.value = value;
  bool get _iptvZapEpgLoading => epgLoading.value;
  set _iptvZapEpgLoading(bool value) => epgLoading.value = value;
  DateTime get _iptvZapClock => clock.value;
  set _iptvZapClock(DateTime value) => clock.value = value;

  // IPTV zap banner (live channels) — the broadcast lower third.
  //
  // It has two homes. Floating over bare video after a zap, and embedded as
  // the header of the controls dock (they share the bottom strip, so they
  // merge into one panel rather than fight for it). The channel/EPG data
  // below belongs to the playing channel and outlives either presentation.

  Timer? _iptvZapHideTimer;
  Timer? _iptvZapTicker;
  int _iptvZapEpgTicket = 0;

  List<IptvChannel>? _iptvChannelsOverride;
  IptvGuideContext? _iptvGuideContextOverride;
  final IptvCatchupRequestGate _iptvCatchupRequests = IptvCatchupRequestGate();

  /// The guide may replace the launch window after a source/category/search
  /// request. Playback always reads this effective list so the selected row,
  /// resume key, title, headers, and later episode navigation stay aligned.
  List<IptvChannel>? get _effectiveIptvChannels =>
      _iptvChannelsOverride ?? widget.iptvChannels;

  /// Live IPTV presents its identity in the bottom zap banner, so the corner
  /// title/channel badges stand down: they said the same thing twice, and the
  /// right-hand one was painted from launch state a zap never refreshed.
  bool get _iptvZapBannerOwnsIdentity => _currentIptvChannel?.isLive == true;

  /// Bumped whenever the guide reports a browse the user drove (a category)
  /// pick, a search, a source change). An in-flight re-anchor that predates
  /// the change must not land: it would reset the ring and the persisted
  /// category, silently undoing what the user just asked for.
  int _iptvGuideContextGeneration = 0;

  void _persistIptvGuideContext(IptvGuideContext context) {
    if (!mounted) return;
    _iptvGuideContextGeneration++;
    setState(() => _iptvGuideContextOverride = context);
  }

  /// Make the guide's selected category follow the playing channel.
  ///
  /// The native player re-anchors its browsing context to the playing
  /// channel's group on every tune and every pick. Here the category only
  /// ever moved when the user chose one, so after zapping — or after picking
  /// a channel from a different category — reopening the guide showed a
  /// category that no longer contained what was on screen.
  void _anchorIptvGuideCategory(IptvChannel channel, {Object? categories}) {
    if (!mounted || !channel.isLive) return;
    final group = channel.group?.trim();
    _applyIptvGuideCategory(
      (group == null || group.isEmpty) ? null : group,
      categories is List ? categories.whereType<String>().toList() : null,
    );
  }

  /// Point the guide at [category] verbatim, without inferring it from a
  /// channel. A zap that crossed a category boundary knows the category it
  /// landed in from the response — including the null the "All"/uncategorized
  /// wrap lands on, which no single channel's group can express.
  ///
  /// Deliberately does NOT bump [_iptvGuideContextGeneration]: that counter
  /// means "the user browsed", and an in-flight zap prefetch reading it must
  /// not be invalidated by the zap's own bookkeeping.
  void _applyIptvGuideCategory(String? category, List<String>? categories) {
    if (!mounted) return;
    final current = _iptvGuideContextOverride;
    final nextCategories =
        categories ??
        (current?.categories ?? widget.iptvCategories ?? const <String>[]);
    if (current != null &&
        current.selectedCategory == category &&
        listEquals(nextCategories, current.categories)) {
      return;
    }
    setState(() {
      _iptvGuideContextOverride = IptvGuideContext(
        categories: nextCategories,
        sourceId: current?.sourceId ?? widget.iptvSourceId,
        // Same fallback the sheet applies to a nameless source.
        sourceName: current?.sourceName ?? widget.iptvSourceName ?? 'IPTV',
        selectedCategory: category,
        contentType: current?.contentType ?? widget.iptvContentType ?? 'live',
      );
    });
  }

  void _cancelPendingIptvCatchup({bool hideFeedback = true}) {
    if (!_iptvCatchupRequests.cancel()) return;
    if (hideFeedback && mounted) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
  }

  int _beginIptvCatchupRequest() {
    _cancelPendingIptvCatchup();
    return _iptvCatchupRequests.begin();
  }

  bool _isCurrentIptvCatchupRequest(int ticket) =>
      mounted && _iptvCatchupRequests.isCurrent(ticket);

  List<IptvChannel>? get effectiveChannels => _effectiveIptvChannels;
  bool get bannerOwnsIdentity => _iptvZapBannerOwnsIdentity;
  bool get canZap => _canZapIptvChannel;
  bool get pagingActive => _iptvZapPagingActive;
  IptvGuideContext? get guideContext => _iptvGuideContextOverride;

  void persistGuideContext(IptvGuideContext context) =>
      _persistIptvGuideContext(context);
  void anchorGuideCategory(IptvChannel channel, {Object? categories}) =>
      _anchorIptvGuideCategory(channel, categories: categories);
  void cancelPendingCatchup({bool hideFeedback = true}) =>
      _cancelPendingIptvCatchup(hideFeedback: hideFeedback);
  void zap(int delta) => _zapIptvChannel(delta);
  void ensurePagingArmed() => _ensureIptvZapPagingArmed();
  void prepareBannerData(IptvChannel channel) =>
      _prepareIptvBannerData(channel);
  void raiseBanner() => _raiseIptvZapBanner();
  void hideBanner({bool immediate = false}) =>
      _hideIptvZapBanner(immediate: immediate);
  void syncBannerTicker() => _syncIptvBannerTicker();
  Future<void> playCatchup(IptvChannel channel, EpgProgramme programme) =>
      _playIptvCatchup(channel, programme);
  Future<void> switchToGuideChannel(List<IptvChannel> channels, int index) =>
      _switchToIptvGuideChannel(channels, index);
  Widget? buildInfoPanel({required bool flush}) =>
      _buildIptvInfoPanel(flush: flush);

  /// Origin `_infoPanelSignature` (IPTV branch + Debrify fallback args).
  String infoPanelSignature({
    required bool debrifyTvOwnsIdentity,
    required String? currentChannelName,
    required String? launchChannelName,
    required int? currentChannelNumber,
    required bool showVideoTitle,
  }) {
    final channel = _iptvZapChannel;
    if (channel == null || !_iptvZapBannerOwnsIdentity) {
      if (debrifyTvOwnsIdentity) {
        final name = (currentChannelName ?? launchChannelName)?.trim();
        return [
          'dtv',
          (name?.isNotEmpty ?? false) || currentChannelNumber != null
              ? 'p'
              : '',
          showVideoTitle ? 't' : '',
        ].join('|');
      }
      return '-';
    }
    final epg = _iptvZapEpg;
    return [
      _playerGuideStyle.name,
      channel.channelNumber != null ? 'n' : '',
      (channel.group?.isNotEmpty ?? false) ? 'g' : '',
      channel.logoUrl != null ? 'l' : '',
      epg?.now != null ? 'w' : '',
      epg?.next != null ? 'x' : '',
      _iptvZapEpgLoading ? 'L' : '',
      _recordingActiveNow ? 'r' : '',
    ].join('|');
  }

  void showChannelSheet() {
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    _hideIptvZapBanner();
    session.openIptvChannelSheet();
  }

  void hideChannelSheet() {
    _cancelPendingIptvCatchup();
    session.closeIptvChannelSheet();
  }

  DateTime? _lastIptvErrorShown;

  void clearErrorBurst() => _lastIptvErrorShown = null;

  void onStreamError(String error) => _onIptvStreamError(error);

  /// A plain IPTV channel's stream failed. Say so — the alternative (and the
  /// pre-existing behavior) is an indefinite black screen that reads as the
  /// whole IPTV section being broken.
  void _onIptvStreamError(String error) {
    session.noteTuneError(error);
    if (!mounted || session.iptvErrorsMuted) return;
    final channels = _effectiveIptvChannels;
    if (channels == null) return;

    // Phase 2: a live channel's error goes to the recovery machine first —
    // the snackbar below is now the SURRENDER voice (via the machine's
    // onSurrender), not the first response. Non-live keeps the old
    // say-it-immediately behavior. Auth-class failures (mpv's error string
    // is all we have — best-effort match) skip the ladder entirely: a
    // 401/403/404 repeats deterministically, so say so NOW instead of
    // retrying for 75 seconds (mirror of the TV policy's AUTH class).
    final looksAuthError = RegExp(r'\b(401|403|404)\b').hasMatch(error);
    if (_currentIptvChannel?.isLive == true &&
        !looksAuthError &&
        session.tryLiveRecoveryOnError()) {
      return;
    }

    final now = DateTime.now();
    final last = _lastIptvErrorShown;
    if (last != null && now.difference(last) < const Duration(seconds: 6)) {
      return;
    }
    _lastIptvErrorShown = now;

    final name = (_currentIptvIndex >= 0 && _currentIptvIndex < channels.length)
        ? channels[_currentIptvIndex].name
        : 'This channel';
    debugPrint('Player: IPTV stream error on "$name": $error');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$name didn't play — $error"),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void disposeTimers() {
    _iptvZapHideTimer?.cancel();
    _iptvZapTicker?.cancel();
    _iptvCatchupRequests.cancel();
    showBanner.dispose();
    floatingMounted.dispose();
    channel.dispose();
    epg.dispose();
    epgLoading.dispose();
    clock.dispose();
  }

  /// Host `_switchToIptvChannel` stays on the player. Moved zap / catch-up
  /// bodies keep calling this name; it forwards [IptvZapSession.onSwitch].
  Future<void> _switchToIptvChannel(
    int index, {
    bool quietRecovery = false,
  }) async {
    final channels = _effectiveIptvChannels;
    if (channels == null || index < 0 || index >= channels.length) return;
    await session.onSwitch(channels[index], quietRecovery: quietRecovery);
  }

  Future<void> _switchToIptvGuideChannel(
    List<IptvChannel> channels,
    int index,
  ) async {
    if (index < 0 || index >= channels.length) return;
    _cancelPendingIptvCatchup();
    final channel = channels[index];
    // Adopt the visible list first so playback starts immediately; the
    // re-anchor below then replaces it with the channel's own category.
    // A browse result is not a page of any category, so the zap window's
    // coordinates stop describing the ring until the re-anchor lands.
    _resetIptvZapPaging();
    _iptvChannelsOverride = List<IptvChannel>.from(channels);
    // Take this tune's generation from the call itself. _switchToIptvChannel
    // bumps the ticket synchronously before its first await, and it returns
    // normally when a newer tune supersedes it — so reading the ticket AFTER
    // the await would read the newer tune's value and defeat every staleness
    // check downstream.
    final switchFuture = _switchToIptvChannel(index);
    final switchTicket = _iptvSwitchTicket;
    await switchFuture;
    if (!mounted || switchTicket != _iptvSwitchTicket) return;
    unawaited(_reanchorIptvRingToCategory(channel, switchTicket: switchTicket));
  }

  /// Rebuild the channel ring around [channel] from its own category.
  ///
  /// The native guide does this on every pick (`beginIptvCategoryZapSession`):
  /// the list you navigate afterwards is the channel's category, never the
  /// list you happened to pick from. Without it, choosing a channel out of a
  /// search left the search matches standing in as the entire channel list —
  /// so the guide reopened onto a handful of unrelated channels, and the
  /// category shown alongside them belonged to the previous selection.
  ///
  /// Best effort by design: playback has already started, so a failed or
  /// unhelpful page simply leaves the adopted list in place, which is what
  /// the native fallback does too.
  Future<void> _reanchorIptvRingToCategory(
    IptvChannel channel, {
    required int switchTicket,
  }) async {
    final provider = widget.iptvBrowseProvider;
    if (provider == null || !channel.isLive) return;
    if (switchTicket != _iptvSwitchTicket) return;
    final category = channel.group?.trim();
    final contextGeneration = _iptvGuideContextGeneration;

    Map<String, dynamic>? result;
    try {
      result = await provider({
        'action': 'zapPage',
        'sourceId': _iptvGuideContextOverride?.sourceId ?? widget.iptvSourceId,
        'contentType': 'live',
        'category': (category == null || category.isEmpty) ? null : category,
        'query': '',
        'anchorUrl': channel.url,
        'anchorName': channel.name,
        'offset': 0,
        // A full page rather than the native player's 200: unlike the native
        // guide this one has no scroll-prefetch to grow a small window, so the
        // ring has to arrive anchored AND whole. Anything past the provider's
        // own maximum is clamped there.
        'limit': _kIptvZapPageSize,
      });
    } catch (error) {
      debugPrint('Player: IPTV ring re-anchor failed: $error');
      return;
    }
    if (!mounted || result == null) return;
    // A newer zap owns the ring now — installing this page would drop the
    // viewer onto the wrong channel's neighbours.
    if (switchTicket != _iptvSwitchTicket) return;
    // The user browsed while this was in flight. Their category is the
    // current intent; this page predates it.
    if (contextGeneration != _iptvGuideContextGeneration) return;
    // Last line of defence: whatever else moved, the ring must only ever be
    // rebuilt around the channel that is actually playing.
    final playing = _currentIptvChannel;
    if (playing == null ||
        playing.url != channel.url ||
        playing.name != channel.name) {
      return;
    }

    final page = _parseIptvZapPage(result);
    if (page == null) return;
    final playingIndex = page.channels.indexWhere(
      (candidate) =>
          candidate.url == channel.url && candidate.name == channel.name,
    );
    // The page has to contain what is playing, or the ring would no longer
    // describe the channel on screen.
    if (playingIndex < 0) return;

    _clearIptvZapBoundaryCache();
    setState(() {
      _iptvChannelsOverride = page.channels;
      _currentIptvIndex = playingIndex;
      // Where this window sits in the category. Zapping past its edge needs
      // both numbers: without them the window's end and the category's end
      // are indistinguishable, and a category larger than one page would
      // cross into the next category partway through.
      _iptvZapWindowOffset = page.offset;
      _iptvZapCategoryTotal = page.total;
      // Binds every later boundary request to the source this ring came from,
      // however far the guide wanders afterwards.
      _iptvZapSourceId =
          page.sourceId ??
          _iptvGuideContextOverride?.sourceId ??
          widget.iptvSourceId;
      _iptvZapCategory = page.category;
      if (page.categories.isNotEmpty) _iptvZapCategories = page.categories;
      _iptvZapPagingActive = true;
    });
    _anchorIptvGuideCategory(channel, categories: result['categories']);
  }

  // ── Live channel zapping ─────────────────────────────────────────────────
  //
  // Port of the native player's zap ladder (`zapIptvChannel`): step inside the
  // loaded window, page through the rest of the category at the window's
  // edges, and cross into the adjacent category when the category itself runs
  // out — wrapping at the last one. The browse provider already speaks this
  // protocol (native drove it), so the only thing this side has to carry is
  // where the window sits and what is already on its way.
  //
  // One deliberate divergence: native trims its hidden window to 600 rows to
  // keep a TV's adapter light, and re-fetches what it dropped. Here the same
  // list backs the guide, which has no scroll-prefetch to refill it, so
  // trimming would silently shrink the guide instead.

  /// Page size asked of the browse provider. It clamps to its own per-launch
  /// maximum, so drift here changes only how many rows arrive, never
  /// correctness: an overlapping backward page merges, a short one just
  /// leaves more to fetch.
  static const int _kIptvZapPageSize = 1500;

  /// How close to the window's edge counts as "about to need what's next".
  static const int _kIptvZapEdgeMargin = 12;

  /// Absolute position, within the active category, of the first channel of
  /// [_effectiveIptvChannels].
  int _iptvZapWindowOffset = 0;

  /// How many channels the active category holds in total; the window is a
  /// slice of it.
  int _iptvZapCategoryTotal = 0;

  /// The ring came from a paged response, so [_iptvZapWindowOffset] and
  /// [_iptvZapCategoryTotal] describe it. False for the launch window or a
  /// browse result standing in — zapping then just wraps inside the list,
  /// which is what native does before its paging session starts.
  bool _iptvZapPagingActive = false;

  /// The source and category the ring belongs to. Kept apart from the guide's
  /// selection on purpose: browsing can move the guide to another source or
  /// category — and leave it there without ever tuning — while the ring keeps
  /// describing what is playing. Asking the guide's source for the ring's
  /// category would fetch a category that source may not even have.
  String? _iptvZapSourceId;
  String? _iptvZapCategory;
  List<String> _iptvZapCategories = const [];

  int _iptvZapRequestTicket = 0;
  bool _iptvZapRequestInFlight = false;

  /// Presses that arrived while a page was loading. Crossing a page or a
  /// category is a round trip, so holding the key down has to queue rather
  /// than drop.
  final List<int> _iptvZapPendingInputs = [];
  bool _iptvZapDrainingInputs = false;

  /// The adjacent category, fetched before it is needed so crossing one costs
  /// no more than stepping inside the current one.
  String? _iptvZapCachedOriginCategory;
  int _iptvZapCachedDirection = 0;
  _IptvZapPage? _iptvZapCachedPage;

  /// Live IPTV with somewhere to zap to — either more than one channel in the
  /// ring, or a paged context that can fetch more.
  bool get _canZapIptvChannel =>
      _currentIptvChannel?.isLive == true &&
      ((_effectiveIptvChannels?.length ?? 0) > 1 || _iptvZapPagingActive);

  void _clearIptvZapBoundaryCache() {
    _iptvZapCachedOriginCategory = null;
    _iptvZapCachedDirection = 0;
    _iptvZapCachedPage = null;
  }

  /// The ring is about to stop being a page of a category. Bumping the request
  /// ticket strands anything in flight: it would otherwise merge a page of the
  /// old category into the new ring at positions that mean nothing there.
  void _resetIptvZapPaging() {
    _iptvZapPagingActive = false;
    _iptvZapWindowOffset = 0;
    _iptvZapCategoryTotal = 0;
    _iptvZapSourceId = null;
    _iptvZapCategory = null;
    _iptvZapRequestTicket++;
    _iptvZapRequestInFlight = false;
    _iptvZapPendingInputs.clear();
    _clearIptvZapBoundaryCache();
  }

  /// A re-anchor is out arming the ladder, so a burst of presses can't stack
  /// full-category queries behind it.
  bool _iptvZapArmingPaging = false;

  /// Arm the ladder around whatever live channel is playing now.
  ///
  /// The launch bootstrap re-anchors the channel the player opened with, but a
  /// zap landing before that response does moves the switch ticket on and the
  /// response is dropped. Nothing else would re-arm it, so the ladder would sit
  /// inactive and zapping would circle the launch window until the user opened
  /// the guide and retuned. Retrying from the zap itself closes that: the first
  /// press after a lost bootstrap arms the ladder for the channel it landed on.
  void _ensureIptvZapPagingArmed() {
    if (_iptvZapPagingActive || _iptvZapArmingPaging) return;
    if (widget.iptvBrowseProvider == null) return;
    final channel = _currentIptvChannel;
    if (channel == null || !channel.isLive) return;
    _iptvZapArmingPaging = true;
    unawaited(
      _reanchorIptvRingToCategory(
        channel,
        switchTicket: _iptvSwitchTicket,
      ).whenComplete(() => _iptvZapArmingPaging = false),
    );
  }

  /// Previous/next channel in guide order.
  void _zapIptvChannel(int delta) {
    final channels = _effectiveIptvChannels;
    final current = _currentIptvChannel;
    if (channels == null || current == null || !current.isLive) return;
    if (!_iptvZapPagingActive && channels.length < 2) return;
    final from = _currentIptvIndex.clamp(0, channels.length - 1);
    final next = from + delta;

    if (!_iptvZapPagingActive) {
      // No paged context: the ring is all there is, so wrap inside it.
      unawaited(
        _switchToIptvChannel((next + channels.length) % channels.length),
      );
      // Tuning has already moved the index and the switch ticket, so this arms
      // the ladder around the channel just landed on.
      _ensureIptvZapPagingArmed();
      return;
    }

    if (next >= 0 && next < channels.length) {
      unawaited(_switchToIptvChannel(next));
      unawaited(_prefetchIptvZapPage(delta));
      unawaited(_prefetchAdjacentIptvCategory(delta));
      return;
    }

    final firstAbsolute = _iptvZapWindowOffset;
    final lastAbsolute = _iptvZapWindowOffset + channels.length - 1;
    final hasAnotherPage = delta > 0
        ? lastAbsolute + 1 < _iptvZapCategoryTotal
        : firstAbsolute > 0;
    if (hasAnotherPage) {
      // The category continues past the window. Hold the press until the page
      // it needs has landed, then replay it against the grown ring.
      _queuePendingIptvZapInput(delta);
      unawaited(_prefetchIptvZapPage(delta));
      return;
    }

    if (_consumeCachedAdjacentIptvCategory(delta)) return;
    unawaited(_requestAdjacentIptvCategory(delta));
  }

  /// One page request at a time, like native: a second in-flight request would
  /// race the first into the ring with no way to order the two.
  Future<_IptvZapPage?> _requestIptvZapPage({
    required String? category,
    required int offset,
    bool fromEnd = false,
  }) async {
    final provider = widget.iptvBrowseProvider;
    if (provider == null || _iptvZapRequestInFlight) return null;
    final ticket = ++_iptvZapRequestTicket;
    final contextGeneration = _iptvGuideContextGeneration;
    _iptvZapRequestInFlight = true;

    Map<String, dynamic>? result;
    try {
      result = await provider({
        'action': 'zapPage',
        // The ring's own source, not the guide's — see [_iptvZapSourceId].
        'sourceId':
            _iptvZapSourceId ??
            _iptvGuideContextOverride?.sourceId ??
            widget.iptvSourceId,
        'contentType': 'live',
        'category': (category == null || category.isEmpty) ? null : category,
        'query': '',
        'offset': offset < 0 ? 0 : offset,
        'limit': _kIptvZapPageSize,
        'fromEnd': fromEnd,
      });
    } catch (error) {
      debugPrint('Player: IPTV zap page failed: $error');
    }
    // A newer request (or a reset) owns the flag now — leave it to them.
    if (ticket != _iptvZapRequestTicket) return null;
    _iptvZapRequestInFlight = false;
    if (!mounted || result == null) {
      // Replaying queued presses against a ring that never grew would spin.
      _iptvZapPendingInputs.clear();
      return null;
    }
    // The user browsed while this was in flight; their category is the current
    // intent and every queued press belonged to the old one.
    if (contextGeneration != _iptvGuideContextGeneration) {
      _iptvZapPendingInputs.clear();
      return null;
    }
    return _parseIptvZapPage(result);
  }

  _IptvZapPage? _parseIptvZapPage(Map<String, dynamic> result) {
    final raw = result['channels'];
    if (raw is! List) return null;
    final channels = [
      for (final entry in raw.whereType<Map>())
        iptvChannelFromBrowsePayload(Map<String, dynamic>.from(entry)),
    ];
    final rawOffset = result['pageOffset'];
    final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;
    final rawTotal = result['totalChannels'];
    final total = rawTotal is num ? rawTotal.toInt() : channels.length;
    final rawSourceId = (result['sourceId'] as String?)?.trim();
    final rawCategory = (result['selectedCategory'] as String?)?.trim();
    final rawCategories = result['categories'];
    return _IptvZapPage(
      channels: channels,
      offset: offset,
      // A total that doesn't cover the page it came with would put the
      // category's end behind the window's own last row.
      total: math.max(total, offset + channels.length),
      sourceId: (rawSourceId == null || rawSourceId.isEmpty)
          ? null
          : rawSourceId,
      category: (rawCategory == null || rawCategory.isEmpty)
          ? null
          : rawCategory,
      categories: rawCategories is List
          ? [
              for (final entry in rawCategories.whereType<String>())
                if (entry.isNotEmpty) entry,
            ]
          : const [],
    );
  }

  /// Replace the ring with [page]. The caller tunes afterwards, so the index
  /// left behind here is only a starting point.
  void _installIptvZapWindow(
    _IptvZapPage page, {
    required bool preservePlayingChannel,
  }) {
    if (page.channels.isEmpty) return;
    if (page.category != _iptvZapCategory) _clearIptvZapBoundaryCache();
    final playing = preservePlayingChannel ? _currentIptvChannel : null;
    var index = 0;
    if (playing != null) {
      final found = page.channels.indexWhere(
        (candidate) =>
            candidate.url == playing.url && candidate.name == playing.name,
      );
      if (found >= 0) index = found;
    }
    setState(() {
      _iptvChannelsOverride = page.channels;
      _currentIptvIndex = index;
      _iptvZapWindowOffset = page.offset;
      _iptvZapCategoryTotal = page.total;
      _iptvZapSourceId = page.sourceId ?? _iptvZapSourceId;
      _iptvZapCategory = page.category;
      if (page.categories.isNotEmpty) _iptvZapCategories = page.categories;
      _iptvZapPagingActive = true;
    });
  }

  /// Splice a freshly loaded page into the ring, growing the window rather
  /// than replacing it — the channel on screen has to keep its place, and the
  /// guide is looking at the same list.
  void _mergeIptvZapPage(_IptvZapPage page) {
    if (!_iptvZapPagingActive || page.channels.isEmpty) return;
    if (page.category != _iptvZapCategory) return;
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;

    final windowStart = _iptvZapWindowOffset;
    final merged = iptvMergeZapWindow(
      window: channels,
      windowOffset: windowStart,
      page: page.channels,
      pageOffset: page.offset,
    );
    // The page didn't touch the window — see iptvMergeZapWindow.
    if (merged == null) return;

    final playing = _currentIptvChannel;
    var index = _currentIptvIndex + (windowStart - merged.offset);
    if (playing != null) {
      final found = merged.channels.indexWhere(
        (candidate) =>
            candidate.url == playing.url && candidate.name == playing.name,
      );
      if (found >= 0) index = found;
    }
    setState(() {
      _iptvChannelsOverride = merged.channels;
      _currentIptvIndex = index.clamp(0, merged.channels.length - 1);
      _iptvZapWindowOffset = merged.offset;
      _iptvZapCategoryTotal = math.max(
        page.total,
        merged.offset + merged.channels.length,
      );
      if (page.categories.isNotEmpty) _iptvZapCategories = page.categories;
    });
  }

  /// Pull in the next page of the current category once zapping gets near the
  /// window's edge.
  Future<void> _prefetchIptvZapPage(int delta) async {
    if (!_iptvZapPagingActive || _iptvZapRequestInFlight) return;
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    final firstAbsolute = _iptvZapWindowOffset;
    final lastAbsolute = firstAbsolute + channels.length - 1;
    final shouldLoad = delta > 0
        ? lastAbsolute + 1 < _iptvZapCategoryTotal &&
              _currentIptvIndex >= channels.length - _kIptvZapEdgeMargin
        : firstAbsolute > 0 && _currentIptvIndex < _kIptvZapEdgeMargin;
    if (!shouldLoad) return;

    final page = await _requestIptvZapPage(
      category: _iptvZapCategory,
      offset: delta > 0
          ? lastAbsolute + 1
          : math.max(0, firstAbsolute - _kIptvZapPageSize),
    );
    if (!mounted || page == null) return;
    _mergeIptvZapPage(page);
    _drainPendingIptvZapInputs();
  }

  String? _adjacentIptvCategory(int delta, int attempt) =>
      iptvAdjacentZapCategory(
        categories: _iptvZapCategories,
        current: _iptvZapCategory,
        delta: delta,
        attempt: attempt,
      );

  Future<void> _prefetchAdjacentIptvCategory(
    int delta, {
    int attempt = 1,
  }) async {
    // A cached page only answers the direction it was fetched for; turning
    // around makes it the wrong end of the wrong category.
    if (_iptvZapCachedPage != null && _iptvZapCachedDirection != delta) {
      _clearIptvZapBoundaryCache();
    }
    if (!_iptvZapPagingActive ||
        _iptvZapRequestInFlight ||
        _iptvZapCategory == null ||
        _iptvZapCachedPage != null) {
      return;
    }
    final channels = _effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    final nearBoundary = delta > 0
        ? _iptvZapWindowOffset + channels.length >= _iptvZapCategoryTotal &&
              _currentIptvIndex >= channels.length - _kIptvZapEdgeMargin
        : _iptvZapWindowOffset == 0 && _currentIptvIndex < _kIptvZapEdgeMargin;
    if (!nearBoundary) return;

    final target = _adjacentIptvCategory(delta, attempt);
    if (target == null) return;
    final origin = _iptvZapCategory;
    final page = await _requestIptvZapPage(
      category: target,
      offset: 0,
      fromEnd: delta < 0,
    );
    if (!mounted || page == null) return;
    // Zapping moved on while this loaded; it is no longer the next category.
    if (origin != _iptvZapCategory) return;
    if (page.channels.isEmpty) {
      await _prefetchAdjacentIptvCategory(delta, attempt: attempt + 1);
      return;
    }
    _iptvZapCachedOriginCategory = origin;
    _iptvZapCachedDirection = delta;
    _iptvZapCachedPage = page;
    _drainPendingIptvZapInputs();
  }

  /// Cross into the prefetched category with no round trip. Returns false when
  /// nothing usable was cached, leaving the caller to fetch.
  bool _consumeCachedAdjacentIptvCategory(int delta) {
    final cached = _iptvZapCachedPage;
    if (cached == null ||
        cached.channels.isEmpty ||
        _iptvZapCachedOriginCategory != _iptvZapCategory ||
        _iptvZapCachedDirection != delta) {
      return false;
    }
    _clearIptvZapBoundaryCache();
    _enterIptvZapCategory(cached, delta);
    unawaited(_prefetchAdjacentIptvCategory(delta));
    return true;
  }

  /// Adopt [page] as the ring and tune the channel the zap was heading for:
  /// going forwards that is the new category's first channel, going backwards
  /// its last.
  void _enterIptvZapCategory(_IptvZapPage page, int delta) {
    _installIptvZapWindow(page, preservePlayingChannel: false);
    unawaited(_switchToIptvChannel(delta > 0 ? 0 : page.channels.length - 1));
    // After the tune, not before: the switch anchors the guide to the tuned
    // channel's own group, and the response's category is the more accurate
    // of the two (it can be the null of an uncategorized wrap, which no
    // channel's group expresses).
    _applyIptvGuideCategory(
      page.category,
      page.categories.isEmpty ? null : page.categories,
    );
    unawaited(_prefetchIptvZapPage(delta));
  }

  /// The category ran out. Load the adjacent one, skipping any that come back
  /// empty, and give up once every category has been tried.
  Future<void> _requestAdjacentIptvCategory(
    int delta, {
    int attempt = 1,
  }) async {
    if (_iptvZapRequestInFlight) {
      _queuePendingIptvZapInput(delta);
      return;
    }
    final hasCategories = _iptvZapCategories.any((c) => c.isNotEmpty);
    if (_iptvZapCategory == null || !hasCategories) {
      // An uncategorized/"All" context has no category boundary to cross:
      // wrap by paging the opposite end of the same result set.
      final page = await _requestIptvZapPage(
        category: null,
        offset: 0,
        fromEnd: delta < 0,
      );
      if (!mounted || page == null || page.channels.isEmpty) {
        // Nothing came back to zap into, so nothing will drain these either.
        _iptvZapPendingInputs.clear();
        return;
      }
      _enterIptvZapCategory(page, delta);
      _drainPendingIptvZapInputs();
      return;
    }

    // Null once the walk has been all the way round — every category was
    // empty, so nothing will ever drain the queued presses.
    final target = _adjacentIptvCategory(delta, attempt);
    if (target == null) {
      _iptvZapPendingInputs.clear();
      return;
    }
    final page = await _requestIptvZapPage(
      category: target,
      offset: 0,
      fromEnd: delta < 0,
    );
    if (!mounted || page == null) return;
    if (page.channels.isEmpty) {
      await _requestAdjacentIptvCategory(delta, attempt: attempt + 1);
      return;
    }
    _enterIptvZapCategory(page, delta);
    unawaited(_prefetchAdjacentIptvCategory(delta));
    _drainPendingIptvZapInputs();
  }

  void _queuePendingIptvZapInput(int delta) {
    if (_iptvZapPendingInputs.length >= 24) return;
    _iptvZapPendingInputs.add(delta >= 0 ? 1 : -1);
  }

  void _drainPendingIptvZapInputs() {
    if (_iptvZapDrainingInputs) return;
    _iptvZapDrainingInputs = true;
    try {
      while (_iptvZapPendingInputs.isNotEmpty) {
        final queued = _iptvZapPendingInputs.length;
        _zapIptvChannel(_iptvZapPendingInputs.removeAt(0));
        // Another round trip started: the rest drain when it lands.
        if (_iptvZapRequestInFlight) break;
        // The press went straight back on the queue without starting one, so
        // nothing will arrive to move it along — stop instead of spinning.
        if (_iptvZapPendingInputs.length >= queued) break;
      }
    } finally {
      _iptvZapDrainingInputs = false;
    }
  }

  /// Turn an archived EPG programme into a finite, seekable IPTV item in the
  /// current player. The normal IPTV switching path remains responsible for
  /// headers, transition feedback, tracks, and resume identity.
  Future<void> _playIptvCatchup(
    IptvChannel channel,
    EpgProgramme programme,
  ) async {
    final requestTicket = _beginIptvCatchupRequest();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Preparing replay of "${programme.title}"…'),
        duration: const Duration(seconds: 30),
      ),
    );
    String? url;
    try {
      url = await IptvEpgService.instance.catchupUrl(channel.url, programme);
    } catch (error) {
      debugPrint('Player: IPTV replay lookup failed: $error');
    }
    if (!_isCurrentIptvCatchupRequest(requestTicket)) return;
    if (url == null) {
      _iptvCatchupRequests.complete(requestTicket);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Replay is not available')),
      );
      return;
    }

    final sourceId =
        channel.attributes['source_playlist_id'] ??
        _iptvGuideContextOverride?.sourceId ??
        widget.iptvSourceId;
    final replay = IptvChannel(
      name: programme.title,
      url: url,
      logoUrl: channel.logoUrl,
      group: channel.name,
      contentType: 'vod',
      httpHeaders: channel.httpHeaders,
      attributes: {if (sourceId != null) 'source_playlist_id': sourceId},
    );
    await StorageService.recordIptvWatch(
      replay.url,
      channelName: replay.name,
      logoUrl: replay.logoUrl,
      group: replay.group,
      playlistId: sourceId,
      httpHeaders: replay.httpHeaders,
    );
    if (!_isCurrentIptvCatchupRequest(requestTicket)) return;
    _iptvCatchupRequests.complete(requestTicket);
    messenger.hideCurrentSnackBar();
    // A replay is a single on-demand item, not a page of any category.
    _resetIptvZapPaging();
    _iptvChannelsOverride = [replay];
    await _switchToIptvChannel(0);
  }

  /// Adopt [channel] as the banner's subject and start its guide lookup.
  ///
  /// Called on the first tune and on every zap, whatever is on screen at the
  /// time: the dock can be opened minutes later and must find the panel's
  /// data already loaded.
  void _prepareIptvBannerData(IptvChannel channel) {
    if (!mounted || !channel.isLive) return;
    final ticket = ++_iptvZapEpgTicket;
    // Whatever the guide already knows paints immediately; the fetch below
    // only ever upgrades it.
    final known = IptvEpgService.instance.peekNowNext(channel.url);
    setState(() {
      _iptvZapChannel = channel;
      _iptvZapEpg = known;
      _iptvZapEpgLoading = known == null;
      _iptvZapClock = DateTime.now();
    });
    if (known == null) unawaited(_loadIptvZapBannerEpg(channel, ticket));
    // Zapping from VOD to live with the dock already open gives the panel its
    // first channel here rather than at raise time — start its clock.
    _syncIptvBannerTicker();
  }

  /// Float the banner over bare video and let it fade itself out.
  void _raiseIptvZapBanner() {
    if (!mounted || _iptvZapChannel == null) return;
    // Anything the user deliberately opened keeps the frame. The dock is the
    // exception it used to share this strip with: it now carries the same
    // panel itself, so there is nothing to raise over it.
    if (_showIptvChannelSheet ||
        _showSourceSheet ||
        _showChannelGuide ||
        _controlsVisible.value) {
      return;
    }
    setState(() {
      _showIptvZapBanner = true;
      _iptvZapFloatingMounted = true;
    });
    _iptvZapHideTimer?.cancel();
    _iptvZapHideTimer = Timer(
      const Duration(milliseconds: 4500),
      _hideIptvZapBanner,
    );
    _syncIptvBannerTicker();
  }

  /// [immediate] skips the fade and unmounts in the same frame — for a handoff
  /// to the dock's copy, where a fade would show both at once.
  void _hideIptvZapBanner({bool immediate = false}) {
    _iptvZapHideTimer?.cancel();
    _iptvZapHideTimer = null;
    final live = _showIptvZapBanner || (immediate && _iptvZapFloatingMounted);
    if (mounted && live) {
      setState(() {
        _showIptvZapBanner = false;
        if (immediate) _iptvZapFloatingMounted = false;
      });
    }
    _syncIptvBannerTicker();
  }

  /// The panel's clock only has to run while the panel is on screen — in
  /// either home. Without it the countdown and the elapsed rule sit frozen,
  /// which is most obvious exactly where the dock is used: while paused,
  /// where the position stream has stopped driving rebuilds.
  void _syncIptvBannerTicker() {
    final onScreen =
        _iptvZapChannel != null &&
        (_showIptvZapBanner ||
            (_controlsVisible.value && _iptvZapBannerOwnsIdentity));
    if (!onScreen) {
      _iptvZapTicker?.cancel();
      _iptvZapTicker = null;
      return;
    }
    if (_iptvZapTicker != null) return;
    _iptvZapTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _iptvZapClock = DateTime.now());
      _refreshIptvBannerEpgIfEnded();
    });
  }

  /// The dock can stay open past the end of the programme it is describing.
  /// Re-ask once the current one has finished rather than leave a listing
  /// that is quietly wrong.
  void _refreshIptvBannerEpgIfEnded() {
    if (_iptvZapEpgLoading) return;
    final channel = _iptvZapChannel;
    final current = _iptvZapEpg?.now;
    if (channel == null || current == null) return;
    if (current.stop.isAfter(DateTime.now())) return;
    final ticket = ++_iptvZapEpgTicket;
    setState(() => _iptvZapEpgLoading = true);
    unawaited(_loadIptvZapBannerEpg(channel, ticket));
  }

  /// The same lazy now/next fetch the guide rows use. [ticket] is the banner's
  /// generation: a zap that lands mid-flight owns the banner, so a late answer
  /// for the previous channel is dropped rather than painted under the new
  /// channel's name.
  Future<void> _loadIptvZapBannerEpg(IptvChannel channel, int ticket) async {
    EpgNowNext? result;
    try {
      result = await IptvEpgService.instance.nowNext(channel.url);
    } catch (_) {
      result = null;
    }
    if (!mounted || ticket != _iptvZapEpgTicket) return;
    setState(() {
      _iptvZapEpg = result;
      _iptvZapEpgLoading = false;
    });
  }

  Widget? _buildIptvInfoPanel({required bool flush}) {
    final channel = _iptvZapChannel;
    if (channel == null || !_iptvZapBannerOwnsIdentity) return null;
    return IptvZapBanner(
      channel: channel,
      epg: _iptvZapEpg,
      epgLoading: _iptvZapEpgLoading,
      now: _iptvZapClock,
      flush: flush,
      style: _playerGuideStyle,
      tokens: _playerGuideTokens,
      isRecording: _recordingActiveNow,
    );
  }
}
