import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/torrent.dart';
import '../../models/torrent_filter_state.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/search/keyword_search_controller.dart';
import '../../services/torrent_playback_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/dialog_tap_guard.dart';
import '../../utils/format_tag_detector.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/search_loading_animation.dart';
import '../../widgets/source_row.dart';
import '../../widgets/torrent_filters_sheet.dart';

/// In-tab keyword torrent search. Extracted from `search_screen.dart` (G1'-3).
///
/// Controller owns query, streamed batches, freeze/adopt, selection, filters.
/// Screen params: [isTelevision], [onOpenStream], [onBulkAdd]. Host keeps the
/// mode chrome and a thin launcher (host switchMode).
class KeywordSearchScreen extends StatefulWidget {
  const KeywordSearchScreen({
    super.key,
    required this.controller,
    required this.isTelevision,
    required this.onOpenStream,
    required this.onBulkAdd,
    required this.onOpenSources,
    required this.onFocusSearchField,
    this.onFocusSidebar,
    this.onSnack,
  });

  final KeywordSearchController controller;
  final bool isTelevision;
  final void Function(
    BuildContext context,
    Torrent torrent,
    List<Torrent> sources,
    int sourceIndex,
    String searchKeyword,
  )
  onOpenStream;
  final Future<bool> Function(
    BuildContext context,
    List<Torrent> torrents,
    String keyword,
  )
  onBulkAdd;
  final Future<void> Function() onOpenSources;
  final VoidCallback onFocusSearchField;
  final VoidCallback? onFocusSidebar;
  final void Function(String message)? onSnack;

  @override
  State<KeywordSearchScreen> createState() => _KeywordSearchScreenState();
}

