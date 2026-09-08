import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';

/// The focusable/tappable strip that opens a collection rail's full catalog
/// browse (or, for the folder's "All" row, switches to the merged grid).
///
/// Wraps the whole header — title plus its tag pill — rather than a separate
/// "See all ›" pill: the affordance used to be a small link at the header's
/// right edge, but collection rows no longer carry that label anywhere
/// (folder screen or Home). The row itself is still openable; only the
/// visible chrome is gone. TV renders a focus highlight around the whole
/// header and doubles it as the DPAD rung between rails (up to the rail
/// above, down into this rail's own cards); elsewhere it's a plain tap
/// target with no special styling until hovered.
class RailHeaderFocus extends StatefulWidget {
  final FocusNode node;
  final bool isTelevision;
  final VoidCallback onPressed;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onFocused;
  final Widget child;

  const RailHeaderFocus({
    super.key,
    required this.node,
    required this.isTelevision,
    required this.onPressed,
    required this.onUp,
    required this.onDown,
    required this.onFocused,
    required this.child,
  });

  @override
  State<RailHeaderFocus> createState() => _RailHeaderFocusState();
}

class _RailHeaderFocusState extends State<RailHeaderFocus> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.node.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant RailHeaderFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      oldWidget.node.removeListener(_onFocusChange);
      widget.node.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.node.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final focused = widget.node.hasFocus;
    if (focused == _focused) return;
    setState(() => _focused = focused);
    if (focused) widget.onFocused();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onDown();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      // Nothing beside the header — swallow so focus can't wander off-screen.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Focus(
      focusNode: widget.node,
      onKeyEvent: _onKey,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: app.shape.br(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: app.shape.br(9),
            color: _focused ? app.fade(app.core.tx, 0.10) : Colors.transparent,
            border: Border.all(
              color: _focused ? app.seeAll.accentBorder : Colors.transparent,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
