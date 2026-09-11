import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Starts uncached artwork after its owning viewport settles. A horizontal
/// shelf's nearest Scrollable cannot see the enclosing vertical movement.
/// Existing/pending decoded-cache entries mount immediately, and an image that
/// has already started is never removed when movement resumes.
class ScrollDeferredImage extends StatefulWidget {
  const ScrollDeferredImage({
    super.key,
    required this.scrolling,
    required this.image,
    required this.placeholder,
    required this.child,
  });
  final ValueListenable<bool> scrolling;
  final ImageProvider image;
  final Widget placeholder, child;

  @override
  State<ScrollDeferredImage> createState() => _ScrollDeferredImageState();
}

class _ScrollDeferredImageState extends State<ScrollDeferredImage> {
  bool _released = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.scrolling.addListener(_scrollChanged);
    _checkCache();
  }

  void _checkCache() {
    final generation = ++_generation;
    _released = !widget.scrolling.value;
    if (_released) return;
    var synchronous = true;
    widget.image
        .obtainKey(ImageConfiguration.empty)
        .then(
          (key) {
            if (!mounted || generation != _generation || _released) return;
            final status = PaintingBinding.instance.imageCache.statusForKey(
              key,
            );
            if (!status.keepAlive && !status.live && !status.pending) return;
            if (synchronous) {
              _released = true;
            } else {
              setState(() => _released = true);
            }
          },
          onError: (Object _, StackTrace __) {
            // The real image widget handles provider errors once scrolling settles.
          },
        );
    synchronous = false;
  }

  void _scrollChanged() {
    if (!_released && !widget.scrolling.value) {
      setState(() => _released = true);
    }
  }

  @override
  void didUpdateWidget(ScrollDeferredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrolling != widget.scrolling) {
      oldWidget.scrolling.removeListener(_scrollChanged);
      widget.scrolling.addListener(_scrollChanged);
    }
    if (oldWidget.image != widget.image) {
      _checkCache();
    } else if (!widget.scrolling.value) {
      _released = true;
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.scrolling.removeListener(_scrollChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _released ? widget.child : widget.placeholder;
}
