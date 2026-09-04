import 'package:flutter/material.dart';
import '../../utils/tv_reveal.dart';
import 'package:flutter/services.dart';

import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../utils/platform_util.dart';
import '../../theme/app_focus.dart';
import '../../theme/widgets/parallax_focus.dart';
import 'settings_spotlight_shell.dart';
import 'settings_catalog.dart';
import 'settings_page_registry.dart';
import 'settings_page_spec.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// TV-only two-pane Settings shell (the "Mock 1" layout): a category rail on
/// the left, the selected category's rows on the right.
///
/// DPAD model — deliberately hand-wired (like the old connection grid) rather
/// than relying on Flutter's directional traversal, so behaviour is
/// deterministic on real TV hardware:
///   • Rail: Up/Down move between categories (and the pane updates live, so
///     you preview a category by focusing it). Right / OK enter the pane.
///     Left from the rail hands off to the app sidebar.
///   • Pane: Up/Down move between rows (auto-scrolling into view via the
///     default traversal's ensure-visible). Left returns to the *selected*
///     rail item (never a different category).
///
/// Only the TV layout is built here; phone/desktop keep the single-column
/// `_SettingsLayout`. All actions/dialogs still live in the parent State —
/// this is presentation + focus only.
class SettingsTvLayout extends StatefulWidget {
  final List<ConnectionInfo> connections;

  /// Cross-service watch-history policy, visually separated from the account
  /// connections below it in the Trackers category.
  final ConnectionInfo tracking;

  /// Watch-history services (Trakt, Simkl, MDBList) in their own section.
  final List<ConnectionInfo> trackers;

  /// Focus target the sidebar hand-off and post-logout restores aim at —
  /// attached to the first rail item.
  final FocusNode? firstFocusNode;

  /// Opens the full-screen settings search (the rail's search item / OK / Right).
  final VoidCallback onOpenSearch;

  final bool showSwitchProfile;
  final bool showSupportDonation;

  /// Bound settings pages from [SettingsPageRegistry]. Empty falls back
  /// to the production catalog (existing layout tests only exercise the
  /// Connections pane, which is still a special-case card grid).
  final List<SettingsPageSpec> pages;

  const SettingsTvLayout({
    super.key,
    required this.connections,
    required this.tracking,
    required this.trackers,
    required this.firstFocusNode,
    required this.onOpenSearch,
    this.showSwitchProfile = false,
    this.showSupportDonation = false,
    this.pages = const [],
  });

  @override
  State<SettingsTvLayout> createState() => _SettingsTvLayoutState();
}

class _Category {
  final IconData icon;
  final String label;

  /// One-line hint of what the category holds, shown under [label] in the
  /// rail so a glance down the list previews each section's contents.
  final String subtitle;
  final String title;
  final String description;
  const _Category(
    this.icon,
    this.label,
    this.subtitle,
    this.title,
    this.description,
  );
}

// Rail copy lives on kSettingsCategories (settings_page_registry.dart) —
// one list shared with the phone/desktop shells and the search index.
class _SettingsTvLayoutState extends State<SettingsTvLayout> {
  /// Max focusable rows in any single FIXED category. Kept as a floor;
  /// the pane pool also covers [SettingsPageRegistry.tvMaxFocusableRows]
  /// so a newly registered page cannot land past the pool.
  static const int _kMaxCategoryRows = 19;

  List<_Category> get _rail => [
    for (final c in kSettingsCategories)
      _Category(c.icon, c.label, c.tvSubtitle, c.tvTitle, c.tvDescription),
  ];

  SettingsPageRegistry get _pageRegistry => SettingsPageRegistry(
    pages: widget.pages.isNotEmpty
        ? widget.pages
        : buildSettingsPages(
            SettingsPageBindings.noop(
              isAndroidTv: PlatformUtil.isAndroidTvCached,
              isTelevision: true,
              showSwitchProfile: widget.showSwitchProfile,
              downloadLocationSupported: true,
              diagnosticExportVisible: true,
              showSupportDonation: widget.showSupportDonation,
            ),
          ),
  );

  /// Selected category. A [ValueNotifier] (not setState) so a rail focus-move
  /// only rebuilds the pane and the two affected rail items via their
  /// [ValueListenableBuilder]s — not the whole two-pane tree (which, on
  /// Connections, means re-laying-out every provider card per DPAD step on
  /// weak TVs).
  final ValueNotifier<int> _selected = ValueNotifier<int>(0);

