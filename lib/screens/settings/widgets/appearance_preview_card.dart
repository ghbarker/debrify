import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/text_brightness.dart';
import '../../../theme/app_looks.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_theme_controller.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../theme/appearance_preview.dart';
import '../../../theme/widgets/theme_preview_stage.dart';
import '../../../utils/platform_util.dart';
import '../../../widgets/detail/theme/detail_themes.dart';
import 'layout_preview_channel.dart';
import 'layout_preview_stage.dart';

/// The live preview pinned to the top of Appearance.
///
/// Shows [state] on a real mini-screen ([ThemePreviewStage]) and, under it,
/// the Looks as chips. Pointing at a chip (hover, or DPAD/keyboard focus
/// moving along the strip) reports it through [onPreview] so the host can
/// show that Look WITHOUT applying it; choosing one (tap, OK, Enter) reports
/// it through [onApply]. The card itself never touches a controller — the
/// theme it draws is resolved purely from [state], which is what lets a test
/// pump it for every Look with no storage behind it.
///
/// Focus: the whole strip is ONE focus node ([focusNode]). On TV the pane
/// walker moves Up/Down by node index, so a chip per node would put seven
/// horizontal stops in a vertical list; one node with Left/Right inside it
/// keeps Down landing on the first row below. Left at the first chip is left
/// unhandled so the pane can hand it to the rail as usual.
class AppearancePreviewCard extends StatefulWidget {
  const AppearancePreviewCard({
    super.key,
    required this.state,
    required this.onApply,
    this.onPreview,
    this.looks = AppLooks.all,
    this.activeLookId,
    this.candidate = false,
    this.focusNode,
    this.singleRow,
    this.layout,
  });

  /// What to draw.
  final AppearancePreviewState state;

  /// A Screen-layouts option to draw on the stage instead of the theme
  /// stage — the one under the pointer / D-pad highlight on an inline row,
  /// or the applied option of the row touched last. Null: the theme stage.
  /// A Look candidate ([candidate]) always wins over it, since the look strip
  /// is this card's own control.
  final LayoutPreviewTarget? layout;

  /// The Looks offered on the strip.
  final List<AppLook> looks;

  /// The Look the app is actually on, for the tick. Null for Custom.
  final String? activeLookId;

  /// True while [state] shows something other than the applied options —
  /// the caption then says so, because a preview that looks applied is a lie.
  final bool candidate;

  /// A Look is under the pointer / focus (or null: nothing is), so the host
  /// can swap [state] to show it.
  final ValueChanged<AppLook?>? onPreview;

  /// The user chose this Look.
  final Future<void> Function(AppLook look) onApply;

  /// The strip's focus node — on TV, the pane node this card claims.
  final FocusNode? focusNode;

  /// One horizontal, scrolling row of chips instead of a Wrap. Null means
  /// "on a television": Left/Right is the only way a D-pad walks the strip,
  /// so a wrapped second row would be unreachable; pointer surfaces keep the
  /// Wrap, where every chip stays under the mouse without scrolling.
  final bool? singleRow;

  @override
  State<AppearancePreviewCard> createState() => _AppearancePreviewCardState();
}

class _AppearancePreviewCardState extends State<AppearancePreviewCard> {
  /// Resolved themes by [AppearancePreviewState.cacheKey]. A hover sweep
  /// across the strip resolves each Look once, not once per frame.
  final Map<String, AppTheme> _cache = {};
  static const int _kCacheCap = 16;
  final GlobalKey _cardKey = GlobalKey();

