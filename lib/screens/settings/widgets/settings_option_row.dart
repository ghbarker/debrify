import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../layout_options.dart';
import 'layout_preview_channel.dart';
import 'tv_chip_row.dart';

/// A Screen-layouts row with its options inline, as chips.
///
/// Pointing at a chip (hover, or the D-pad highlight moving along the row)
/// reports it to the [LayoutPreviewChannel] as a candidate so the preview
/// card can draw that layout WITHOUT applying it; choosing one (tap, OK,
/// Enter) calls [SettingsLayoutOptions.apply] — the opener page's own
/// setter — and the row marks it. The row keeps its own `_selected` so the
/// tick moves on the frame the choice lands, before the settings screen has
/// rebuilt with the new value.
///
/// Focus: the whole row is ONE focus node ([focusNode]) — on TV the pane node
/// the layout hands it. The pane walker moves Up/Down by node index, so a
/// chip per node would put a horizontal strip into a vertical walk; one node
/// with Left/Right inside keeps Down landing on the next row. Left at the
/// first chip is left unhandled so the pane can hand it to the rail, exactly
/// as the look strip does. Up/Down are never handled here.
///
/// The pane node is owned by the layout and reused across categories, and
/// Focus does not clear an external node's onKeyEvent on dispose — see
/// [_release], which mirrors the look strip's fix for the Shield.
class SettingsOptionRow extends StatefulWidget {
  const SettingsOptionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.options,
    this.focusNode,
    this.channel,
    this.singleRow,
  });

  final IconData icon;
  final String title;
  final SettingsLayoutOptions options;

  /// Lets a parent (the TV two-pane rail) drive focus onto this row.
  final FocusNode? focusNode;

  /// Test seam; production rows share [LayoutPreviewChannel.instance].
  final LayoutPreviewChannel? channel;

  /// One horizontal, scrolling row of chips instead of a Wrap. Null means
  /// "on a television": a D-pad cannot reach a chip that wrapped onto a
  /// second row (the Details Page row's 11 options were the reported case),
  /// so TV always uses the single scrolling row; pointer surfaces keep the
  /// Wrap, where every chip stays under the mouse without scrolling.
  final bool? singleRow;

  /// The row id, for tests walking the category column.
  String get rowId => options.rowId;

  @override
  State<SettingsOptionRow> createState() => _SettingsOptionRowState();
}

