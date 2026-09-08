import 'package:flutter/widgets.dart';

import '../../../theme/app_motion.dart';

/// One horizontal, scrolling row of chips that keeps [highlightedIndex] on
/// screen as it moves — the TV alternative to `Wrap`.
///
/// Left/Right is the only way a D-pad walks a strip, so a wrapped second row
/// is unreachable; this is shared by the Appearance Look strip and every
/// inline Screen-layouts row so a highlight-follow fix lands once for both
/// (see PR #270, which first fixed this for the Look strip, and the Details
/// Page row's 11 chips wrapping into an unreachable second row on the
/// Shield). Pointer surfaces keep `Wrap` instead of this widget entirely.
class TvChipRow extends StatefulWidget {
  const TvChipRow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.highlightedIndex,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Index Left/Right is on, or null while the row has neither focus nor
  /// hover — nothing to keep visible.
  final int? highlightedIndex;

  @override
  State<TvChipRow> createState() => TvChipRowState();
}

class TvChipRowState extends State<TvChipRow> {
  final ScrollController scroll = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  List<GlobalKey> _chipKeys = const [];

  void _syncChipKeys() {
    if (_chipKeys.length != widget.itemCount) {
      _chipKeys = List.generate(widget.itemCount, (_) => GlobalKey());
    }
  }

  @override
  void didUpdateWidget(covariant TvChipRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedIndex != widget.highlightedIndex ||
        oldWidget.itemCount != widget.itemCount) {
      keepVisible();
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// Scrolls (horizontally only) so the highlighted chip is fully on screen,
  /// with a little breathing room. Public so a parent can call it right after
  /// a focus change lands, before this widget's own [didUpdateWidget] would
  /// otherwise fire on the next build.
  void keepVisible() {
    final target = widget.highlightedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      if (target == null || target < 0 || target >= _chipKeys.length) return;
      final chip = _chipKeys[target].currentContext?.findRenderObject();
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (chip is! RenderBox || viewport is! RenderBox) return;
      const pad = 12.0;
      final visibleLeft = chip
          .localToGlobal(Offset.zero, ancestor: viewport)
          .dx;
      final left = visibleLeft + scroll.offset;
      final right = left + chip.size.width;
      final extent = viewport.size.width;
      var offsetTarget = scroll.offset;
      if (left - pad < scroll.offset) {
        offsetTarget = left - pad;
      } else if (right + pad > scroll.offset + extent) {
        offsetTarget = right + pad - extent;
      }
      offsetTarget = offsetTarget.clamp(0.0, scroll.position.maxScrollExtent);
      if (offsetTarget == scroll.offset) return;
      final motion = AppMotion.of(context);
      scroll.animateTo(
        offsetTarget,
        duration: motion.scaled(const Duration(milliseconds: 160)),
        curve: motion.standard,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncChipKeys();
    return SingleChildScrollView(
      key: _viewportKey,
      controller: scroll,
      scrollDirection: Axis.horizontal,
      // Clip at the row's own bounds: with Clip.none the off-screen chips
      // would paint straight across the host's padding and border.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.itemCount; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            KeyedSubtree(
              key: _chipKeys[i],
              child: widget.itemBuilder(context, i),
            ),
          ],
        ],
      ),
    );
  }
}