  /// The strip took focus (TV Up/Down landed on it). Coming from the rows
  /// below, only the strip would be on screen and nothing brings the stage
  /// back — so scroll the WHOLE card to the top of the pane. Post-frame: the
  /// focus change setState may still be pending layout.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cardKey.currentContext;
      if (!mounted || ctx == null) return;
      final motion = AppMotion.of(ctx);
      Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        duration: motion.scaled(const Duration(milliseconds: 220)),
        curve: motion.standard,
      );
    });
  }

  AppTheme _resolve(AppearancePreviewState s) {
    final hit = _cache[s.cacheKey];
    if (hit != null) return hit;
    if (_cache.length >= _kCacheCap) _cache.clear();
    return _cache[s.cacheKey] = resolveAppearancePreview(s);
  }

  /// The theme the stage is currently drawing — for tests.
  @visibleForTesting
  AppTheme get shownTheme => _resolve(widget.state);

  /// The layout on the stage, or null when the theme stage is up.
  LayoutPreviewTarget? get _layoutShown =>
      widget.candidate ? null : widget.layout;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final shown = _resolve(widget.state);
    final layout = _layoutShown;
    final radius = app.shape.br(13);
    return Container(
      key: _cardKey,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          t.accent.withValues(alpha: 0.06),
          app.fade(app.core.tx, 0.03),
        ),
        borderRadius: radius,
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (layout != null)
            _Caption(
              label: layout.optionLabel,
              eyebrow: layout.rowTitle.toUpperCase(),
              candidate: !layout.applied,
            )
          else
            _Caption(
              label: widget.state.lookLabel ?? 'Custom',
              candidate: widget.candidate,
            ),
          const SizedBox(height: 10),
          // The theme stage always sizes the slot, even while a layout is
          // shown over it: swapping stages must not change the card's
          // height, or the first hover on a row below would move that row
          // out from under the pointer (an exit, and the preview snaps back).
          Stack(
            children: [
              Visibility(
                visible: layout == null,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: ThemePreviewStage(theme: shown),
              ),
              if (layout != null)
                Positioned.fill(
                  child: LayoutPreviewStage(
                    theme: shown,
                    rowId: layout.rowId,
                    optionId: layout.optionId,
                    variant: layout.variant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _LookStrip(
            looks: widget.looks,
            activeLookId: widget.activeLookId,
            focusNode: widget.focusNode,
            onPreview: widget.onPreview,
            onApply: widget.onApply,
            onFocused: _reveal,
            singleRow: widget.singleRow ?? PlatformUtil.isTelevision,
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.label,
    required this.candidate,
    this.eyebrow,
  });

  final String label;
  final bool candidate;

  /// What kind of thing [label] names when it is not a Look — the row's
  /// title, appended after the preview state ("PREVIEWING · DETAILS PAGE").
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final state = candidate ? 'PREVIEWING' : 'LIVE PREVIEW';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow == null ? state : '$state · $eyebrow',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.55,
                  color: t.accent2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: app.core.tx,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          candidate ? 'Not applied yet' : 'Applied',
          style: TextStyle(fontSize: 10.5, color: t.dim),
        ),
      ],
    );
  }
}

/// The Looks as chips, under one focus node. See [AppearancePreviewCard].
class _LookStrip extends StatefulWidget {
  const _LookStrip({
    required this.looks,
    required this.activeLookId,
    required this.focusNode,
    required this.onPreview,
    required this.onApply,
    this.onFocused,
    this.singleRow = false,
  });

  final List<AppLook> looks;
  final String? activeLookId;
  final FocusNode? focusNode;
  final ValueChanged<AppLook?>? onPreview;
  final Future<void> Function(AppLook look) onApply;
  final VoidCallback? onFocused;
  final bool singleRow;

  @override
  State<_LookStrip> createState() => _LookStripState();
}