class _SettingsOptionRowState extends State<SettingsOptionRow> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());
  LayoutPreviewChannel get _channel =>
      widget.channel ?? LayoutPreviewChannel.instance;

  late String _selected;

  /// Index into the strip (options, then the More chip) Left/Right is on.
  int _highlight = 0;
  bool _focused = false;
  bool _hoveredRow = false;
  int? _hoverChip;

  int get _moreIndex => widget.options.options.length;
  int get _stripLength =>
      widget.options.options.length + (widget.options.onMore != null ? 1 : 0);

  /// One horizontal row, never a Wrap, on TV — see [TvChipRow]. Shared with
  /// the Appearance Look strip so a D-pad surface can always reach every
  /// chip, however many a row has.
  final GlobalKey<TvChipRowState> _rowKey = GlobalKey<TvChipRowState>();
  bool get _singleRow => widget.singleRow ?? PlatformUtil.isTelevision;

  void _keepChipVisible() {
    if (!_singleRow) return;
    _rowKey.currentState?.keepVisible();
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.options.current();
  }

  @override
  void didUpdateWidget(covariant SettingsOptionRow old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) _release(old.focusNode);
    // The settings screen rebuilt with a fresh value (its own load, a Look
    // apply, a restore): follow it.
    final now = widget.options.current();
    if (now != old.options.current() && now != _selected) {
      _selected = now;
    }
  }

  @override
  void dispose() {
    _release(widget.focusNode);
    _ownNode?.dispose();
    super.dispose();
  }

  /// Focus never clears an external node's onKeyEvent, and FocusNode.attach
  /// keeps the old handler when the next Focus supplies none — so without
  /// this the pane node keeps routing Left/Right to a disposed State.
  void _release(FocusNode? node) {
    if (node != null && node.onKeyEvent == _onKey) node.onKeyEvent = null;
  }

  LayoutPreviewTarget _target(LayoutOption o) => LayoutPreviewTarget(
    rowId: widget.options.rowId,
    rowTitle: widget.title,
    optionId: o.id,
    optionLabel: o.label,
    applied: o.id == _selected,
    variant: widget.options.variant?.call(),
  );

  LayoutOption? get _applied => widget.options.byId(_selected);

  /// The option the eye is on: a hovered chip beats the keyboard highlight.
  LayoutOption? get _eyeOn {
    final h = _hoverChip;
    if (h != null && h < widget.options.options.length) {
      return widget.options.options[h];
    }
    if (_focused && _highlight < widget.options.options.length) {
      return widget.options.options[_highlight];
    }
    return null;
  }

  void _emit() {
    final applied = _applied;
    if (applied != null) _channel.rest(_target(applied));
    final on = _eyeOn;
    if (on != null) {
      _channel.point(_target(on));
    } else {
      _channel.unpoint(widget.options.rowId);
    }
  }

  void _onFocusChange(bool focused) {
    if (!mounted) return;
    setState(() {
      _focused = focused;
      if (focused) {
        // Land on the applied option, so the first Left/Right steps away from
        // what the app has rather than from an arbitrary first chip.
        final i = widget.options.options.indexWhere((o) => o.id == _selected);
        _highlight = i < 0 ? 0 : i;
      }
    });
    _emit();
    if (focused) _keepChipVisible();
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
      if (_highlight < _stripLength - 1) {
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
      if (_highlight == _moreIndex) {
        widget.options.onMore?.call();
      } else {
        _choose(widget.options.options[_highlight]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _choose(LayoutOption o) async {
    if (o.id == _selected) {
      _emit();
      return;
    }
    setState(() => _selected = o.id);
    // The stage shows the new applied layout immediately; the write may
    // still be in flight, which is the same order the opener pages used
    // (setState, then await the setter).
    _emit();
    await widget.options.apply(o.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final spotlight = app.id == 'spotlight';
    final lit = _focused || _hoveredRow;
    final radius = app.shape.br(12);
    final applied = _applied;
    // The blurb follows the eye: hovered / highlighted option, else applied.
    final described = _eyeOn ?? applied;
    final onMore = _focused && _highlight == _moreIndex;
    final blurb = onMore
        ? 'More options'
        : described?.blurb ?? widget.options.labelOf(_selected);

    return Focus(
      focusNode: _node,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredRow = true),
        onExit: (_) => setState(() => _hoveredRow = false),
        child: Container(
          decoration: BoxDecoration(
            color: lit ? t.panel2 : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: _focused ? t.accent : Colors.transparent,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (spotlight)
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: app.fade(app.core.tx, 0.055),
                    borderRadius: app.shape.br(10),
                  ),
                  child: Icon(
                    widget.icon,
                    color: lit ? t.accent2 : t.dim,
                    size: 20,
                  ),
                )
              else
                SizedBox(
                  width: 34,
                  child: Icon(
                    widget.icon,
                    color: lit ? t.accent2 : t.dim,
                    size: 22,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: spotlight
                            ? app.core.tx
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Always two lines tall: the blurb changes under the
                    // pointer, and a one-line blurb replacing a two-line one
                    // would pull the chips up from under the cursor — an exit
                    // event, and the preview would flicker back.
                    SizedBox(
                      height: MediaQuery.textScalerOf(context).scale(30),
                      child: Text(
                        blurb,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: t.dim,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _singleRow
                        ? TvChipRow(
                            key: _rowKey,
                            itemCount: _stripLength,
                            itemBuilder: (context, i) => _stripItem(i),
                            highlightedIndex: _focused ? _highlight : null,
                          )
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < _stripLength; i++)
                                _stripItem(i),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One chip in the strip, by index — an option chip, or (at [_moreIndex])
  /// the trailing "More" chip. Shared by both the TV single row and the
  /// pointer surfaces' Wrap.
  Widget _stripItem(int i) {
    if (i == _moreIndex) {
      return SettingsOptionChip(
        label: widget.options.moreLabel!,
        active: false,
        highlighted: _focused && _highlight == _moreIndex,
        trailing: Icons.chevron_right_rounded,
        onEnter: () {},
        onExit: () {},
        onTap: () {
          setState(() => _highlight = _moreIndex);
          widget.options.onMore!();
        },
      );
    }
    return _chip(i, widget.options.options[i]);
  }

  Widget _chip(int i, LayoutOption o) {
    return SettingsOptionChip(
      label: o.label,
      tooltip: o.blurb,
      active: o.id == _selected,
      highlighted: _focused && i == _highlight,
      onEnter: () {
        _hoverChip = i;
        _emit();
      },
      onExit: () {
        if (_hoverChip == i) _hoverChip = null;
        _emit();
      },
      onTap: () {
        // A tap also moves the keyboard highlight, so a later OK re-applies
        // what was just chosen rather than a stale chip.
        setState(() => _highlight = i);
        _choose(o);
      },
    );
  }
}

/// One option chip. Same anatomy as the look strip's chips (minus the
/// swatch) so the two strips read as one control family.
class SettingsOptionChip extends StatelessWidget {
  const SettingsOptionChip({
    super.key,
    required this.label,
    required this.active,
    required this.highlighted,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
    this.tooltip,
    this.trailing,
  });

  final String label;

  /// The option's blurb, exposed to assistive tech as the chip's hint.
  final String? tooltip;
  final bool active;
  final bool highlighted;
  final IconData? trailing;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

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
    final Widget chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
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
          Flexible(
            child: Text(
              label,
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
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: 14, color: lit ? app.core.tx : t.dim),
          ],
        ],
      ),
    );
    // No Tooltip: the row's blurb line already follows the pointed chip, and
    // a tooltip's show timer would leave the settings widget tests with a
    // pending timer after every hover.
    return Semantics(
      button: true,
      selected: active,
      label: label,
      hint: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: chip,
        ),
      ),
    );
  }
}
