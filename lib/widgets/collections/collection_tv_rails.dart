import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../models/metadata_preferences.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/ui_frame_diagnostics.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/home_rail_metrics.dart';
import '../../utils/tv_keys.dart';
import '../home/card_focus_rise.dart';
import '../metadata_presentation_mixin.dart';

class CollectionTvRail {
  const CollectionTvRail({
    required this.id,
    required this.title,
    required this.items,
    required this.loading,
    required this.onLoadMore,
  });
  final String id, title;
  final List<StremioMeta> items;
  final bool loading;
  final VoidCallback onLoadMore;
}

/// TV title shelves. Headers are labels; only cards take content focus.
/// This owner moves the vertical viewport, each row moves only horizontally.
class CollectionTvRails extends StatefulWidget {
  const CollectionTvRails({
    super.key,
    required this.rails,
    required this.landscapeCards,
    this.showCardIdentity = true,
    required this.onOpen,
    required this.onExitTop,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
  });
  final List<CollectionTvRail> rails;
  final bool landscapeCards;
  final bool showCardIdentity;
  final ValueChanged<StremioMeta> onOpen;
  final ValueChanged<StremioMeta>? onQuickPlay, onItemFocused;
  final VoidCallback onExitTop;
  final bool Function(StremioMeta)? isBound;

  @override
  State<CollectionTvRails> createState() => CollectionTvRailsState();
}

class _RowFocus {
  final scroll = ScrollController();
  final nodes = <String, FocusNode>{};
  double? target;
  FocusNode node(StremioMeta item) => nodes.putIfAbsent(
    '${item.type}:${item.id}',
    () => FocusNode(debugLabel: 'collection_title_${item.id}'),
  );
  void dispose() {
    scroll.dispose();
    for (final node in nodes.values) {
      node.dispose();
    }
  }
}

class CollectionTvRailsState extends State<CollectionTvRails> {
  final _vertical = _RailScrollController();
  final _navigationFocus = FocusNode(
    debugLabel: 'collection_rails_navigation',
    skipTraversal: true,
  );
  final _rows = <String, _RowFocus>{};
  int _row = 0, _column = 0, _generation = 0;
  bool _waitingForItems = false;
  FocusNode? _waitingFrom;
  void _clearWaiting() {
    _waitingFrom?.removeListener(_entryFocusChanged);
    _waitingFrom = null;
    _waitingForItems = false;
  }

  void _entryFocusChanged() {
    if (_waitingFrom?.hasFocus != true) _clearWaiting();
  }

  double _extent = 0;
  double? _verticalTarget;
  Size _card = Size.zero;
  Duration _duration = Duration.zero;
  Timer? _hold;
  ({String rail, StremioMeta item, LogicalKeyboardKey key})? _pressed;
  bool _holdFired = false;

  void _cancelPress() {
    _hold?.cancel();
    _hold = null;
    _pressed = null;
    _holdFired = false;
  }

  bool get _pressIsCurrent {
    final pressed = _pressed;
    if (pressed == null || _row >= widget.rails.length) return false;
    final rail = widget.rails[_row];
    return rail.id == pressed.rail &&
        _column < rail.items.length &&
        rail.items[_column].id == pressed.item.id &&
        rail.items[_column].type == pressed.item.type;
  }

  KeyEventResult _activate(KeyEvent event) {
    // Direction repeats may select a destination before its card is mounted.
    // Neither a short press nor a hold may act on that unfocused destination.
    if (!_owner(_row).node(widget.rails[_row].items[_column]).hasFocus) {
      _cancelPress();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && _pressed == null) {
      final rail = widget.rails[_row];
      _pressed = (
        rail: rail.id,
        item: rail.items[_column],
        key: event.logicalKey,
      );
      _holdFired = false;
      if (widget.onQuickPlay != null) {
        _hold = Timer(const Duration(milliseconds: 800), () {
          if (!mounted ||
              !_pressIsCurrent ||
              ModalRoute.of(context)?.isCurrent == false ||
              !_owner(_row).node(widget.rails[_row].items[_column]).hasFocus) {
            return;
          }
          _holdFired = true;
          widget.onQuickPlay!(widget.rails[_row].items[_column]);
        });
      }
    } else if (event is KeyUpEvent && event.logicalKey == _pressed?.key) {
      final open = _pressIsCurrent && !_holdFired;
      _cancelPress();
      if (open) widget.onOpen(widget.rails[_row].items[_column]);
    }
    return KeyEventResult.handled;
  }