  /// One node per category rail item — all owned here. The parent's
  /// [SettingsTvLayout.firstFocusNode] is NOT aliased to a rail item; it's a
  /// dedicated entry proxy (below) that redirects to the *currently selected*
  /// category, so bouncing out to the sidebar and back doesn't reset the pane.
  late final List<FocusNode> _railNodes;

  /// The search item sits above the category rail — its own node so Up from the
  /// first category lands here and Down from here returns to the categories.
  final FocusNode _searchNode = FocusNode(
    debugLabel: 'settings-tv-rail-search',
  );

  /// Pool of focus nodes for the pane rows, indexed top-to-bottom. Reused
  /// across categories (only one pane is shown at a time). A node whose
  /// `context` is null isn't attached to a row in the current category, which
  /// is how the DPAD wiring clamps at the pane's first/last visible row
  /// without tracking per-category row counts.
  late final List<FocusNode> _paneNodes;

  final ScrollController _paneScroll = ScrollController();

  /// The rail is scrollable so the taller two-line items + search entry can't
  /// overflow a short TV surface (e.g. 540-logical-px panels); focused items
  /// are revealed into view like the pane's rows.
  final ScrollController _railScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _railNodes = List.generate(
      _rail.length,
      (i) => FocusNode(debugLabel: 'settings-tv-rail-$i'),
    );
    // The pool must cover whichever category has the most rows. Connections
    // and Trackers each have one node per card; the fixed categories have
    // at most [_kMaxCategoryRows]. Computed over all three rather than
    // assuming Connections is always the biggest — it no longer holds every
    // provider.
    var poolSize = _kMaxCategoryRows;
    final catalogMax = _pageRegistry.tvMaxFocusableRows;
    if (catalogMax > poolSize) poolSize = catalogMax;
    for (final n in [widget.connections.length, widget.trackers.length + 1]) {
      if (n > poolSize) poolSize = n;
    }
    _paneNodes = List.generate(
      poolSize,
      (i) => FocusNode(debugLabel: 'settings-tv-pane-$i'),
    );
    widget.firstFocusNode?.addListener(_onEntryFocus);
  }

  @override
  void didUpdateWidget(SettingsTvLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstFocusNode != widget.firstFocusNode) {
      oldWidget.firstFocusNode?.removeListener(_onEntryFocus);
      widget.firstFocusNode?.addListener(_onEntryFocus);
    }
  }

  @override
  void dispose() {
    widget.firstFocusNode?.removeListener(_onEntryFocus);
    for (final n in _railNodes) {
      n.dispose();
    }
    for (final n in _paneNodes) {
      n.dispose();
    }
    _searchNode.dispose();
    _selected.dispose();
    _paneScroll.dispose();
    _railScroll.dispose();
    super.dispose();
  }

  /// The sidebar hand-off and logout restores focus [firstFocusNode]; redirect
  /// that onto the rail item for whatever category is currently showing.
  void _onEntryFocus() {
    if (!mounted) return;
    if (widget.firstFocusNode?.hasFocus ?? false) {
      _railNodes[_selected.value].requestFocus();
    }
  }

  void _select(int i) {
    if (i == _selected.value) return;
    _selected.value = i;
    // Reset scroll to top synchronously *before* the pane rebuilds. The
    // SingleChildScrollView (and its position) is reused across the
    // ValueListenableBuilder rebuild — only the inner keyed Column swaps — so
    // setting the offset now means the new category's pane paints at the top
    // on its first frame (a post-frame jumpTo would flash one stale-offset
    // frame first).
    if (_paneScroll.hasClients) _paneScroll.jumpTo(0);
  }

  // Enter the pane on the first row — via _focusPaneRow so it scrolls into
  // view. Without the scroll, re-entering a category whose pane was left
  // scrolled down would focus the (off-screen) top row with no visible
  // highlight.
  void _enterPane() {
    _focusPaneRow(0, travel: const Offset(1, 0));
  }

  void _focusPaneRow(int i, {Offset travel = Offset.zero}) {
    if (travel != Offset.zero) ParallaxTravel.note(travel);
    final node = _paneNodes[i];
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = node.context;
      if (ctx != null && ctx.mounted) {
        tvRevealMinimal(ctx);
      }
    });
  }

  KeyEventResult _railKey(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      ParallaxTravel.note(const Offset(0, -1));
      // Above the first category sits the search item.
      if (index > 0) {
        _railNodes[index - 1].requestFocus();
      } else {
        _searchNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _railNodes.length - 1) {
        ParallaxTravel.note(const Offset(0, 1));
        _railNodes[index + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _enterPane();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Always consume Left so focus never escapes the rail via directional
      // traversal, even if the sidebar hand-off isn't registered.
      ParallaxTravel.note(const Offset(-1, 0));
      MainPageBridge.focusTvSidebar?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// DPAD for the rail's search item: Down enters the category list, Right/OK
  /// opens search, Left hands off to the sidebar, Up is trapped (topmost).
  KeyEventResult _searchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      ParallaxTravel.note(const Offset(0, 1));
      _railNodes[0].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onOpenSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      ParallaxTravel.note(const Offset(-1, 0));
      MainPageBridge.focusTvSidebar?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _paneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_selected.value == 1) return _trackerPaneKey(event);
    final key = event.logicalKey;
    final i = _paneNodes.indexWhere((n) => n.hasFocus);
    final grid =
        _selected.value == 0 && MediaQuery.sizeOf(context).width >= 880;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (grid && i > 0 && i.isOdd && _isPaneRowLive(i - 1)) {
        _focusPaneRow(i - 1, travel: const Offset(-1, 0));
        return KeyEventResult.handled;
      }
      // Return to the category we're viewing, not whichever rail item happens
      // to sit to the left geometrically.
      ParallaxTravel.note(const Offset(-1, 0));
      _railNodes[_selected.value].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (grid && i >= 0 && i.isEven && _isPaneRowLive(i + 1)) {
        _focusPaneRow(i + 1, travel: const Offset(1, 0));
      }
      // Nothing to the right of the pane — trap so focus can't escape.
      return KeyEventResult.handled;
    }
    // Hand-wire Up/Down between the pane's visible rows, trapping at the ends
    // so directional traversal can never bounce focus back onto the rail.
    // A pooled node is "in the current category" only if its context is
    // mounted — the pool is reused across categories and a FocusNode's context
    // is NOT nulled on unmount, so `context != null` would be a stale true for
    // a node last attached by a larger, previously-visited category.
    final step = grid ? 2 : 1;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (i - step >= 0 && _isPaneRowLive(i - step)) {
        _focusPaneRow(i - step, travel: const Offset(0, -1));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (i >= 0 && i + step < _paneNodes.length && _isPaneRowLive(i + step)) {
        _focusPaneRow(i + step, travel: const Offset(0, 1));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Tracking is a full-width policy card above a separate two-column account
  /// grid, so the generic even/odd grid walker cannot describe its geometry.
  KeyEventResult _trackerPaneKey(KeyEvent event) {
    final key = event.logicalKey;
    final i = _paneNodes.indexWhere((n) => n.hasFocus);
    if (i < 0) return KeyEventResult.ignored;
    final count = widget.trackers.length + 1;
    final twoColumns = MediaQuery.sizeOf(context).width >= 880;

    if (key == LogicalKeyboardKey.arrowLeft) {
      // Provider cards use indices 1...: even indices are the right column.
      if (twoColumns && i >= 2 && i.isEven && _isPaneRowLive(i - 1)) {
        _focusPaneRow(i - 1, travel: const Offset(-1, 0));
      } else {
        ParallaxTravel.note(const Offset(-1, 0));
        _railNodes[_selected.value].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (twoColumns &&
          i >= 1 &&
          i.isOdd &&
          i + 1 < count &&
          _isPaneRowLive(i + 1)) {
        _focusPaneRow(i + 1, travel: const Offset(1, 0));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final target = !twoColumns
          ? i - 1
          : i <= 2
          ? 0
          : i - 2;
      if (target >= 0 && target != i && _isPaneRowLive(target)) {
        _focusPaneRow(target, travel: const Offset(0, -1));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final target = !twoColumns
          ? i + 1
          : i == 0
          ? 1
          : i + 2;
      if (target < count && _isPaneRowLive(target)) {
        _focusPaneRow(target, travel: const Offset(0, 1));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether pane node [i] is attached to a row mounted in the current pane.
  bool _isPaneRowLive(int i) => _paneNodes[i].context?.mounted ?? false;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return SettingsBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final railWidth = (constraints.maxWidth * 0.33).clamp(236.0, 320.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Invisible entry proxy: the parent State focuses
                // [firstFocusNode] on sidebar hand-off / logout restore;
                // [_onEntryFocus] redirects to the selected rail item.
                if (widget.firstFocusNode != null)
                  Focus(
                    focusNode: widget.firstFocusNode,
                    skipTraversal: true,
                    descendantsAreFocusable: false,
                    child: const SizedBox.shrink(),
                  ),
                _buildRail(railWidth),
                Container(width: 1, color: t.line),
                // Only the pane rebuilds when the category changes.
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _selected,
                          builder: (context, selected, _) =>
                              _buildPane(selected),
                        ),
                      ),
                      _buildFooter(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    Widget hint(String key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: app.shape.br(5),
            border: Border.all(color: t.line),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 8,
              color: t.dim,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(fontSize: 9, color: t.dim2)),
      ],
    );
    return Container(
      height: 46,
      margin: const EdgeInsets.only(right: 36),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showSaved = constraints.maxWidth >= 650;
          return Row(
            children: [
              const SizedBox(width: 32),
              hint('←', 'categories'),
              const SizedBox(width: 17),
              hint('↑ ↓', 'move'),
              const SizedBox(width: 17),
              hint('OK', 'open'),
              if (showSaved) ...[
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.success,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Changes save automatically',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 8,
                    color: t.success.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRail(double width) {
    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        controller: _railScroll,
        padding: const EdgeInsets.fromLTRB(24, 28, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, right: 8, bottom: 20),
              child: SettingsRootHeader(compact: true),
            ),
            _RailSearchItem(
              focusNode: _searchNode,
              onKey: _searchKey,
              onActivate: widget.onOpenSearch,
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _rail.length; i++)
              _RailItem(
                index: i,
                category: _rail[i],
                focusNode: _railNodes[i],
                selected: _selected,
                onKey: _railKey,
                onActivate: _enterPane,
                onFocused: _select,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPane(int selected) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _paneKey,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SingleChildScrollView(
          controller: _paneScroll,
          padding: const EdgeInsets.fromLTRB(32, 30, 40, 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              key: ValueKey<int>(selected),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _rail[selected].label.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: _rail[selected].label == 'Danger Zone'
                              ? AppThemeScope.of(context).settings.danger
                              : AppThemeScope.of(
                                  context,
                                ).settings.accent.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _rail[selected].title,
                        style: const TextStyle(
                          fontSize: 28,
                          height: 1.06,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          _rail[selected].description,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: AppThemeScope.of(context).settings.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ..._buildPaneChildren(selected),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPaneChildren(int category) {
    switch (category) {
      case 0: // Connections
        return [_buildConnectionGrid(widget.connections)];
      case 1: // Trackers
        return [_buildTrackerGroups()];
      default:
        if (category < 0 || category >= kSettingsCategories.length) {
          return const [];
        }
        // Nodes stay CONTIGUOUS from 0 — the DPAD walker only advances to
        // the immediately adjacent live node, so a gap strands Down.
        // buildSettingsCategoryChildren claims [_paneNodes] sequentially
        // (headers and info tiles take no node).
        final label = kSettingsCategories[category].label;
        final t = AppThemeScope.of(context).settings;
        final built = buildSettingsCategoryChildren(
          registry: _pageRegistry,
          surface: SettingsLayoutSurface.tv,
          category: label,
          paneNodes: _paneNodes,
          accentColor: label == 'Danger Zone' ? t.danger : null,
        );
        if (built.isEmpty && label == 'Profiles') {
          return [
            SettingsSection(
              title: '',
              children: [
                SettingsTile.spec(
                  SettingsRowContent(
                    icon: Icons.info_outline_rounded,
                    title: 'Profiles unavailable',
                    subtitle: ProfileBootstrap.legacyReasonSummary
                        .split('\n')
                        .first,
                  ),
                  onTap: () => showLegacyModeInfoDialog(context),
                  focusNode: _paneNodes[0],
                ),
              ],
            ),
          ];
        }
        return built;
    }
  }

  Widget _buildConnectionGrid(List<ConnectionInfo> connections) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = MediaQuery.sizeOf(context).width >= 880;
        final width = twoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < connections.length; i++)
              SizedBox(
                width: width,
                child: ConnectionCard(
                  info: connections[i],
                  focusNode: _paneNodes[i],
                  isLeftColumn: false,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTrackerGroups() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = MediaQuery.sizeOf(context).width >= 880;
        final width = twoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionLabel('Tracking'),
            SizedBox(
              width: constraints.maxWidth,
              child: ConnectionCard(
                info: widget.tracking,
                focusNode: _paneNodes[0],
                isLeftColumn: false,
              ),
            ),
            const SizedBox(height: 22),
            const SettingsSectionLabel('Tracker services'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < widget.trackers.length; i++)
                  SizedBox(
                    width: width,
                    child: ConnectionCard(
                      info: widget.trackers[i],
                      focusNode: _paneNodes[i + 1],
                      isLeftColumn: false,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A single category rail item. Self-contained so a focus move only rebuilds
/// the two affected items (local `_focused`) and their selection tint (via the
/// shared [selected] notifier) — never the whole two-pane tree.
class _RailItem extends StatefulWidget {
  final int index;
  final _Category category;
  final FocusNode focusNode;
  final ValueNotifier<int> selected;
  final KeyEventResult Function(FocusNode, KeyEvent, int) onKey;
  final VoidCallback onActivate;
  final ValueChanged<int> onFocused;

  const _RailItem({
    required this.index,
    required this.category,
    required this.focusNode,
    required this.selected,
    required this.onKey,
    required this.onActivate,
    required this.onFocused,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  /// Live, never cached — a remembered flag survives the focus change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => widget.focusNode.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final inverse =
        _focused && app.focus.expression == FocusExpression.parallax;
    final focusInk = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(11);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ParallaxFocus(
        focused: _focused,
        shape: ParallaxShape.settingsRow,
        radius: radius,
        child: Focus(
          // Key handler only — the InkWell below owns the focusable node, so
          // this wrapper must not be a focus target itself.
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) => widget.onKey(node, event, widget.index),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              focusNode: widget.focusNode,
              borderRadius: radius,
              onTap: widget.onActivate,
              onFocusChange: (f) {
                setState(() {});
                if (f) {
                  widget.onFocused(widget.index);
                  // Scroll the focused item into view — the rail scrolls now.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && context.mounted) tvRevealMinimal(context);
                  });
                }
              },
              child: ValueListenableBuilder<int>(
                valueListenable: widget.selected,
                builder: (context, sel, _) {
                  final bool selected = sel == widget.index;
                  final bool focused = _focused;
                  final Color fg = inverse
                      ? focusInk
                      : (focused || selected)
                      ? app.core.tx
                      : t.dim;
                  final Color iconColor = inverse
                      ? focusInk
                      : (focused || selected)
                      ? t.accent2
                      : t.dim;
                  // Subtitle brightens with the row but stays a step dimmer than
                  // the title so the label still reads as primary.
                  final Color subColor = inverse
                      ? focusInk.withValues(alpha: 0.52)
                      : (focused || selected)
                      ? app.fade(app.core.tx, 0.60)
                      : t.dim2;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: inverse
                          ? app.core.tx
                          : selected
                          ? app.fade(app.core.tx, 0.1)
                          : (focused ? t.panel2 : Colors.transparent),
                      borderRadius: radius,
                    ),
                    child: Row(
                      children: [
                        Icon(widget.category.icon, size: 20, color: iconColor),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.category.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.category.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                  color: subColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Search entry at the top of the rail — looks like a search field, opens the
/// full-screen [SettingsSearchPage]. Self-contained (local `_focused`) so a
/// focus move only rebuilds this item, matching [_RailItem].
class _RailSearchItem extends StatefulWidget {
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback onActivate;

  const _RailSearchItem({
    required this.focusNode,
    required this.onKey,
    required this.onActivate,
  });

  @override
  State<_RailSearchItem> createState() => _RailSearchItemState();
}

class _RailSearchItemState extends State<_RailSearchItem> {
  /// Live, never cached — a remembered flag survives the focus change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => widget.focusNode.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final bool focused = _focused;
    final inverse = focused && app.focus.expression == FocusExpression.parallax;
    final Color fg = inverse
        ? app.inkOn(app.core.tx)
        : focused
        ? app.core.tx
        : t.dim;
    final radius = app.shape.br(22);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ParallaxFocus(
        focused: focused,
        shape: ParallaxShape.settingsRow,
        radius: radius,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: widget.onKey,
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              focusNode: widget.focusNode,
              borderRadius: radius,
              onTap: widget.onActivate,
              onFocusChange: (f) {
                setState(() {});
                if (f) {
                  // Reveal the top of the rail (search sits above category 0).
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && context.mounted) tvRevealMinimal(context);
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: inverse
                      ? app.core.tx
                      : (focused ? t.panel2 : app.fade(app.core.tx, 0.07)),
                  borderRadius: radius,
                  border: Border.all(
                    color: inverse
                        ? app.core.tx
                        : (focused ? t.accent : t.line),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: inverse ? fg : (focused ? t.accent2 : t.dim),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        'Search settings',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
