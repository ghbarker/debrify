import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../../services/imdb_person_service.dart';
import '../../services/watched_filter.dart';
import '../../theme/app_motion.dart';
import '../../theme/widgets/hover_grow.dart';
import '../../utils/platform_util.dart';
import 'detail_rail_cards.dart';
import 'detail_style.dart';
import 'theme/detail_theme.dart';

/// Resolves a cast member's IMDb name id to their known-for titles.
/// Injected so widget tests never reach the network.
typedef ActorTitlesLoader = Future<ImdbPerson?> Function(String nameId);

/// The page a cast tile opens: the actor's photo and name over a "Known for"
/// grid of the titles IMDb lists them for.
///
/// Titles are opened through [onOpenTitle] — the same opener the detail
/// page's "More Like This" uses — so an actor's film lands on exactly the
/// detail page a recommendation would. The screen that owns the detail page
/// pushes this via [show]; the widget itself never imports a screen.
class ActorTitlesView extends StatefulWidget {
  final CastMember member;
  final void Function(StremioMeta) onOpenTitle;
  final ActorTitlesLoader loader;
  final bool isTelevision;

  const ActorTitlesView({
    super.key,
    required this.member,
    required this.onOpenTitle,
    this.loader = ImdbPersonService.fetchKnownFor,
    this.isTelevision = false,
  });

  /// Push the actor page. [theme] is the detail theme of the page underneath:
  /// inherited widgets do not cross routes, so a themed layout passes it
  /// explicitly and Classic passes none (Signal). [routeName] lets the host
  /// mark the route the way it marks its own detail routes, so "pop to host"
  /// tears this page down along with them.
  static Future<void> show(
    BuildContext context, {
    required CastMember member,
    required void Function(StremioMeta) onOpenTitle,
    DetailTheme? theme,
    bool isTelevision = false,
    String? routeName,
    ActorTitlesLoader loader = ImdbPersonService.fetchKnownFor,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: routeName),
        builder: (_) {
          final view = ActorTitlesView(
            member: member,
            onOpenTitle: onOpenTitle,
            loader: loader,
            isTelevision: isTelevision,
          );
          if (theme == null) return view;
          return DetailThemeScope(theme: theme, child: view);
        },
      ),
    );
  }

  @override
  State<ActorTitlesView> createState() => _ActorTitlesViewState();
}

/// One grid row: a 100-wide 2:3 poster plus its two caption lines.
const double _tileExtent = 196;
const double _rowGap = 14;

class _ActorTitlesViewState extends State<ActorTitlesView> {
  final FocusNode _backNode = FocusNode(debugLabel: 'actor-back');