  _RowFocus _owner(int row) =>
      _rows.putIfAbsent(widget.rails[row].id, _RowFocus.new);

  @override
  void initState() {
    super.initState();
    if (UiFrameDiagnostics.instance.enabled) {
      _vertical.addListener(_recordScrollPosition);
    }
  }

  void _recordScrollPosition() {
    if (_vertical.hasClients) {
      UiFrameDiagnostics.instance.navigation(
        2,
        _row,
        _vertical.offset,
        _verticalTarget ?? 0,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Collections retain their existing glide. The Smooth/Snappy preference
    // controls Spotlight Home, not this surface; accessibility still wins.
    _duration = AppMotion.of(context).reduced
        ? Duration.zero
        : const Duration(milliseconds: 260);
  }

  @override
  void didUpdateWidget(CollectionTvRails oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Late watched/identity updates can remove a card without replacing the
    // rail. Preserve the selected identity, or focus its surviving neighbour.
    final hadFocus = _rows.values.any(
      (r) => r.nodes.values.any((n) => n.hasFocus),
    );
    if (_row < oldWidget.rails.length) {
      final old = oldWidget.rails[_row];
      final item = _column < old.items.length ? old.items[_column] : null;
      final nextRow = widget.rails.indexWhere((r) => r.id == old.id);
      if (nextRow >= 0) {
        _row = nextRow;
        final nextItems = widget.rails[_row].items;
        final nextColumn = nextItems.indexWhere(
          (m) => m.id == item?.id && m.type == item?.type,
        );
        _column = nextColumn >= 0
            ? nextColumn
            : _column.clamp(0, nextItems.isEmpty ? 0 : nextItems.length - 1);
        if (hadFocus && nextColumn < 0) {
          final generation = ++_generation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                generation == _generation &&
                ModalRoute.of(context)?.isCurrent != false) {
              focusFirst();
            }
          });
        }
      }
    }
    final ids = widget.rails.map((r) => r.id).toSet();
    if (!_pressIsCurrent) _cancelPress();
    for (final id in _rows.keys.where((id) => !ids.contains(id)).toList()) {
      _rows.remove(id)!.dispose();
    }
    if (_waitingForItems && widget.rails.any((r) => r.items.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _waitingForItems &&
            ModalRoute.of(context)?.isCurrent != false) {
          focusFirst();
        }
      });
    }
  }

  @override
  void dispose() {
    ++_generation;
    _cancelPress();
    _clearWaiting();
    _vertical.removeListener(_recordScrollPosition);
    _vertical.dispose();
    _navigationFocus.dispose();
    for (final row in _rows.values) {
      row.dispose();
    }
    super.dispose();
  }

  void focusFirst() {
    final row = widget.rails.indexWhere((r) => r.items.isNotEmpty);
    _clearWaiting();
    if (row < 0) {
      _waitingForItems = true;
      _waitingFrom = FocusManager.instance.primaryFocus;
      _waitingFrom?.addListener(_entryFocusChanged);
      return;
    }
    final remembered =
        _row < widget.rails.length && widget.rails[_row].items.isNotEmpty;
    _focus(remembered ? _row : row, remembered ? _column : 0);
  }

  double _offset(
    ScrollController scroll,
    double top,
    double bottom,
    double? previous,
  ) {
    final position = scroll.position;
    final start = previous ?? position.pixels;
    return (top < start
            ? top
            : bottom > start + position.viewportDimension
            ? bottom - position.viewportDimension
            : start)
        .clamp(0.0, position.maxScrollExtent);
  }

  void _move(ScrollController scroll, double target, {required bool jump}) {
    if (jump || _duration == Duration.zero) {
      scroll.jumpTo(target);
    } else {
      unawaited(
        scroll.animateTo(
          target,
          duration: _duration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _focus(int row, int column) {
    if (row < 0 || row >= widget.rails.length) return;
    final rail = widget.rails[row];
    if (rail.items.isEmpty) return;
    _cancelPress();
    _clearWaiting();
    _row = row;
    _column = column.clamp(0, rail.items.length - 1);
    final item = rail.items[_column];
    final owner = _owner(row);
    final node = owner.node(item);
    final generation = ++_generation;
    if (!owner.scroll.hasClients) {
      // The old card may be recycled before the destination mounts. Keep
      // remote repeats and reversal on this stable ancestor in the meantime.
      _navigationFocus.requestFocus();
    }
    // Offscreen destinations mount along the glide before receiving focus.
    // Rapid presses replace the target and invalidate pending focus callbacks.
    if (_vertical.hasClients) {
      final target = _offset(
        _vertical,
        row * _extent,
        (row + 1) * _extent,
        _verticalTarget,
      );
      UiFrameDiagnostics.instance.navigation(0, row, _vertical.offset, target);
      if (target != _verticalTarget || !owner.scroll.hasClients) {
        _verticalTarget = target;
        // Row recycling must not turn an animated traversal into a jump.
        _move(_vertical, target, jump: false);
      }
    }
    void finish() {
      if (!mounted ||
          generation != _generation ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (!owner.scroll.hasClients) {
        // Stop retrying if scrolling was interrupted before the row mounted.
        if (_vertical.hasClients &&
            _vertical.position.isScrollingNotifier.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) => finish());
          WidgetsBinding.instance.ensureVisualUpdate();
        }
        return;
      }
      if (owner.scroll.hasClients) {
        final top = 13 + _column * (_card.width + 22);
        final target = _offset(
          owner.scroll,
          top,
          top + _card.width + 22,
          owner.target,
        );
        if (target != owner.target || node.context == null) {
          owner.target = target;
          _move(owner.scroll, target, jump: node.context == null);
        }
      }
      if (node.context != null) {
        UiFrameDiagnostics.instance.navigation(
          1,
          row,
          _vertical.hasClients ? _vertical.offset : 0,
          _verticalTarget ?? 0,
        );
        node.requestFocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              generation == _generation &&
              node.context != null &&
              ModalRoute.of(context)?.isCurrent != false) {
            UiFrameDiagnostics.instance.navigation(
              1,
              row,
              _vertical.hasClients ? _vertical.offset : 0,
              _verticalTarget ?? 0,
            );
            node.requestFocus();
          }
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }

    if (owner.scroll.hasClients) {
      finish();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => finish());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  KeyEventResult _key(KeyEvent event) {
    if (_row >= widget.rails.length ||
        _column >= widget.rails[_row].items.length) {
      return KeyEventResult.handled;
    }
    if (isActivateOrSpaceKey(event.logicalKey)) return _activate(event);
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final next = _column + (key == LogicalKeyboardKey.arrowRight ? 1 : -1);
      final rail = widget.rails[_row];
      _focus(_row, next);
      if (next >= rail.items.length - 3) rail.onLoadMore();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final direction = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      var next = _row + direction;
      while (next >= 0 &&
          next < widget.rails.length &&
          widget.rails[next].items.isEmpty) {
        next += direction;
      }
      if (next < 0) {
        ++_generation;
        _cancelPress();
        _clearWaiting();
        widget.onExitTop();
      } else if (next < widget.rails.length) {
        _focus(next, _column);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _card = classicRailCardSize(
      context,
      isTelevision: true,
      landscapeCards: widget.landscapeCards,
    );
    final headerHeight = MediaQuery.textScalerOf(context).scale(18) * 1.4;
    _extent = _card.height + 30 + headerHeight;
    final app = AppThemeScope.of(context);
    final rails = ListView.builder(
      controller: _vertical,
      itemExtent: _extent,
      scrollCacheExtent: ScrollCacheExtent.pixels(_extent * 2),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: widget.rails.length,
      itemBuilder: (context, row) {
        final rail = widget.rails[row];
        final owner = _owner(row);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: SizedBox(
                height: headerHeight,
                child: Text(
                  rail.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: app.core.tx,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _card.height + 14,
              child: rail.items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        rail.loading ? 'Loading…' : 'No titles',
                        style: TextStyle(color: app.fade(app.core.tx, .6)),
                      ),
                    )
                  : ListView.builder(
                      controller: owner.scroll,
                      scrollDirection: Axis.horizontal,
                      itemExtent: _card.width + 22,
                      scrollCacheExtent: ScrollCacheExtent.pixels(
                        (_card.width + 22) * 2,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      itemCount: rail.items.length,
                      itemBuilder: (context, column) {
                        final item = rail.items[column];
                        final node = owner.node(item);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 11),
                          child: Center(
                            child: SizedBox(
                              key: ValueKey(
                                'collection_card_${rail.id}_${item.id}',
                              ),
                              width: _card.width,
                              height: _card.height,
                              child: Focus(
                                focusNode: node,
                                onKeyEvent: (_, event) => _key(event),
                                onFocusChange: (focused) {
                                  if (focused) {
                                    UiFrameDiagnostics.instance.navigation(
                                      3,
                                      row,
                                      _vertical.hasClients
                                          ? _vertical.offset
                                          : 0,
                                      _verticalTarget ?? 0,
                                    );
                                    _row = row;
                                    _column = column;
                                    widget.onItemFocused?.call(item);
                                  } else if (_pressed?.item.id == item.id) {
                                    _cancelPress();
                                  }
                                },
                                child: GestureDetector(
                                  onTap: () => widget.onOpen(item),
                                  onLongPress: widget.onQuickPlay == null
                                      ? null
                                      : () => widget.onQuickPlay!(item),
                                  child: ListenableBuilder(
                                    listenable: node,
                                    builder: (_, child) => Semantics(
                                      button: true,
                                      child: CardFocusRise(
                                        active: node.hasFocus,
                                        isTelevision: true,
                                        aspectRatio: _card.aspectRatio,
                                        children: [
                                          child!,
                                          if (widget.isBound?.call(item) ??
                                              false)
                                            const Positioned(
                                              right: 5,
                                              top: 5,
                                              child: Icon(
                                                Icons.bookmark,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    child: _RailArtwork(
                                      item: item,
                                      wide: widget.landscapeCards,
                                      showIdentity: widget.showCardIdentity,
                                      decodeWidth:
                                          (_card.width *
                                                  MediaQuery.devicePixelRatioOf(
                                                    context,
                                                  ) *
                                                  1.1)
                                              .ceil()
                                              .clamp(1, 1280),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
    return Focus(
      focusNode: _navigationFocus,
      onKeyEvent: (_, event) => _key(event),
      child: rails,
    );
  }
}

// Only Collection's vertical viewport retargets this way. Horizontal reveals
// retain their existing controller and mounted-column behavior.
class _RailScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _RailScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _RailScrollPosition extends ScrollPositionWithSingleContext {
  _RailScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  (double, double, double)? _dimensions;

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    final target = to.clamp(minScrollExtent, maxScrollExtent);
    final current = activity;
    if (current is _RailScrollActivity && !current.motion.finished) {
      if (current.motion.target != target) {
        current.motion.retarget(
          pixels,
          current.velocity,
          target,
          duration,
          minScrollExtent,
          maxScrollExtent,
        );
      }
      return current.done;
    }
    if ((target - pixels).abs() <= physics.toleranceFor(this).distance) {
      return super.animateTo(target, duration: duration, curve: curve);
    }
    final driven = _RailScrollActivity(
      this,
      _RailSimulation(pixels, target, duration, curve),
      context.vsync,
    );
    beginActivity(driven);
    return driven.done;
  }

  @override
  void applyNewDimensions() {
    super.applyNewDimensions();
    final dimensions = (minScrollExtent, maxScrollExtent, viewportDimension);
    if (_dimensions == dimensions) return;
    _dimensions = dimensions;
    final current = activity;
    if (current is _RailScrollActivity && !current.motion.finished) {
      final target = current.motion.target.clamp(
        minScrollExtent,
        maxScrollExtent,
      );
      // Even a still-valid target can lose its outgoing braking space when
      // content shrinks. Rebase against the new bounds without extending the
      // current deadline on pagination or viewport changes.
      current.motion.retarget(
        pixels,
        current.velocity,
        target,
        current.motion.remaining,
        minScrollExtent,
        maxScrollExtent,
      );
    }
  }
}

class _RailScrollActivity extends DrivenScrollActivity {
  _RailScrollActivity(
    ScrollActivityDelegate delegate,
    this.motion,
    TickerProvider vsync,
  ) : super.simulation(delegate, motion, vsync: vsync);

  final _RailSimulation motion;
}

/// The first leg is exactly the caller's curve. Retargets use a cubic Hermite
/// segment with the current position/velocity and zero arrival velocity. The
/// activity and its elapsed clock survive: no first-frame pause on each key.
class _RailSimulation extends Simulation {
  _RailSimulation(this._from, this.target, this.duration, this._curve)
    : _seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;

  double _from, target;
  Duration duration;
  final Curve _curve;
  double _seconds;
  double _time = 0, _epoch = 0, _velocity = 0;
  bool _retargeted = false;

  // A final pixel notification can request a new target before the completed
  // activity's asynchronous cleanup. Its ticker has already stopped then.
  bool get finished => isDone(_time);

  Duration get remaining => Duration(
    microseconds:
        ((_seconds - (_time - _epoch)) * Duration.microsecondsPerSecond)
            .ceil()
            .clamp(1, duration.inMicroseconds),
  );

  void retarget(
    double from,
    double velocity,
    double to,
    Duration nextDuration,
    double minimum,
    double maximum,
  ) {
    _from = from;
    target = to;
    duration = nextDuration;
    _epoch = _time;
    _seconds = nextDuration.inMicroseconds / Duration.microsecondsPerSecond;
    _velocity = velocity;
    _retargeted = true;
    final distance = to - from;
    if (velocity * distance > 0) {
      // A Hermite segment is monotone when v*T <= 3*distance.
      _seconds = _seconds.clamp(0.0, 3 * distance.abs() / velocity.abs());
    } else if (velocity != 0) {
      // On reversal, outgoing travel is at most 4*v*T/27. Limit that
      // braking excursion to the available space before the physical edge.
      final room = velocity > 0 ? maximum - from : from - minimum;
      if (room <= 0) {
        _velocity = 0;
      } else {
        _seconds = _seconds.clamp(0.0, 6 * room / velocity.abs());
      }
    }
  }

  double _value(double time) {
    final u = ((time - _epoch) / _seconds).clamp(0.0, 1.0);
    final distance = target - _from;
    if (!_retargeted) return _from + distance * _curve.transform(u);
    return _from +
        distance * u * u * (3 - 2 * u) +
        _velocity * _seconds * u * (1 - u) * (1 - u);
  }

  @override
  double x(double time) {
    _time = time;
    return _value(time);
  }

  @override
  double dx(double time) {
    if (time - _epoch >= _seconds) return 0;
    if (!_retargeted) {
      // Same numerical derivative convention as Flutter's curve simulation.
      return (_value(time + tolerance.time) - _value(time - tolerance.time)) /
          (2 * tolerance.time);
    }
    final u = ((time - _epoch) / _seconds).clamp(0.0, 1.0);
    return (target - _from) * 6 * u * (1 - u) / _seconds +
        _velocity * (1 - 4 * u + 3 * u * u);
  }

  @override
  bool isDone(double time) => time - _epoch > _seconds;
}

/// Same profile-aware metadata policy as the collection gallery, decoded for
/// a title card's physical width rather than a full gallery/hero backdrop.
class _RailArtwork extends StatefulWidget {
  const _RailArtwork({
    required this.item,
    required this.wide,
    required this.decodeWidth,
    required this.showIdentity,
  });
  final StremioMeta item;
  final bool wide, showIdentity;
  final int decodeWidth;
  @override
  State<_RailArtwork> createState() => _RailArtworkState();
}

class _RailArtworkState extends State<_RailArtwork>
    with MetadataPresentationMixin<_RailArtwork> {
  @override
  StremioMeta get originalMetadata => widget.item;

  @override
  Widget build(BuildContext context) {
    final category = widget.wide
        ? MetadataCategory.backgrounds
        : MetadataCategory.posters;
    final item = presentedMetadata!;
    final fallback =
        !usesMetadataProvider(category) || metadataPreferences.fallback
        ? item.poster
        : null;
    final url = metadataArtworkPending(category)
        ? null
        : widget.wide
        ? item.background ?? fallback
        : item.poster;
    const placeholder = ColoredBox(
      color: Color(0xFF1D1B2E),
      child: Center(child: Icon(Icons.image_outlined, color: Colors.white24)),
    );
    Widget image(String value, {bool retry = true}) => CachedNetworkImage(
      imageUrl: value,
      cacheManager: DebrifyImageCache.manager,
      memCacheWidth: widget.decodeWidth,
      fit: BoxFit.cover,
      fadeInDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      fadeInCurve: Curves.easeOut,
      // Only the arriving image fades; the default 1 s placeholder fade would
      // cover that short reveal and add another opacity layer to every card.
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => retry && fallback != null && fallback != value
          ? image(fallback, retry: false)
          : placeholder,
    );
    final rating = item.imdbRating;
    // These shelves have no hero to identify the focused title. Keep identity
    // inside the existing artwork bounds, including while artwork is pending.
    final artwork = Semantics(
      label: item.name,
      excludeSemantics: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          url == null || url.isEmpty ? placeholder : image(url),
          if (widget.showIdentity) ...[
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (rating != null && rating.isFinite && rating > 0)
                    Text(
                      '\u2605 ${rating.toStringAsFixed(1)}',
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
    // The surrounding focus scale/shadow animates every move. Keep the static
    // image and title layer reusable while that chrome repaints.
    return RepaintBoundary(child: artwork);
  }
}