class _KeywordSearchScreenState extends State<KeywordSearchScreen> {
  KeywordSearchController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    c.kwScroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(KeywordSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_onChanged);
      oldWidget.controller.kwScroll.removeListener(_onScroll);
      c.addListener(_onChanged);
      c.kwScroll.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    c.kwScroll.removeListener(_onScroll);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (c.kwScroll.hasClients) c.kwLastScroll = c.kwScroll.offset;
  }

  @override
  Widget build(BuildContext context) => _buildSurface();

  Widget _buildSurface() {
    if (c.kwLoading) {
      // Branded phased loader (parity with the old screen) instead of a bare
      // spinner. Keyword search is never series-aware, so isSeries stays false.
      return SearchLoadingAnimation(
        phase: SearchPhase.searching,
        isTelevision: widget.isTelevision,
      );
    }
    if (c.kwError != null) {
      return _message(Icons.error_outline_rounded, 'Search failed', c.kwError!);
    }
    if (c.kwQuery.isEmpty) {
      // Surface Sources before searching so users can enable/disable the
      // trackers that get queried up front.
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _kwSourcesButton(),
            ),
          ),
          Expanded(
            child: _message(
              Icons.bolt_rounded,
              'Keyword torrent search',
              'Type a title and press search to find torrents across your '
                  'enabled sources, then tap one to play. Use Sources to choose '
                  'which trackers are queried.',
            ),
          ),
        ],
      );
    }
    final narrow =
        !widget.isTelevision && MediaQuery.of(context).size.width < 600;
    // Apply a restored scroll offset once the list is laid out, then clear it so
    // it only fires on the first build after a restore.
    if (c.pendingKwScroll != null && c.kwResults.isNotEmpty) {
      final off = c.pendingKwScroll!;
      c.pendingKwScroll = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.kwScroll.hasClients) {
          c.kwScroll.jumpTo(
            off.clamp(0.0, c.kwScroll.position.maxScrollExtent),
          );
        }
      });
    }
    final content = Column(
      children: [
        // Tabs are suppressed during multi-select: switching source mid-select
        // would hide checked rows under the user while "Add · N" still counts
        // them (matching the toolbar's own selection lock-out).
        if (c.kwTabsVisible && !c.kwSelectionMode) _kwSourceTabs(),
        _buildKeywordToolbar(floatingSelect: narrow),
        if (c.kwSearching) _kwSearchingStrip(),
        if (c.kwCachedOnly && c.kwAll.isNotEmpty) _kwCachedOnlyNotice(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: c.kwResults.isEmpty
                    ? _message(
                        Icons.search_off_rounded,
                        c.kwAll.isEmpty ? 'No results' : 'No matches',
                        c.kwAll.isEmpty
                            ? 'Nothing found for "$c.kwQuery". Try different '
                                  'keywords or enable more sources.'
                            : 'No results match your filters. Adjust or clear them.',
                      )
                    : NotificationListener<ScrollNotification>(
                        // A user drag (not programmatic scrolls) freezes live
                        // reshuffling — arrivals park behind the pill instead.
                        onNotification: (n) {
                          if (n is ScrollStartNotification &&
                              n.dragDetails != null) {
                            c.freeze();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: c.kwScroll,
                          // A focused SourceRow can scale and rise in
                          // Spotlight. The first item starts at scroll offset
                          // zero, so it needs real viewport clearance rather
                          // than relying on ensureVisible to make room.
                          padding: EdgeInsets.symmetric(
                            vertical: widget.isTelevision ? 24 : 8,
                            horizontal: 10,
                          ),
                          cacheExtent: 1200,
                          itemCount: c.kwResults.length,
                          itemBuilder: (context, i) {
                            final t = c.kwResults[i];
                            final selectable =
                                !t.isDirectStream && !t.isExternalStream;
                            final isStream = !selectable;
                            final labels =
                                c.kwCache[t.infohash.toLowerCase()] ?? const [];
                            final tags = isStream
                                ? const <FormatTag>[]
                                : FormatTagDetector.detect(t.name);
                            return SourceRow(
                              key: ValueKey(
                                '${t.infohash}_${c.kwSelectionMode}_${c.kwSelected.contains(t.infohash)}',
                              ),
                              title: t.displayTitle,
                              titleMaxLines: 6,
                              subtitle: _kwRowSubtitle(t),
                              focusNode: c.kwNodes[i],
                              isTelevision: widget.isTelevision,
                              showPlayPill: widget.isTelevision,
                              formatTags: tags,
                              badgeName: t.name,
                              badgeDescription: t.badgeDescription,
                              qualityTag: tags.isEmpty
                                  ? _qualityLabel(t)
                                  : null,
                              cacheLabel: labels.isEmpty
                                  ? null
                                  : labels.join(' | '),
                              streamBadge: t.isExternalStream
                                  ? 'External'
                                  : t.isDirectStream
                                  ? 'Direct'
                                  : null,
                              isSelectionMode: c.kwSelectionMode && selectable,
                              isSelected: c.kwSelected.contains(t.infohash),
                              onCopy: c.kwSelectionMode || t.copyLink == null
                                  ? null
                                  : () => unawaited(_copyKwLink(t)),
                              onTap: () {
                                if (c.kwSelectionMode && selectable) {
                                  c.toggleSelection(t);
                                  return;
                                }
                                // Swallow a SELECT that leaks through as a toolbar
                                // dialog (sort/filter/sources) closes on TV.
                                if (DialogTapGuard.shouldIgnoreTap()) return;
                                // Playing pushes the player — freeze so the list
                                // is exactly as left when the user comes back.
                                c.freeze();
                                widget.onOpenStream(
                                  context,
                                  t,
                                  c.kwResults,
                                  i,
                                  c.kwQuery,
                                );
                              },
                              onLongPress: c.kwSelectionMode
                                  ? null
                                  : selectable
                                  ? () {
                                      c.enterSelection();
                                      c.toggleSelection(t);
                                    }
                                  // Direct/external streams aren't selectable — long
                                  // press opens their Play/Copy/Download menu instead
                                  // (parity with the old direct-stream action dialog).
                                  : () {
                                      c.freeze();
                                      _showKwStreamMenu(t, i);
                                    },
                              onNavigateUp: () {
                                c.freeze();
                                if (i > 0) {
                                  c.kwNodes[i - 1].requestFocus();
                                } else if (c.kwPendingNewCount > 0 &&
                                    !c.kwSelectionMode) {
                                  // Parked arrivals: the pill is the row above
                                  // (unmounted during multi-select, where UP
                                  // must reach the selection toolbar instead).
                                  c.kwPillFocus.requestFocus();
                                } else if (c.kwToolbarVisible) {
                                  // From the top row, Up lands on the toolbar (Sort…),
                                  // not straight back to the search field.
                                  c.kwToolbarNodes.first.requestFocus();
                                } else {
                                  widget.onFocusSearchField();
                                }
                              },
                              onNavigateDown: () {
                                c.freeze();
                                if (i < c.kwNodes.length - 1) {
                                  c.kwNodes[i + 1].requestFocus();
                                }
                              },
                            );
                          },
                        ),
                      ),
              ),
              // Frozen-mode arrivals wait behind this pill so the list never
              // reshuffles under the user. Hidden during multi-select —
              // adopting would renumber rows under the checkmarks.
              if (c.kwPendingNewCount > 0 && !c.kwSelectionMode)
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(child: _kwNewResultsPill()),
                ),
            ],
          ),
        ),
      ],
    );

    if (!narrow) return content;
    // Small screens: Home-style floating select FAB / selection bar overlaid
    // on the results, instead of the toolbar "Select" pill.
    final canSelect = c.kwSelectableResults.isNotEmpty;
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (canSelect)
          c.kwSelectionMode ? _buildKwSelectionBar() : _buildKwSelectFab(),
      ],
    );
  }

  /// Standalone "Sources" pill shown in the pre-search keyword state so users
  /// can pick which trackers are queried before typing a query.
  Widget _kwSourcesButton() {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: c.kwSourcesBtnFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          _openKeywordSources();
          return KeyEventResult.handled;
        }
        // It's the only content in the pre-search state: Up returns to the
        // search field, Left hands off to the sidebar. Down has nowhere to go.
        if (key == LogicalKeyboardKey.arrowUp) {
          widget.onFocusSearchField();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onFocusSidebar?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: c.kwSourcesBtnFocus,
        builder: (context, _) {
          final focused = c.kwSourcesBtnFocus.hasFocus;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openKeywordSources,
              borderRadius: app.shape.brPill,
              canRequestFocus: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: app.shape.brPill,
                  // 1.5px always so focus never shifts layout: white ring when
                  // focused, else the faint idle border.
                  border: Border.all(
                    color: focused
                        ? app.fade(app.core.tx, 0.9)
                        : app.fade(app.core.tx, 0.10),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.dns_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sources',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// `size · ↑seeders · ↓leechers · SOURCE · date` meta line for a keyword
  /// row — same grammar as the Sources screen's rows (shared SourceRow look).
  static String _kwRowSubtitle(Torrent t) {
    final parts = <String>[];
    if (t.isDirectStream || t.isExternalStream) {
      if (t.sizeBytes > 0) {
        parts.add(_fmtSize(t.sizeBytes));
      }
      if (t.source.isNotEmpty) parts.add(t.source.toUpperCase());
      return parts.join(' · ');
    }
    if (t.sizeBytes > 0) parts.add(_fmtSize(t.sizeBytes));
    if (t.seeders > 0) parts.add('↑ ${t.seeders}');
    if (t.leechers > 0) parts.add('↓ ${t.leechers}');
    if (t.source.isNotEmpty) parts.add(t.source.toUpperCase());
    final date = _fmtDate(t.createdUnix);
    if (date != null) parts.add(date);
    return parts.join(' · ');
  }

  /// Display name for a source tab ('stremio:foo' → 'Foo').
  static String _kwPrettySource(String s) {
    final v = s.startsWith('stremio:') ? s.substring(8) : s;
    return v.isEmpty ? s : v[0].toUpperCase() + v.substring(1);
  }

  /// Horizontal source tabs (All / per-source with counts) above the toolbar —
  /// the fast single-select layer on top of the Providers multi-select. Only
  /// built when [c.kwTabsVisible] (2+ sources). Derives from [c.kwFullSet]:
  /// counts tick and new source pills appear live even while the rows below
  /// are frozen behind the pill (activating any tab folds the parked set in
  /// first, so what a tab press shows is always the complete picture). DPAD:
  /// left/right across tabs, up to the search field, down into the toolbar,
  /// select to activate.
  Widget _kwSourceTabs() {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final dim = app.fade(app.core.tx, 0.55);
    final sources = c.kwSourceList;
    final full = c.kwFullSet;
    final counts = <String, int>{};
    for (final t in full) {
      counts[KeywordSearchController.kwSourceOf(t)] =
          (counts[KeywordSearchController.kwSourceOf(t)] ?? 0) + 1;
    }
    final total = sources.length + 1;

    Widget tab(int navIndex, String label, bool on, VoidCallback onTap) {
      // Nodes are synced in c.recompute; a mid-build mismatch (e.g. the
      // strip rebuilt by a non-recompute setState) must not range-crash.
      final node = navIndex < c.kwTabNodes.length
          ? c.kwTabNodes[navIndex]
          : null;
      Widget body(bool focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: on ? accent : app.fade(app.core.tx, 0.05),
          borderRadius: app.shape.brPill,
          // Always 2px so focus never shifts layout.
          border: Border.all(
            color: focused ? app.fade(app.core.tx, 0.9) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            // Scored against the fill the selected tab actually paints.
            // `accent` IS the theme accent, and white fails on 17 of the 18
            // selectable themes (Noir's and Frost's are #FFFFFF), so a
            // hardcoded white label vanished into its own pill. Legacy's
            // #7B5CFF scores 4.36 against white, so inkOn still returns white
            // there — no visual change to today's app.
            color: on ? app.inkOn(accent) : dim,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      final Widget tappable = node == null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: app.shape.brPill,
                child: body(false),
              ),
            )
          : Focus(
              focusNode: node,
              onKeyEvent: (n, e) => _handleKwTabKey(navIndex, total, onTap, e),
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: app.shape.brPill,
                      canRequestFocus: false,
                      child: body(focused),
                    ),
                  );
                },
              ),
            );
      return Padding(padding: const EdgeInsets.only(right: 6), child: tappable);
    }

    // SingleChildScrollView + Row (not a lazy ListView) so EVERY tab's
    // FocusNode stays mounted — requestFocus on an unmounted node is a silent
    // no-op that would strand DPAD at the viewport edge (same reason the
    // keyword toolbar uses this shape).
    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          children: [
            tab(
              0,
              'All · ${full.length}',
              c.kwSourceTab == null,
              () => c.setSourceTab(null),
            ),
            for (var i = 0; i < sources.length; i++)
              tab(
                i + 1,
                '${_kwPrettySource(sources[i])} · ${counts[sources[i]] ?? 0}',
                c.kwSourceTab == sources[i],
                () => c.setSourceTab(sources[i]),
              ),
          ],
        ),
      ),
    );
  }

  /// DPAD/keyboard handling for a focused source tab: select activates,
  /// left/right move between tabs (left edge escapes to the sidebar), up
  /// returns to the search field, down drops into the toolbar pills.
  KeyEventResult _handleKwTabKey(
    int index,
    int total,
    VoidCallback onTap,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onFocusSearchField();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      c.kwToolbarNodes.first.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        c.focusTab(index - 1);
      } else {
        widget.onFocusSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < total - 1) c.focusTab(index + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Slim "still searching" strip under the toolbar while engines are in
  /// flight — rows are already usable, this just says more may arrive.
  Widget _kwSearchingStrip() {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 8),
          Text(
            'Still searching sources…',
            style: TextStyle(
              fontSize: 11.5,
              color: app.fade(app.core.tx, 0.55),
            ),
          ),
        ],
      ),
    );
  }

  /// The "+N new results" pill: tap (or OK on TV) folds the parked arrivals
  /// into the list; DOWN returns to the rows, UP reaches the toolbar.
  Widget _kwNewResultsPill() {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final n = c.kwPendingNewCount;
    return Focus(
      focusNode: c.kwPillFocus,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(e.logicalKey)) {
          c.adoptPending();
          if (c.kwNodes.isNotEmpty) c.kwNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (c.kwNodes.isNotEmpty) c.kwNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          c.kwToolbarNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: c.kwPillFocus,
        builder: (context, _) {
          final focused = c.kwPillFocus.hasFocus;
          return GestureDetector(
            onTap: c.adoptPending,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: focused ? app.core.tx : accent,
                borderRadius: app.shape.brPill,
                border: Border.all(
                  color: focused ? app.core.tx : Colors.transparent,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 14,
                    // Unfocused the pill is FILLED with the accent, so its ink
                    // has to be scored against it — white is invisible on the
                    // near-white accents (Noir, Frost, Vault). The focused
                    // branch keeps its dark ink on the white focus fill.
                    color: focused
                        ? const Color(0xFF17131F)
                        : app.inkOn(accent),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$n new result${n == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: focused
                          ? const Color(0xFF17131F)
                          : app.inkOn(accent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// [floatingSelect] true on small screens where the multi-select entry is a
  /// floating FAB + bar (Home-style) rather than a toolbar pill — so the
  /// toolbar stays Sort/Filters/Sources and never swaps to selection controls.
  Widget _buildKeywordToolbar({bool floatingSelect = false}) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Every facet counts. Sizes were already missing here, so a size-only
    // filter quietly trimmed the results while the pill still read "Filters"
    // and rendered inactive — the same trap a dynamic-range-only filter would
    // fall into.
    final filterCount =
        c.kwFilters.qualities.length +
        c.kwFilters.ripSources.length +
        c.kwFilters.languages.length +
        c.kwFilters.sizes.length +
        c.kwFilters.dynamicRanges.length;

    // [navIndex]/[navTotal], when provided, make the pill keyboard/DPAD
    // focusable at that position in the toolbar (left/right between pills, up to
    // the search field, down into the results, select to activate).
    Widget pill(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
      bool compact = false,
      int? navIndex,
      int navTotal = 0,
    }) {
      Widget body(bool focused) => Container(
        padding: compact
            ? const EdgeInsets.all(10)
            : const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHigh,
          borderRadius: app.shape.brPill,
          // Always 2px so focus never shifts layout: white ring when
          // focused, else the active/idle border.
          border: Border.all(
            color: focused
                ? app.fade(app.core.tx, 0.9)
                : active
                ? scheme.primary.withValues(alpha: 0.5)
                : app.fade(app.core.tx, 0.10),
            width: 2,
          ),
        ),
        child: compact
            ? Icon(
                icon,
                size: 18,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
      );

      final Widget tappable = navIndex == null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: app.shape.brPill,
                child: body(false),
              ),
            )
          : Focus(
              focusNode: c.kwToolbarNodes[navIndex],
              onKeyEvent: (n, event) =>
                  _handleKwToolbarKey(navIndex, navTotal, onTap, event),
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: app.shape.brPill,
                      canRequestFocus: false,
                      child: body(focused),
                    ),
                  );
                },
              ),
            );

      return Padding(padding: const EdgeInsets.only(right: 8), child: tappable);
    }

    if (c.kwSelectionMode && !floatingSelect) {
      final selectable = c.kwSelectableResults.length;
      final count = c.kwSelected.length;
      final allSelected = count > 0 && count == selectable;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            pill(
              Icons.close_rounded,
              'Cancel',
              c.exitSelection,
              navIndex: 0,
              navTotal: 3,
            ),
            pill(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              allSelected ? 'None' : 'All',
              allSelected ? c.deselectAll : c.selectAll,
              navIndex: 1,
              navTotal: 3,
            ),
            pill(
              Icons.playlist_add_rounded,
              count > 0 ? 'Add · $count' : 'Add',
              count > 0 ? _openBulkAdd : () {},
              active: count > 0,
              navIndex: 2,
              navTotal: 3,
            ),
          ],
        ),
      );
    }

    final canSelect = c.kwSelectableResults.isNotEmpty;
    final showSelect = canSelect && !floatingSelect;
    final showProviders = c.kwHasProviderFilter;
    final providerActive = c.kwProviderFilterActive;
    // Build the pill set dynamically so navIndex stays contiguous when the
    // optional Providers / Select pills come and go. Base pills always present:
    // Sort, Filters, Sources (3); Providers and Select are optional.
    final total = 3 + (showProviders ? 1 : 0) + (showSelect ? 1 : 0);
    var idx = 0;
    final pills = <Widget>[
      pill(
        Icons.sort_rounded,
        'Sort · ${_sortLabel(c.kwSort)}',
        _openKeywordSort,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      pill(
        Icons.filter_list_rounded,
        filterCount > 0 ? 'Filters · $filterCount' : 'Filters',
        _openKeywordFilters,
        active: filterCount > 0,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      if (showProviders)
        pill(
          Icons.hub_rounded,
          providerActive > 0 ? 'Providers · $providerActive' : 'Providers',
          _openKeywordProviders,
          active: providerActive > 0,
          compact: floatingSelect,
          navIndex: idx++,
          navTotal: total,
        ),
      pill(
        Icons.dns_rounded,
        'Sources',
        _openKeywordSources,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      if (showSelect)
        pill(
          Icons.checklist_rounded,
          'Select',
          c.enterSelection,
          navIndex: idx++,
          navTotal: total,
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(children: pills),
    );
  }

  /// DPAD/keyboard handling for a focused keyword-toolbar pill: select fires the
  /// pill, left/right move between pills, up returns to the search field, down
  /// drops into the first result row.
  KeyEventResult _handleKwToolbarKey(
    int index,
    int total,
    VoidCallback onTap,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      // Source tabs sit between the toolbar and the search field — land on
      // the active tab so the strip context is obvious. Hidden during
      // multi-select (the strip is suppressed then — see _buildKeyword).
      if (!c.kwSelectionMode && c.kwTabsVisible && c.kwTabNodes.isNotEmpty) {
        final tabs = c.kwSourceList;
        final active = c.kwSourceTab == null
            ? 0
            : tabs.indexOf(c.kwSourceTab!) + 1;
        c.focusTab(active >= 0 && active < c.kwTabNodes.length ? active : 0);
        return KeyEventResult.handled;
      }
      widget.onFocusSearchField();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (c.kwNodes.isNotEmpty) {
        c.kwNodes.first.requestFocus();
      } else if (c.kwPendingNewCount > 0 && !c.kwSelectionMode) {
        // Zero rows (e.g. a no-match filter) but arrivals parked behind the
        // pill: the pill must stay reachable or it's visible-but-dead on TV.
        c.kwPillFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        c.kwToolbarNodes[index - 1].requestFocus();
      } else {
        widget.onFocusSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < total - 1) c.kwToolbarNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Floating checklist FAB (bottom-left) that enters multi-select on small
  /// screens — ported from Home's torrent-search layout.
  Widget _buildKwSelectFab() {
    final app = AppThemeScope.of(context);
    return Positioned(
      left: 16,
      bottom: 16,
      child: GestureDetector(
        onTap: c.enterSelection,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: app.home.controlBg,
            shape: BoxShape.circle,
            border: Border.all(color: app.fade(app.core.tx, 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(Icons.checklist_rounded, color: app.core.tx, size: 20),
        ),
      ),
    );
  }

  /// Floating multi-select bar (bottom) — Home-style. Right-inset so it clears
  /// the mobile floating "Menu" nav.
  Widget _buildKwSelectionBar() {
    final app = AppThemeScope.of(context);
    final selectable = c.kwSelectableResults.length;
    final count = c.kwSelected.length;
    final allSelected = count > 0 && count == selectable;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    Widget chip(Widget child, VoidCallback? onTap, Color bg) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: app.shape.br(8)),
        child: child,
      ),
    );

    return Positioned(
      left: 12,
      // Clear the bottom-right "Menu" FAB — which only the floating nav
      // style has; the classic bar occupies its own strip below the page.
      right: MainPageBridge.phoneNavStyleCached == 'floating' ? 108 : 12,
      bottom: 12 + bottomPad,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: app.shape.br(16),
          border: Border.all(color: app.fade(app.home.chromeAccent, 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            chip(
              Icon(
                Icons.close_rounded,
                color: app.core.tx.withValues(alpha: 0xB3 / 0xFF),
                size: 18,
              ),
              c.exitSelection,
              app.fade(app.core.tx, 0.1),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '$count selected',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: count > 0
                      ? app.home.chromeAccent
                      : app.core.tx.withValues(alpha: 0x8A / 0xFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            chip(
              Text(
                allSelected ? 'None' : 'All',
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0xB3 / 0xFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              allSelected ? c.deselectAll : c.selectAll,
              app.fade(app.core.tx, 0.08),
            ),
            const SizedBox(width: 8),
            chip(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    // Enabled, this chip is filled with the OPAQUE accent, so
                    // its ink is scored against it (white disappears on Noir's
                    // and Frost's #FFFFFF accent). Disabled, the fill is a 0.3
                    // wash over the dark bar, where white38 still reads.
                    color: count > 0
                        ? app.inkOn(app.home.chromeAccent)
                        : Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Add',
                    style: TextStyle(
                      color: count > 0
                          ? app.inkOn(app.home.chromeAccent)
                          : Colors.white38,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              count > 0 ? _openBulkAdd : null,
              count > 0
                  ? app.home.chromeAccent
                  : app.fade(app.home.chromeAccent, 0.3),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(String s) =>
      const {
        'relevance': 'Relevance',
        'seeders': 'Seeders',
        'size': 'Size',
        'date': 'Date',
        'name': 'Name',
      }[s] ??
      s;

  Future<void> _openBulkAdd() async {
    if (c.kwBulkBusy) return;
    final chosen = c.kwResults
        .where((t) => c.kwSelected.contains(t.infohash))
        .toList();
    if (chosen.isEmpty) return;
    c.kwBulkBusy = true;
    bool chose = false;
    try {
      chose = await widget.onBulkAdd(context, chosen, c.kwQuery);
    } finally {
      c.kwBulkBusy = false;
    }
    // Stay in selection mode if the user just dismissed the chooser.
    if (mounted && chose && c.kwSelectionMode) c.exitSelection();
  }

  void _showKwStreamMenu(Torrent t, int i) {
    final app = AppThemeScope.of(context);
    final external = t.isExternalStream;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.home.sheetBg,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                external ? Icons.open_in_new_rounded : Icons.play_arrow_rounded,
                color: app.core.tx,
              ),
              title: Text(external ? 'Open externally' : 'Play now'),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                widget.onOpenStream(context, t, c.kwResults, i, c.kwQuery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Color(0xFFF59E0B)),
              title: const Text('Copy link'),
              onTap: () async {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                await _copyKwLink(t);
              },
            ),
            if (ProfilePolicyGuard.allowsSync(ProfileFeature.downloads))
              ListTile(
                leading: const Icon(
                  Icons.download_rounded,
                  color: Color(0xFF60A5FA),
                ),
                title: const Text('Download to device'),
                onTap: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(sheetCtx).pop();
                  unawaited(
                    TorrentPlaybackService.downloadDirectStream(context, t),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyKwLink(Torrent t) async {
    final link = t.copyLink;
    if (link == null) {
      widget.onSnack?.call('No link available for this source.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) widget.onSnack?.call('Link copied to clipboard');
  }

  Future<void> _openKeywordFilters() async {
    c.freezeAndAdopt();
    final result = await showDialog<TorrentFilterState>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: TorrentFiltersSheet(initialState: c.kwFilters),
      ),
    );
    if (result == null || !mounted) return;
    c.kwFilters = result;
    c.recompute();
  }

  Widget _kwCachedOnlyNotice() {
    final app = AppThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
        borderRadius: app.shape.br(8),
        border: Border.all(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF38BDF8),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing Torbox cached results only. Disable "Check Torbox cache '
              'during searches" in Torbox settings to see every result.',
              style: TextStyle(
                fontSize: 12,
                color: app.fade(app.core.tx, 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openKeywordProviders() async {
    c.freezeAndAdopt();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void apply(VoidCallback mutate) {
              setLocal(mutate);
              c.recompute();
            }

            Widget group(
              String title,
              Map<String, int> counts,
              Set<String> selected,
            ) {
              if (counts.isEmpty) return const SizedBox.shrink();
              final entries = counts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final allOn = selected.length == counts.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => apply(() {
                            if (allOn) {
                              selected.clear();
                            } else {
                              selected
                                ..clear()
                                ..addAll(counts.keys);
                            }
                          }),
                          child: Text(allOn ? 'None' : 'All'),
                        ),
                      ],
                    ),
                  ),
                  ...entries.map(
                    (e) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected.contains(e.key),
                      title: Text(
                        e.key,
                        style: TextStyle(fontSize: 13, color: scheme.onSurface),
                      ),
                      secondary: Text(
                        '${e.value}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      onChanged: (_) => apply(() {
                        if (selected.contains(e.key)) {
                          selected.remove(e.key);
                        } else {
                          selected.add(e.key);
                        }
                      }),
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: const Text('Filter by source'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      group('Direct', c.kwDirectCounts, c.kwSelectedDirect),
                      group('Torrent', c.kwTorrentCounts, c.kwSelectedTorrent),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openKeywordSort() async {
    c.freezeAndAdopt();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void applyField(String value) {
              setLocal(() {
                c.kwSort = value;
                c.kwSortAsc = c.naturalAscFor(value);
              });
              c.recompute();
            }

            void applyDir(bool asc) {
              setLocal(() => c.kwSortAsc = asc);
              c.recompute();
            }

            Widget tile(String value, String label) => ListTile(
              dense: true,
              title: Text(label),
              trailing: c.kwSort == value
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () => applyField(value),
            );

            final dirEnabled = c.kwSort != 'relevance';
            return AlertDialog(
              backgroundColor: scheme.surfaceContainerHigh,
              title: const Text('Sort by'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tile('relevance', 'Relevance'),
                  tile('seeders', 'Seeders'),
                  tile('size', 'Size'),
                  tile('date', 'Date added'),
                  tile('name', 'Name'),
                  const Divider(height: 12),
                  Opacity(
                    opacity: dirEnabled ? 1 : 0.4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Direction')),
                          ToggleButtons(
                            isSelected: [!c.kwSortAsc, c.kwSortAsc],
                            onPressed: dirEnabled
                                ? (i) => applyDir(i == 1)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            constraints: const BoxConstraints(
                              minHeight: 34,
                              minWidth: 46,
                            ),
                            children: const [
                              Icon(Icons.arrow_downward_rounded, size: 18),
                              Icon(Icons.arrow_upward_rounded, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openKeywordSources() async {
    final fromToolbar = c.kwToolbarNodes.any((n) => n.hasFocus);
    await widget.onOpenSources();
    if (!mounted || c.kwQuery.isEmpty) return;
    await c.run(c.kwQuery, refocusToolbar: fromToolbar);
  }

  static String? _fmtDate(int createdUnix) {
    if (createdUnix <= 0) return null;
    final then = DateTime.fromMillisecondsSinceEpoch(createdUnix * 1000);
    final d = DateTime.now().difference(then);
    if (d.inDays >= 365) return '${(d.inDays / 365).floor()}y ago';
    if (d.inDays >= 30) return '${(d.inDays / 30).floor()}mo ago';
    if (d.inDays >= 7) return '${(d.inDays / 7).floor()}w ago';
    if (d.inDays >= 1) return '${d.inDays}d ago';
    if (d.inHours >= 1) return '${d.inHours}h ago';
    return 'Today';
  }

  static String? _qualityLabel(Torrent t) {
    final tags = FormatTagDetector.detect(t.name);
    if (tags.contains(FormatTag.uhd4k)) return '4K';
    if (tags.contains(FormatTag.fullHd)) return '1080p';
    if (tags.contains(FormatTag.hd720)) return '720p';
    return null;
  }

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var u = 0;
    while (size >= 1024 && u < units.length - 1) {
      size /= 1024;
      u++;
    }
    return '${size.toStringAsFixed(size >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
  }

  Widget _message(IconData icon, String title, String body) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