  ImdbPerson? _person;
  List<StremioMeta> _titles = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _backNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.member.nameId;
    final person = id == null || id.isEmpty ? null : await widget.loader(id);
    if (!mounted) return;
    setState(() {
      _person = person;
      // Same "Hide watched titles" decider as the recommendations rail.
      _titles = WatchedFilter.apply(person?.knownFor ?? const []);
      _loading = false;
    });
    if (widget.isTelevision && _titles.isNotEmpty) {
      // Land the DPAD on the first poster rather than leaving it on the back
      // button, which is where the page had to park it while loading.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_backNode.hasFocus) return;
        FocusScope.of(context).focusInDirection(TraversalDirection.down);
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Classic and the legacy page push this unthemed, so the page provides
    // its own scope (Signal by default): the shared slab, ring and card
    // widgets below all resolve `DetailThemeScope.of`.
    final t = DetailThemeScope.maybeOf(context);
    final photo = _person?.imageUrl ?? widget.member.imageUrl;
    final name = (_person?.name.isNotEmpty ?? false)
        ? _person!.name
        : widget.member.name;
    return DetailThemeScope(
      theme: t,
      child: Focus(
        // A key handler only. It must not be a focus target itself: a
        // traversable node whose rect is the whole page sits in every row's
        // horizontal band, so RIGHT past the end of a short bottom row (no
        // poster to the right; the vertical grid gives the directional
        // policy no same-scrollable filter for LEFT/RIGHT) used to land the
        // DPAD here — nothing highlighted, and from a node covering the
        // screen no direction has a candidate. Key events still bubble up to
        // an ancestor that cannot hold focus.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: t.ground,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      _BackButton(
                        node: _backNode,
                        autofocus: widget.isTelevision,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 14),
                      _Portrait(url: photo, size: 72),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleStyle(
                                size: 24,
                                weight: FontWeight.w700,
                                tracking: -0.3,
                              ),
                            ),
                            if ((widget.member.character ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'as ${widget.member.character}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: t.tx2, fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: const DetailSlab('Known for'),
                ),
                Expanded(child: _body(t)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(DetailTheme t) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: t.focus),
        ),
      );
    }
    if (_titles.isEmpty) {
      final message = _person == null
          ? 'Could not load titles for ${widget.member.name}.'
          : 'No titles found for ${widget.member.name}.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.tx2, fontSize: 14),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      // Directional focus search only sees mounted nodes, and the tile's
      // follow-focus scroll can only target a built row: keep two rows either
      // side of the viewport alive so a DPAD step always has its neighbour.
      scrollCacheExtent: const ScrollCacheExtent.pixels(
        2 * (_tileExtent + _rowGap),
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 124,
        mainAxisExtent: _tileExtent,
        crossAxisSpacing: 12,
        mainAxisSpacing: _rowGap,
      ),
      itemCount: _titles.length,
      itemBuilder: (context, i) => _TitleTile(
        key: ValueKey('actor-title-${_titles[i].id}'),
        item: _titles[i],
        isTelevision: widget.isTelevision,
        onTap: () => widget.onOpenTitle(_titles[i]),
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  final FocusNode node;
  final bool autofocus;
  final VoidCallback onTap;
  const _BackButton({
    required this.node,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.maybeOf(context);
    return DetailFocusRing(
      focused: _f,
      radius: t.brBtn,
      child: Material(
        color: t.panel,
        borderRadius: t.brBtn,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: widget.node,
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _f = f),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.arrow_back_rounded, size: 22, color: t.tx),
          ),
        ),
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  final String? url;
  final double size;
  const _Portrait({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.maybeOf(context);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url != null && url!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                cacheManager: DebrifyImageCache.manager,
                memCacheWidth: 260,
                placeholder: (_, __) => ColoredBox(color: t.placeholder),
                errorWidget: (_, __, ___) => ColoredBox(color: t.placeholder),
              )
            : ColoredBox(
                color: t.placeholder,
                child: Icon(Icons.person, color: t.tx3, size: size * 0.55),
              ),
      ),
    );
  }
}

/// One known-for title: the classic rail's [DetailRecCard] with a caption,
/// lifted by [HoverGrow] while focused or hovered.
class _TitleTile extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final VoidCallback onTap;
  const _TitleTile({
    super.key,
    required this.item,
    required this.isTelevision,
    required this.onTap,
  });

  @override
  State<_TitleTile> createState() => _TitleTileState();
}

class _TitleTileState extends State<_TitleTile> {
  bool _f = false;
  bool _h = false;

  // The tempo of the follow-focus scroll, resolved in build (never in the
  // focus callback: that is an inherited lookup outside build) — see the
  // rules on [AppMotion].
  Duration _followDuration = Duration.zero;
  Curve _followCurve = Curves.easeOutCubic;

  void _onFocusChange(bool f) {
    setState(() => _f = f);
    if (!f) return;
    // Keep the focused tile — caption included — inside the grid. The
    // framework's own traversal scroll only drags the poster's bottom edge
    // to the viewport edge, which clips the caption and leaves the next row
    // unbuilt. Deferred a frame so it wins over that scroll and measures a
    // settled layout; nearest scrollable only, so nothing above the grid
    // moves.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final grid = Scrollable.maybeOf(context);
      final box = context.findRenderObject();
      if (grid == null || box is! RenderBox || !box.attached) return;
      grid.position.ensureVisible(
        box,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: _followDuration,
        curve: _followCurve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.maybeOf(context);
    final motion = AppMotion.of(context);
    _followDuration = motion.scaled(const Duration(milliseconds: 160));
    _followCurve = motion.standard;
    final item = widget.item;
    final tv = widget.isTelevision || PlatformUtil.isTelevision;
    final year = item.year;
    final label = item.type == 'series' ? 'Series' : 'Movie';
    final sub = year == null || year.isEmpty ? label : '$year · $label';
    return Focus(
      // Not a focus target itself — the card's InkWell is — but an ancestor
      // sees the descendant's focus, which is what drives the lift.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: MouseRegion(
        onEnter: tv ? null : (_) => setState(() => _h = true),
        onExit: tv ? null : (_) => setState(() => _h = false),
        child: HoverGrow(
          active: _f || _h,
          isTelevision: tv,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailRecCard(
                rec: item,
                fallback: t.placeholder,
                onTap: widget.onTap,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 100,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _f ? t.tx : t.tx2,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.tx3, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