class _LookStripState extends State<_LookStrip> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  /// The chip Left/Right is on while the strip has focus.
  int _highlight = 0;
  bool _focused = false;
  AppLook? _hover;

  /// One horizontal row, never a Wrap: Left/Right is the only way a D-pad
  /// moves along the strip, so a second wrapped row would be unreachable.
  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  List<GlobalKey> _chipKeys = const [];

  void _syncChipKeys() {
    if (_chipKeys.length != widget.looks.length) {
      _chipKeys = List.generate(widget.looks.length, (_) => GlobalKey());
    }
  }

  /// Scrolls the strip (horizontally only — never the pane) so the
  /// highlighted chip is fully on screen, with a little breathing room.
  void _keepChipVisible() {
    if (!widget.singleRow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_highlight < 0 || _highlight >= _chipKeys.length) return;
      final chip = _chipKeys[_highlight].currentContext?.findRenderObject();
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (chip is! RenderBox || viewport is! RenderBox) return;
      const pad = 12.0;
      final visibleLeft = chip
          .localToGlobal(Offset.zero, ancestor: viewport)
          .dx;
      final left = visibleLeft + _scroll.offset;
      final right = left + chip.size.width;
      final extent = viewport.size.width;
      var target = _scroll.offset;
      if (left - pad < _scroll.offset) {
        target = left - pad;
      } else if (right + pad > _scroll.offset + extent) {
        target = right + pad - extent;
      }
      target = target.clamp(0.0, _scroll.position.maxScrollExtent);
      if (target == _scroll.offset) return;
      final motion = AppMotion.of(context);
      _scroll.animateTo(
        target,
        duration: motion.scaled(const Duration(milliseconds: 160)),
        curve: motion.standard,
      );
    });
  }

  @override
  void didUpdateWidget(covariant _LookStrip old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) _release(old.focusNode);
  }

  @override
  void dispose() {
    _release(widget.focusNode);
    _ownNode?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The pane node is owned by the layout and outlives this widget. Focus does
  /// not clear an external node's onKeyEvent on dispose, and FocusNode.attach
  /// keeps the old handler when the next Focus supplies none — so without this
  /// the node keeps routing Left/Right to a disposed State and every key event
  /// in the app throws from inside the focus manager.
  void _release(FocusNode? node) {
    if (node != null && node.onKeyEvent == _onKey) node.onKeyEvent = null;
  }

  /// Pointer beats keyboard: a hovered chip is what the eye is on.
  void _emit() {
    final look = _hover ?? (_focused ? widget.looks[_highlight] : null);
    widget.onPreview?.call(look);
  }

  void _onFocusChange(bool focused) {
    if (!mounted) return;
    setState(() {
      _focused = focused;
      if (focused) {
        // Land on the applied Look, so the first Left/Right steps away from
        // what the app has rather than from an arbitrary first chip.
        final i = widget.looks.indexWhere((l) => l.id == widget.activeLookId);
        _highlight = i < 0 ? 0 : i;
      }
    });
    _emit();
    if (focused) {
      widget.onFocused?.call();
      _keepChipVisible();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      // At the first chip, unhandled on purpose: the TV pane turns it into
      // "back to the rail", exactly as for every other row.
      if (_highlight == 0) return KeyEventResult.ignored;
      setState(() => _highlight--);
      _emit();
      _keepChipVisible();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_highlight < widget.looks.length - 1) {
        setState(() => _highlight++);
        _emit();
        _keepChipVisible();
      }
      // Trapped at the end so directional traversal cannot carry focus off
      // to whatever happens to sit to the right.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      widget.onApply(widget.looks[_highlight]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _syncChipKeys();
    Widget chip(int i) => KeyedSubtree(
      key: _chipKeys[i],
      child: _LookChip(
        look: widget.looks[i],
        active: widget.looks[i].id == widget.activeLookId,
        highlighted: _focused && i == _highlight,
        onEnter: () {
          _hover = widget.looks[i];
          _emit();
        },
        onExit: () {
          if (_hover?.id == widget.looks[i].id) _hover = null;
          _emit();
        },
        onTap: () {
          // A tap also moves the keyboard highlight, so a later OK
          // re-applies what was just chosen rather than a stale chip.
          setState(() => _highlight = i);
          widget.onApply(widget.looks[i]);
        },
      ),
    );
    final Widget body = widget.singleRow
        ? SingleChildScrollView(
            key: _viewportKey,
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            // Clip at the strip's own bounds: with Clip.none the off-screen
            // chips painted straight across the card's padding and border.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.looks.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  chip(i),
                ],
              ],
            ),
          )
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (var i = 0; i < widget.looks.length; i++) chip(i)],
          );
    return Focus(
      focusNode: _node,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: body,
    );
  }
}

class _LookChip extends StatelessWidget {
  const _LookChip({
    required this.look,
    required this.active,
    required this.highlighted,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
  });

