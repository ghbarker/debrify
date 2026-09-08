import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/quick_play_rules.dart';
import '../../services/analytics_service.dart';
import '../../services/cloud/cloud_provider_id.dart';
import '../../services/source_priority.dart';
import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../utils/tv_reveal.dart';
import 'widgets/settings_widgets.dart';

/// Quick Play settings, simplified: Movies/Series tabs, an "Addon Priority"
/// list (torrent engines and Stremio addons in one flat, reorderable list),
/// a "Prefer torrents" switch, a "Streams to try" failover budget, and — for
/// series — a "Prefer season packs" switch, plus the opt-in "Failover chain"
/// section exposing every [FailoverChainPolicy] knob. The underlying
/// [QuickPlayRules] engine keeps every capability; legacy customizations still
/// load and apply, they just can't be edited here anymore.
class QuickPlaySettingsPage extends StatefulWidget {
  const QuickPlaySettingsPage({super.key});

  @override
  State<QuickPlaySettingsPage> createState() => _QuickPlaySettingsPageState();
}

class _QuickPlaySettingsPageState extends State<QuickPlaySettingsPage> {
  bool _loading = true;
  bool _series = false;
  bool _pikPak = false;

  /// 'quick' | 'smart' | 'always' — see [QuickPlayPolicyPrefs.getPlayButtonMode].
  /// Global on purpose: unlike the rules below it, this is not a per-content
  /// tab setting, so it sits above the Movies/Series tabs.
  String _playMode = 'quick';
  late QuickPlayRules _movie;
  late QuickPlayRules _show;

  /// Every orderable provider, in shipped-default order.
  List<SourceProviderRef> _providers = const [];

  /// The arranged list for each tab (stored order applied over providers).
  List<SourceProviderRef> _orderedMovie = const [];
  List<SourceProviderRef> _orderedSeries = const [];

  /// TV pick-up/drop reorder: the key of the row currently "grabbed".
  String? _pickedKey;

  final _playModeNode = FocusNode(debugLabel: 'quick-play-play-button-mode');
  final _movieTab = FocusNode(debugLabel: 'quick-play-movies-tab');
  final _seriesTab = FocusNode(debugLabel: 'quick-play-series-tab');
  final _torrentToggle = FocusNode(debugLabel: 'quick-play-prefer-torrents');
  final _packToggle = FocusNode(debugLabel: 'quick-play-prefer-packs');
  final _attemptsNode = FocusNode(debugLabel: 'quick-play-max-attempts');
  final _reset = FocusNode(debugLabel: 'quick-play-reset');
  final Map<String, FocusNode> _rowNodes = {};

  // Failover chain section. One node per control so TV DPAD walks every knob.
  final _chainToggle = FocusNode(debugLabel: 'quick-play-chain-enabled');
  final _chainSiblings = FocusNode(debugLabel: 'quick-play-chain-siblings');
  final _chainLater = FocusNode(debugLabel: 'quick-play-chain-later');
  final _chainMatch = FocusNode(debugLabel: 'quick-play-chain-match');
  final _chainProbe = FocusNode(debugLabel: 'quick-play-chain-probe');
  final _chainProbeTimeout = FocusNode(
    debugLabel: 'quick-play-chain-probe-timeout',
  );
  final _chainDemotion = FocusNode(debugLabel: 'quick-play-chain-demotion');
  final Map<String, FocusNode> _chainRowNodes = {};
  final Map<String, FocusNode> _chainNeverProbeNodes = {};

  /// TV pick-up/drop reorder for the chain's provider order (parallel to
  /// [_pickedKey] for the Addon Priority list).
  String? _chainPicked;

  QuickPlayRules get _rules => _series ? _show : _movie;
  bool get _isMovie => !_series;
  List<SourceProviderRef> get _ordered =>
      _series ? _orderedSeries : _orderedMovie;

