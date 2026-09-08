import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';

/// The focusable strip that doubles as the DPAD rung between rails (up to
/// the rail above, down into this rail's own cards) — and, when [onPressed]
/// is given, is also tappable/selectable (the folder's "All" row uses this
/// to switch to the merged grid). A plain list title passes no [onPressed]:
/// on TV a row's name is a label, exactly like Home's own row names, not a
/// control that opens something.
///
/// TV renders a focus highlight around the whole header while it holds the
/// DPAD rung, whether or not it's pressable; elsewhere it's a plain tap
/// target (or, with no [onPressed], not a tap target at all) with no special
/// styling until hovered.
class RailHeaderFocus extends StatefulWidget {
  final FocusNode node;
  final bool isTelevision;
  final VoidCallback? onPressed;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onFocused;
  final Widget child;

  const RailHeaderFocus({
    super.key,
    required this.node,
    required this.isTelevision,
    this.onPressed,
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
    final onPressed = widget.onPressed;
    if (onPressed != null &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA)) {
      onPressed();
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
        // Null makes InkWell paint disabled (no ink, no cursor) — exactly
        // "not a control", same as Home's own row-name label.
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