  final AppLook look;
  final bool active;
  final bool highlighted;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  /// The Look's accent, from its theme CORE only — no subprofile derivation
  /// for a 9px dot.
  Color _swatch() {
    final id = look.values['app_theme'] ?? AppThemes.legacyId;
    if (id == AppThemes.legacyId) return AppThemes.legacy.core.accent;
    return DetailThemes.byId(id).accent;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final lit = active || highlighted;
    final border = highlighted
        ? t.accent
        : active
        ? t.accent.withValues(alpha: 0.6)
        : t.line;
    return Semantics(
      button: true,
      selected: active,
      label: look.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
            decoration: BoxDecoration(
              color: active
                  ? Color.alphaBlend(
                      t.accent.withValues(alpha: 0.14),
                      app.fade(app.core.tx, 0.03),
                    )
                  : app.fade(app.core.tx, 0.04),
              borderRadius: app.shape.br(20),
              border: Border.all(color: border, width: highlighted ? 2 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _swatch(),
                    shape: BoxShape.circle,
                    border: Border.all(color: t.line),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    look.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: lit ? FontWeight.w700 : FontWeight.w500,
                      color: lit ? app.core.tx : t.dim,
                    ),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.check_rounded, size: 13, color: t.accent2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Binds [AppearancePreviewCard] to the live app: the applied options come
/// from `AppThemeController` and `TextBrightnessController`, a hovered or
/// focused Look temporarily replaces them, and choosing a Look applies it the
/// way the Looks page does.
///
/// Listens to both controllers directly rather than trusting an ancestor
/// rebuild, so a change made on an opener page (Text Brightness, Advanced)
/// is on the card the moment the user comes back — or while the page is still
/// open, where the shell keeps the card visible.
class AppearancePreviewHost extends StatefulWidget {
  const AppearancePreviewHost({
    super.key,
    this.focusNode,
    this.applyLook,
    this.singleRow,
    this.layoutChannel,
  });

  /// See [AppearancePreviewCard.singleRow]; null follows the platform.
  final bool? singleRow;

  /// The strip's focus node — on TV, the pane node this card claims.
  final FocusNode? focusNode;

  /// Override for tests. Default: clear token edits, then `LookApplier.apply`,
  /// exactly the Looks page's sequence.
  final Future<void> Function(AppLook look)? applyLook;

  /// Where the inline Screen-layouts rows report what they are pointing at.
  /// Test seam; production shares [LayoutPreviewChannel.instance].
  final LayoutPreviewChannel? layoutChannel;

  @override
  State<AppearancePreviewHost> createState() => _AppearancePreviewHostState();
}

class _AppearancePreviewHostState extends State<AppearancePreviewHost> {
  AppLook? _candidate;
  bool _applying = false;

  LayoutPreviewChannel get _layouts =>
      widget.layoutChannel ?? LayoutPreviewChannel.instance;

  @override
  void initState() {
    super.initState();
    AppThemeController.instance.addListener(_changed);
    TextBrightnessController.notifier.addListener(_changed);
    _layouts.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AppearancePreviewHost old) {
    super.didUpdateWidget(old);
    if (old.layoutChannel != widget.layoutChannel) {
      (old.layoutChannel ?? LayoutPreviewChannel.instance).removeListener(
        _changed,
      );
      _layouts.addListener(_changed);
    }
  }

  @override
  void dispose() {
    AppThemeController.instance.removeListener(_changed);
    TextBrightnessController.notifier.removeListener(_changed);
    _layouts.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _apply(AppLook look) async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      if (widget.applyLook != null) {
        await widget.applyLook!(look);
      } else {
        // Cleared BEFORE the apply — see LooksPage._apply for why a trailing
        // clear would also delete an edit made while the apply was running.
        await AppThemeController.instance.clearOverrides();
        await LookApplier.apply(look);
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeController.instance;
    final edits = controller.overrides.count;
    // A Look with tokens edited on top is NOT that Look — same rule as the
    // Looks page's tick.
    final active = edits == 0 ? AppLooks.active() : null;
    final candidate = _candidate;
    final state = candidate != null
        ? AppearancePreviewState.forLook(candidate)
        : AppearancePreviewState(
            themeId: controller.id,
            overrides: controller.overrides,
            preset: TextBrightnessController.current,
            lookLabel: active?.label,
          );
    return AppearancePreviewCard(
      state: state,
      activeLookId: active?.id,
      candidate: candidate != null && candidate.id != active?.id,
      layout: _layouts.shown,
      focusNode: widget.focusNode,
      singleRow: widget.singleRow,
      onPreview: (look) {
        if (look?.id == _candidate?.id) return;
        setState(() => _candidate = look);
      },
      onApply: _apply,
    );
  }
}