  bool get _preferTorrents =>
      _rules.sourceMode != QuickPlaySourceMode.addonsThenTorrents &&
      _rules.sourceMode != QuickPlaySourceMode.addonsOnly;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('quick_play_settings');
    _load();
  }

  @override
  void dispose() {
    for (final node in [
      _playModeNode,
      _movieTab,
      _seriesTab,
      _torrentToggle,
      _packToggle,
      _attemptsNode,
      _reset,
      ..._rowNodes.values,
      _chainToggle,
      _chainSiblings,
      _chainLater,
      _chainMatch,
      _chainProbe,
      _chainProbeTimeout,
      _chainDemotion,
      ..._chainRowNodes.values,
      ..._chainNeverProbeNodes.values,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
    final show = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    final provider = await ProviderCredentialPrefs.getDefaultTorrentProvider();
    final playMode = await QuickPlayPolicyPrefs.getPlayButtonMode();
    if (!mounted) return;
    setState(() {
      _movie = movie;
      _show = show;
      _pikPak = provider == 'pikpak';
      _playMode = playMode;
      _loading = false;
    });
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _movieTab.requestFocus();
      });
    }
    // Provider enumeration touches the engine registry (disk) — fill the
    // priority list when it lands instead of blocking the whole page on it.
    unawaited(_loadProviders());
  }

  Future<void> _loadProviders() async {
    final providers = await SourcePriority.providers();
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _orderedMovie = _applyStoredOrder(_movie.sourcePriority);
      _orderedSeries = _applyStoredOrder(_show.sourcePriority);
    });
  }

  /// Stored keys first (skipping uninstalled ones), then any provider the
  /// stored order doesn't know about, in default order.
  List<SourceProviderRef> _applyStoredOrder(List<String> stored) {
    final byKey = {for (final p in _providers) p.key: p};
    final out = <SourceProviderRef>[];
    for (final key in stored) {
      final p = byKey.remove(key);
      if (p != null) out.add(p);
    }
    out.addAll(byKey.values);
    return out;
  }

  Future<void> _save(QuickPlayRules rules) async {
    final isMovie = _isMovie;
    setState(() {
      if (isMovie) {
        _movie = rules;
      } else {
        _show = rules;
      }
    });
    await QuickPlayPolicyPrefs.setQuickPlayRules(rules, isMovie: isMovie);
  }

  QuickPlayRules _custom(QuickPlayRules candidate) {
    final compatible = candidate.copyWith(
      preset: QuickPlayPreset.debrifyDefault,
    );
    return compatible == QuickPlayRules.debrifyDefault(isMovie: _isMovie)
        ? compatible
        : candidate.copyWith(preset: QuickPlayPreset.custom);
  }

  Future<void> _change(QuickPlayRules Function(QuickPlayRules) change) =>
      _save(_custom(change(_rules)));

  void _setPreferTorrents(bool value) {
    _change(
      (r) => r.copyWith(
        sourceMode: value
            ? QuickPlaySourceMode.torrentsThenAddons
            : QuickPlaySourceMode.addonsThenTorrents,
      ),
    );
  }

  void _setPreferPacks(bool value) {
    _change(
      (r) => r.copyWith(
        preferSeriesPacks: value,
        // A legacy exact-episode-only profile would silently defeat the
        // switch — turning packs ON must actually allow packs.
        packPreference:
            value &&
                r.packPreference == QuickPlayPackPreference.exactEpisodeOnly
            ? QuickPlayPackPreference.widestFirst
            : null,
      ),
    );
  }

  /// What the player will actually count up to — it computes
  /// `tryNext ? maxAttempts : 1`, so a legacy profile with failover OFF reads
  /// as 1 here no matter what `maxAttempts` still stores.
  int get _effectiveAttempts =>
      _rules.tryNextOnFailure ? _rules.maxAttempts.clamp(1, 10) : 1;

  /// One control drives both fields: 1 means "never fall back", which is
  /// exactly `tryNextOnFailure: false`. Anything higher re-arms failover so
  /// the number the user picked is the number the player honors.
  void _setMaxAttempts(int value) {
    final attempts = value.clamp(1, 10);
    _change(
      (r) => r.copyWith(tryNextOnFailure: attempts > 1, maxAttempts: attempts),
    );
  }

  void _moveRow(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    final list = List<SourceProviderRef>.from(_ordered);
    if (from >= list.length || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    setState(() {
      if (_series) {
        _orderedSeries = list;
      } else {
        _orderedMovie = list;
      }
    });
    // Persist the full materialized order — from here on this tab is
    // "customized" and ordering everywhere follows the list.
    _change((r) => r.copyWith(sourcePriority: [for (final p in list) p.key]));
  }

  KeyEventResult _rowKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Moves resolve the picked row against the CURRENT order, not this
    // handler's build-time [index]: a buffered second press (DPAD repeat on a
    // janky TV frame) can arrive before the rebuild swaps the row's closure.
    final pickedIndex = _pickedKey == null
        ? -1
        : _ordered.indexWhere((p) => p.key == _pickedKey);
    final picked = pickedIndex >= 0;

    if (isActivateOrSpaceKey(key)) {
      setState(
        () => _pickedKey = _pickedKey == _ordered[index].key
            ? null
            : _ordered[index].key,
      );
      return KeyEventResult.handled;
    }
    if (!picked) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final to = key == LogicalKeyboardKey.arrowUp
          ? pickedIndex - 1
          : pickedIndex + 1;
      if (to >= 0 && to < _ordered.length) {
        final movedKey = _ordered[pickedIndex].key;
        _moveRow(pickedIndex, to);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final node = _rowNodes[movedKey];
          if (node != null && mounted) {
            node.requestFocus();
            final ctx = node.context;
            if (ctx != null) tvRevealMinimal(ctx);
          }
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _pickedKey = null);
      return KeyEventResult.handled;
    }
    // A picked row owns the DPAD entirely: RIGHT must not let traversal
    // wander off with the pick still latched.
    if (key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  FocusNode _nodeFor(String key) => _rowNodes.putIfAbsent(
    key,
    () => FocusNode(debugLabel: 'quick-play-priority-$key'),
  );

  // ---------------------------------------------------------------------
  // Failover chain

  FailoverChainPolicy get _chain => _rules.failoverChain;

  void _setChain(FailoverChainPolicy Function(FailoverChainPolicy) change) =>
      _change((r) => r.copyWith(failoverChain: change(r.failoverChain)));

  static String _providerName(String id) =>
      CloudProviderId.fromPlaybackId(id)?.displayName ?? id;

  FocusNode _chainNodeFor(String id) => _chainRowNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'quick-play-chain-provider-$id'),
  );

  FocusNode _neverProbeNodeFor(String id) => _chainNeverProbeNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'quick-play-chain-never-probe-$id'),
  );

  void _moveChainRow(int from, int to) {
    final list = List<String>.from(_chain.providerOrder);
    if (from == to || from < 0 || to < 0) return;
    if (from >= list.length || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    _setChain((c) => c.copyWith(providerOrder: list));
  }

  /// Same pick-up/drop grammar as [_rowKey], over the chain's provider list.
  KeyEventResult _chainRowKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final order = _chain.providerOrder;
    final pickedIndex = _chainPicked == null
        ? -1
        : order.indexOf(_chainPicked!);
    final picked = pickedIndex >= 0;

    if (isActivateOrSpaceKey(key)) {
      setState(
        () => _chainPicked = _chainPicked == order[index] ? null : order[index],
      );
      return KeyEventResult.handled;
    }
    if (!picked) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final to = key == LogicalKeyboardKey.arrowUp
          ? pickedIndex - 1
          : pickedIndex + 1;
      if (to >= 0 && to < order.length) {
        final movedId = order[pickedIndex];
        _moveChainRow(pickedIndex, to);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final node = _chainRowNodes[movedId];
          if (node != null && mounted) {
            node.requestFocus();
            final ctx = node.context;
            if (ctx != null) tvRevealMinimal(ctx);
          }
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _chainPicked = null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  void _restore() async {
    await QuickPlayPolicyPrefs.restoreQuickPlayDefaults();
    if (!mounted) return;
    setState(() {
      _movie = QuickPlayRules.debrifyDefault(isMovie: true);
      _show = QuickPlayRules.debrifyDefault(isMovie: false);
      _orderedMovie = _applyStoredOrder(const []);
      _orderedSeries = _applyStoredOrder(const []);
      // restoreQuickPlayDefaults() clears the stored mode; mirror it here or the
      // dropdown keeps showing the old value until the page is reopened.
      _playMode = 'quick';
      _pickedKey = null;
      _chainPicked = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restored default Quick Play behavior')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Quick Play',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Quick Play',
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          PlatformUtil.isTelevision ? 36 : 16,
          18,
          PlatformUtil.isTelevision ? 36 : 16,
          64,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.bolt_rounded,
                  title: 'Quick Play',
                  subtitle:
                      'Choose what Debrify plays automatically. Movies and series have separate rules.',
                ),
                const SizedBox(height: 22),
                _heading(
                  'Play button opens',
                  'Applies to movies and series. The Play button itself never '
                      'changes — only what happens when you press it.',
                ),
                const SizedBox(height: 10),
                _playModeSelect(),
                const SizedBox(height: 24),
                _tabs(),
                const SizedBox(height: 20),
                _switches(),
                if (_pikPak && _series) ...[
                  const SizedBox(height: 12),
                  const SettingsInfoBanner(
                    text:
                        'PikPak skips season packs because each pack probe creates a real offline download on your account.',
                  ),
                ],
                const SizedBox(height: 24),
                _heading(
                  'Streams to try',
                  'When a stream fails to start, Debrify moves down the list '
                      'and tries the next one. This is the count the player '
                      'shows while it works ("Checking stream 1 of '
                      '$_effectiveAttempts…").',
                ),
                const SizedBox(height: 10),
                _attemptsSelect(),
                const SizedBox(height: 24),
                _heading(
                  'Addon priority',
                  PlatformUtil.isTelevision
                      ? 'Results from the top of this list play first. Press OK to pick up a row, move it with ▲▼, press OK to drop.'
                      : PlatformUtil.isPhone
                      ? 'Results from the top of this list play first. Drag or use the arrows to reorder.'
                      : 'Results from the top of this list play first. Click the arrows, or press Enter on a row and move it with ↑↓.',
                ),
                const SizedBox(height: 10),
                _priorityList(),
                const SizedBox(height: 24),
                _heading(
                  'Failover chain',
                  'Off, Debrify falls back down the source list in order. On, '
                      'it follows a chain: the stream you picked, then streams '
                      'from the same debrid service at the nearest resolution, '
                      'then later services in your order. "Streams to try" '
                      'still caps the total.',
                ),
                const SizedBox(height: 10),
                _chainToggleTile(),
                if (_chain.enabled) ..._chainKnobs(),
                const SizedBox(height: 18),
                _ActionRow(
                  node: _reset,
                  icon: Icons.restore_rounded,
                  title: 'Restore defaults',
                  subtitle:
                      'Reset Movie and Series rules, switches, and priority order',
                  expanded: false,
                  onTap: _restore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, String subtitle) {
    final dim = AppThemeScope.of(context).settings.dim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: dim)),
      ],
    );
  }

  /// The only setting on this page that is NOT per-content, so it lives above
  /// the Movies/Series tabs rather than inside them.
  ///
  /// Copy carries unusual weight here: the Play button looks identical in all
  /// three modes, so this is the one place the difference is ever explained.
  Widget _playModeSelect() => _Panel(
    child: SettingsSelectDropdown(
      focusNode: _playModeNode,
      value: _playMode,
      options: const [
        SettingsSelectOption(
          'quick',
          'Quick Play',
          'Debrify picks the source and starts playing.',
        ),
        SettingsSelectOption(
          'smart',
          'Smart',
          'Uses a pinned source when there is one. Otherwise it shows the '
              'source list instead of choosing for you.',
        ),
        SettingsSelectOption(
          'always',
          'Always show sources',
          'Skips pinned sources and always shows the list, so you pick every '
              'time.',
        ),
      ],
      onChanged: _setPlayMode,
    ),
  );

  Future<void> _setPlayMode(String value) async {
    setState(() => _playMode = value);
    await QuickPlayPolicyPrefs.setPlayButtonMode(value);
  }

  Widget _tabs() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 430),
    child: _Panel(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _FocusButton(
              key: const ValueKey('quick-play-tab-movie'),
              node: _movieTab,
              selected: !_series,
              label: 'Movies',
              onTap: () => setState(() {
                _series = false;
                _pickedKey = null;
              }),
            ),
          ),
          Expanded(
            child: _FocusButton(
              key: const ValueKey('quick-play-tab-series'),
              node: _seriesTab,
              selected: _series,
              label: 'Series',
              onTap: () => setState(() {
                _series = true;
                _pickedKey = null;
              }),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _switches() => _Panel(
    child: Column(
      children: [
        SettingsToggleTile(
          focusNode: _torrentToggle,
          icon: Icons.download_rounded,
          title: 'Prefer torrents',
          subtitle: _preferTorrents
              ? 'Try torrents in Addon Priority order; direct links are the fallback.'
              : 'Follow Addon Priority and each provider’s returned stream order.',
          subtitleMaxLines: 2,
          value: _preferTorrents,
          onChanged: _setPreferTorrents,
        ),
        if (_series && !_pikPak) ...[
          Divider(height: 1, color: AppThemeScope.of(context).settings.line),
          SettingsToggleTile(
            focusNode: _packToggle,
            icon: Icons.inventory_2_rounded,
            title: 'Prefer season packs',
            subtitle: _rules.preferSeriesPacks
                ? 'Grab a whole season when available — later episodes start instantly.'
                : 'Fetch just the episode; packs are only used when nothing else is found.',
            subtitleMaxLines: 2,
            value: _rules.preferSeriesPacks,
            onChanged: _setPreferPacks,
          ),
        ],
      ],
    ),
  );

  /// 1–10 mirrors the clamp in [QuickPlayRules.copyWith] and the player's own
  /// `maxAttempts.clamp(1, 10)`, so every value offered here is a value both
  /// players can honor — including legacy prefs left by the old slider.
  Widget _attemptsSelect() => _Panel(
    child: SettingsSelectDropdown(
      focusNode: _attemptsNode,
      value: '$_effectiveAttempts',
      options: [
        for (var n = 1; n <= 10; n++)
          SettingsSelectOption(
            '$n',
            n == 1
                ? '1 stream'
                : n == 5
                ? '5 streams (default)'
                : '$n streams',
            switch (n) {
              1 =>
                'Play the first source only, without falling back. (One '
                    'exception: if a season pack was ranked first, the best '
                    'single episode still gets a try.)',
              5 =>
                'Debrify’s default — a good balance between starting fast '
                    'and finding a working stream.',
              _ when n < 5 =>
                'Gives up sooner. Fails fast when nothing is working.',
              _ =>
                'Digs deeper before giving up, so a bad run takes longer to '
                    'start.',
            },
          ),
      ],
      onChanged: (v) => _setMaxAttempts(int.tryParse(v) ?? 5),
    ),
  );

  Widget _chainToggleTile() => _Panel(
    child: SettingsToggleTile(
      focusNode: _chainToggle,
      icon: Icons.alt_route_rounded,
      title: 'Use failover chain',
      subtitle: _chain.enabled
          ? 'Same service first, nearest resolution first, then later services.'
          : 'Fall back down the source list in order (Debrify default).',
      subtitleMaxLines: 2,
      value: _chain.enabled,
      onChanged: (v) => _setChain((c) => c.copyWith(enabled: v)),
    ),
  );

  List<Widget> _chainKnobs() => [
    const SizedBox(height: 24),
    _heading(
      'Provider order',
      PlatformUtil.isTelevision
          ? 'After the service you picked, only services below it are tried. Press OK to pick up a row, move it with ▲▼, press OK to drop.'
          : 'After the service you picked, only services below it are tried. Use the arrows, or press Enter on a row and move it with ↑↓.',
    ),
    const SizedBox(height: 10),
    _chainOrderList(),
    const SizedBox(height: 24),
    _heading(
      'Same-service streams',
      'How many other streams from the same debrid service to try, '
          'nearest resolution first (same, then just below, then above).',
    ),
    const SizedBox(height: 10),
    _countSelect(
      node: _chainSiblings,
      value: _chain.maxSiblings,
      onChanged: (n) => _setChain((c) => c.copyWith(maxSiblings: n)),
    ),
    const SizedBox(height: 24),
    _heading(
      'Streams per later service',
      'How many streams to try from each later service, best resolution '
          'match first.',
    ),
    const SizedBox(height: 10),
    _countSelect(
      node: _chainLater,
      value: _chain.maxPerLaterProvider,
      onChanged: (n) => _setChain((c) => c.copyWith(maxPerLaterProvider: n)),
    ),
    const SizedBox(height: 24),
    _heading(
      'Resolution match',
      'How strictly fallbacks must match the resolution you picked.',
    ),
    const SizedBox(height: 10),
    _matchSelect(),
    const SizedBox(height: 24),
    _heading(
      'Liveness probe',
      'Before playing a fallback, ask the host for its first byte '
          '(Range: bytes=0-0). Dead links are skipped without waiting on the '
          'player. Services where a probe costs something are served blind.',
    ),
    const SizedBox(height: 10),
    _Panel(
      child: SettingsToggleTile(
        focusNode: _chainProbe,
        icon: Icons.network_check_rounded,
        title: 'Probe before playing',
        subtitle: _chain.probeEnabled
            ? 'One tiny request per candidate; one retry on timeout.'
            : 'Hand every candidate straight to the player.',
        subtitleMaxLines: 2,
        value: _chain.probeEnabled,
        onChanged: (v) => _setChain((c) => c.copyWith(probeEnabled: v)),
      ),
    ),
    if (_chain.probeEnabled) ...[
      const SizedBox(height: 10),
      _probeTimeoutSelect(),
      const SizedBox(height: 10),
      _neverProbePanel(),
    ],
    const SizedBox(height: 24),
    _heading(
      'Demote recently served links',
      'If you re-pick a title soon after a link failed to start, that link '
          'is tried last instead of first.',
    ),
    const SizedBox(height: 10),
    _demotionSelect(),
  ];

  Widget _chainOrderList() {
    final order = _chain.providerOrder;
    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < order.length; i++)
            _PriorityRow(
              key: ValueKey('quick-play-chain-provider-${order[i]}'),
              node: _chainNodeFor(order[i]),
              index: i,
              provider: SourceProviderRef(
                key: order[i],
                name: _providerName(order[i]),
                isEngine: false,
              ),
              tag: 'Debrid service',
              picked: _chainPicked == order[i],
              isFirst: i == 0,
              isLast: i == order.length - 1,
              showDivider: i < order.length - 1,
              onKey: (event) => _chainRowKey(i, event),
              onTap: () => setState(
                () => _chainPicked = _chainPicked == order[i] ? null : order[i],
              ),
              onMoveUp: i > 0 ? () => _moveChainRow(i, i - 1) : null,
              onMoveDown: i < order.length - 1
                  ? () => _moveChainRow(i, i + 1)
                  : null,
            ),
        ],
      ),
    );
  }

  /// 0–10 mirrors [FailoverChainPolicy.maxCap].
  Widget _countSelect({
    required FocusNode node,
    required int value,
    required ValueChanged<int> onChanged,
  }) => _Panel(
    child: SettingsSelectDropdown(
      focusNode: node,
      value: '$value',
      options: [
        for (var n = 0; n <= FailoverChainPolicy.maxCap; n++)
          SettingsSelectOption(
            '$n',
            n == 0
                ? 'None'
                : n == 1
                ? '1 stream'
                : n == 3
                ? '3 streams (default)'
                : '$n streams',
          ),
      ],
      onChanged: (v) => onChanged(int.tryParse(v) ?? 3),
    ),
  );

  Widget _matchSelect() => _Panel(
    child: SettingsSelectDropdown(
      focusNode: _chainMatch,
      value: _chain.resolutionMatch.name,
      options: const [
        SettingsSelectOption(
          'nearestBelowFirst',
          'Nearest resolution (default)',
          'Same resolution first, then the next one down, then up.',
        ),
        SettingsSelectOption(
          'exactOnly',
          'Same resolution only',
          'Skip anything that is not the resolution you picked.',
        ),
        SettingsSelectOption(
          'ignore',
          'Ignore resolution',
          'Keep each service’s own stream order.',
        ),
      ],
      onChanged: (v) => _setChain(
        (c) => c.copyWith(
          resolutionMatch: FailoverResolutionMatch.values.firstWhere(
            (m) => m.name == v,
            orElse: () => FailoverResolutionMatch.nearestBelowFirst,
          ),
        ),
      ),
    ),
  );

  Widget _probeTimeoutSelect() {
    final steps = {
      1,
      2,
      3,
      5,
      8,
      10,
      15,
      20,
      30,
      _chain.probeTimeoutSeconds,
    }.toList()..sort();
    return _Panel(
      child: SettingsSelectDropdown(
        focusNode: _chainProbeTimeout,
        value: '${_chain.probeTimeoutSeconds}',
        options: [
          for (final s in steps)
            SettingsSelectOption(
              '$s',
              s == 5
                  ? 'Probe timeout: 5 seconds (default)'
                  : 'Probe timeout: $s ${s == 1 ? 'second' : 'seconds'}',
              s <= 2
                  ? 'Fast, but slow-to-wake hosts read as dead.'
                  : s >= 15
                  ? 'Patient; a dead host can hold up the chain this long.'
                  : null,
            ),
        ],
        onChanged: (v) => _setChain(
          (c) => c.copyWith(probeTimeoutSeconds: int.tryParse(v) ?? 5),
        ),
      ),
    );
  }

  Widget _neverProbePanel() {
    final t = AppThemeScope.of(context).settings;
    final ids = FailoverChainPolicy.defaultProviderOrder;
    return _Panel(
      child: Column(
        children: [
          for (var i = 0; i < ids.length; i++) ...[
            if (i > 0) Divider(height: 1, color: t.line),
            SettingsToggleTile(
              focusNode: _neverProbeNodeFor(ids[i]),
              icon: Icons.do_not_disturb_on_rounded,
              title: 'Never probe ${_providerName(ids[i])}',
              subtitle: switch (ids[i]) {
                'premiumize' => 'Each probe mints a new link on your account.',
                'pikpak' => 'Each probe can queue a real download.',
                _ => 'Serve this service’s links blind.',
              },
              subtitleMaxLines: 2,
              value: _chain.neverProbeProviders.contains(ids[i]),
              onChanged: (v) => _setChain(
                (c) => c.copyWith(
                  neverProbeProviders: v
                      ? {...c.neverProbeProviders, ids[i]}
                      : ({...c.neverProbeProviders}..remove(ids[i])),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _demotionSelect() {
    final steps = {
      0,
      2,
      5,
      10,
      15,
      30,
      60,
      120,
      _chain.demotionWindowMinutes,
    }.toList()..sort();
    return _Panel(
      child: SettingsSelectDropdown(
        focusNode: _chainDemotion,
        value: '${_chain.demotionWindowMinutes}',
        options: [
          for (final m in steps)
            SettingsSelectOption(
              '$m',
              m == 0
                  ? 'Off'
                  : m == 10
                  ? '10 minutes (default)'
                  : m >= 60
                  ? '${m ~/ 60} ${m == 60 ? 'hour' : 'hours'}'
                  : '$m minutes',
              m == 0
                  ? 'Always start from the stream you picked.'
                  : 'Links that failed within this window go to the end of the chain.',
            ),
        ],
        onChanged: (v) => _setChain(
          (c) => c.copyWith(demotionWindowMinutes: int.tryParse(v) ?? 10),
        ),
      ),
    );
  }

  Widget _priorityList() {
    final t = AppThemeScope.of(context).settings;
    if (_ordered.isEmpty) {
      return _Panel(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No torrent engines or streaming addons installed yet — add some from the Addons hub and they will appear here.',
          style: TextStyle(color: t.dim),
        ),
      );
    }
    // TV AND desktop: a plain Column. A nested scrollable — even shrinkwrapped
    // and NeverScrollable — hides its children from DIRECTIONAL focus
    // traversal, so arrow keys / DPAD DOWN skipped this whole list and landed
    // on "Restore defaults". TV never drag-reorders; desktop keeps the ▲▼
    // buttons for the mouse and gains the rows' pick-up/drop grammar for the
    // keyboard (Enter to grab, ↑↓ to move, Enter to drop). Only PHONES keep
    // the ReorderableListView, where touch drag matters and keyboards don't.
    if (!PlatformUtil.isPhone) {
      return _Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < _ordered.length; i++) _rowAt(i)],
        ),
      );
    }
    return _Panel(
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _ordered.length,
        onReorderItem: _moveRow,
        itemBuilder: (context, i) => _rowAt(i),
      ),
    );
  }

  Widget _rowAt(int i) {
    final p = _ordered[i];
    return _PriorityRow(
      key: ValueKey('quick-play-priority-${p.key}'),
      node: _nodeFor(p.key),
      index: i,
      provider: p,
      picked: _pickedKey == p.key,
      isFirst: i == 0,
      isLast: i == _ordered.length - 1,
      showDivider: i < _ordered.length - 1,
      onKey: (event) => _rowKey(i, event),
      onTap: () =>
          setState(() => _pickedKey = _pickedKey == p.key ? null : p.key),
      onMoveUp: i > 0 ? () => _moveRow(i, i - 1) : null,
      onMoveDown: i < _ordered.length - 1 ? () => _moveRow(i, i + 1) : null,
    );
  }
}

/// One row of the Addon Priority list: rank, name, a quiet type tag, ▲▼
/// buttons, and (on touch) a drag handle. On TV the row is a Focus target
/// implementing the pick-up/drop reorder grammar.
class _PriorityRow extends StatefulWidget {
  final FocusNode node;
  final int index;
  final SourceProviderRef provider;
  final bool picked;
  final bool isFirst;
  final bool isLast;
  final bool showDivider;
  final KeyEventResult Function(KeyEvent) onKey;
  final VoidCallback onTap;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Quiet type tag under the name; defaults to engine/addon.
  final String? tag;

  const _PriorityRow({
    super.key,
    required this.node,
    required this.index,
    required this.provider,
    required this.picked,
    required this.isFirst,
    required this.isLast,
    required this.showDivider,
    required this.onKey,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    this.tag,
  });

  @override
  State<_PriorityRow> createState() => _PriorityRowState();
}

class _PriorityRowState extends State<_PriorityRow> {
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it missed.
  bool get focused => widget.node.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final accent = widget.picked || focused;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          focusNode: widget.node,
          onFocusChange: (hasFocus) {
            // Gain only — the loss half of a loss→gain pair would reveal the
            // row being LEFT and fight the new row's own reveal.
            if (hasFocus && PlatformUtil.isTelevision) {
              tvRevealMinimal(context);
            }
            setState(() {});
          },
          onKeyEvent: (node, event) => widget.onKey(event),
          // The outer Focus node is the row's ONE focus stop; the InkWell
          // taking its own focus would make every row two DPAD presses.
          child: InkWell(
            canRequestFocus: false,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.picked
                    ? t.panel2
                    : focused
                    ? t.panel2.withValues(alpha: 0.6)
                    : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: accent ? t.accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${widget.index + 1}',
                      style: TextStyle(
                        color: accent ? t.accent2 : t.dim,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.provider.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.tag ??
                              (widget.provider.isEngine
                                  ? 'Torrent engine'
                                  : 'Addon'),
                          style: TextStyle(color: t.dim, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (widget.picked)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Moving…',
                        style: TextStyle(
                          color: t.accent2,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  // Touch/desktop only: on TV these would be two extra DPAD
                  // stops per row that fight the pick-up/drop grammar (the
                  // row itself is the only focus target there). ExcludeFocus
                  // keeps that grammar true for desktop keyboards too — the
                  // buttons are pointer affordances; the keyboard reorders via
                  // the row itself (Enter to grab, ↑↓, Enter to drop).
                  if (!PlatformUtil.isTelevision)
                    ExcludeFocus(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: widget.onMoveUp,
                            tooltip: 'Move up',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: widget.onMoveUp == null ? t.line : t.dim,
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onMoveDown,
                            tooltip: 'Move down',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: widget.onMoveDown == null ? t.line : t.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Phone only — the drag listener needs the
                  // ReorderableListView ancestor, which desktop no longer has.
                  if (PlatformUtil.isPhone)
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.drag_indicator_rounded, color: t.dim),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.showDivider) Divider(height: 1, color: t.line),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _Panel({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: app.shape.br(16),
        border: Border.all(color: t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _FocusButton extends StatefulWidget {
  final FocusNode node;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FocusButton({
    super.key,
    required this.node,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_FocusButton> createState() => _FocusButtonState();
}

class _FocusButtonState extends State<_FocusButton> {
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `widgets/settings_widgets.dart`.
  bool get focused => widget.node.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return InkWell(
      focusNode: widget.node,
      onFocusChange: (_) => setState(() {}),
      onTap: widget.onTap,
      borderRadius: app.shape.br(10),
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: widget.selected ? t.panel2 : Colors.transparent,
          borderRadius: app.shape.br(10),
          border: Border.all(
            color: focused ? t.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  final FocusNode node;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool expanded;

  const _ActionRow({
    required this.node,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.expanded,
  });

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `widgets/settings_widgets.dart`.
  bool get focused => widget.node.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return InkWell(
      focusNode: widget.node,
      onFocusChange: (_) => setState(() {}),
      onTap: widget.onTap,
      borderRadius: app.shape.br(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: focused ? t.panel2 : t.panel,
          borderRadius: app.shape.br(14),
          border: Border.all(color: focused ? t.accent : t.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Icon(widget.icon, color: focused ? t.accent2 : t.dim),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle,
                    style: TextStyle(color: t.dim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: widget.expanded ? .25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.chevron_right_rounded, color: t.dim),
            ),
          ],
        ),
      ),
    );
  }
}
