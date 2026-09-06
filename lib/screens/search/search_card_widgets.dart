part of '../search_screen.dart';

/// The "See All ›" affordance in a rail header — a mouse/tap entry to the
/// full-screen See-All screen, shown on desktop only. Kept understated (quiet
/// grey that brightens on hover, no accent fill) so it doesn't compete with the
/// posters. TV rails are chrome-free and paginate on scroll instead.
class _SeeAllLink extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _SeeAllLink({required this.onTap, this.compact = false});

  @override
  State<_SeeAllLink> createState() => _SeeAllLinkState();
}

class _SeeAllLinkState extends State<_SeeAllLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = _hover ? app.core.tx : app.fade(app.core.tx, 0.5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? app.fade(app.core.tx, 0.08) : Colors.transparent,
            borderRadius: app.shape.br(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.compact ? 'All' : 'See All',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 17, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// One opted-in IPTV custom list shown as a Home row. [channels] are rebuilt
/// from the stored list metadata alone (no provider fetch) with their full
/// presentation fields — a list can hold VOD alongside live channels, and the
/// content type drives both the play routing and whether focus retunes the
/// hero live preview. [nodes] are owned here and reconciled by [listId]
/// across reloads (see [_SearchScreenState._loadIptvListRows]).

/// Generic DPAD arrow-handling wrapper for a favourites-row card — the arrow
/// counterpart to [_BoardCell] for the IPTV / Debrify TV / Stremio TV rows.
/// Holds no focus itself — the inner [ArtPoster] does; this only routes
/// left/right within the row and up/down out of it, matching the catalog
/// cards' navigation exactly.
class FavArtCell extends StatelessWidget {
  final bool isTelevision;
  final int column;
  final List<FocusNode> rowNodes;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// Horizontal overrides — see [_BoardCell.onLeft]. Null keeps the row
  /// grammar.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  /// Held up/down — see [_BoardCell.onUpHold].
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;
  final Widget child;

  const FavArtCell({
    super.key,
    required this.isTelevision,
    required this.column,
    required this.rowNodes,
    required this.onUp,
    required this.onDown,
    this.onLeft,
    this.onRight,
    this.onUpHold,
    this.onDownHold,
    required this.child,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    // Act on key-down AND key-repeat (held DPAD). If we let a repeat fall
    // through as `ignored`, Flutter's default geometric traversal fires and
    // jumps focus into an adjacent row — so only key-ups are passed on.
    if (!isTelevision || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (onLeft != null) {
        onLeft!();
      } else if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (onRight != null) {
        onRight!();
      } else if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyRepeatEvent && onUpHold != null) {
        onUpHold!();
      } else {
        onUp();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && onDownHold != null) {
        onDownHold!();
      } else {
        onDown();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleArrows,
      child: child,
    );
  }
}

/// Stremio-shaped artwork card for a favourite that has a real image (a Stremio
/// TV channel's now-playing poster, or an IPTV channel's logo). Shows the image
/// over a purple gradient — with a live-TV glyph fallback when it's missing or
/// fails to load — and the title below, matching [_StremioCard]'s size, corner
/// radius, hover/focus lift and selection ring so the row reads as one board.
class ArtPoster extends StatefulWidget {
  final String? imageUrl;
  final String title;
  final bool showTitle;

  /// How the image fills the 2:3 tile — cover for posters, contain for logos.
  final BoxFit imageFit;

  /// Optional top-left badge text (e.g. a channel number) drawn over the tile.
  final String? badge;

  /// When true, a red "LIVE" pill is drawn top-right — signalling that this is a
  /// channel and the artwork is what's playing on it right now.
  final bool live;

  /// Optional resume-progress fraction (0..1). When set, a thin progress bar is
  /// drawn along the bottom edge of the poster (used by the Playlist row).
  final double? progress;
  final bool isTelevision;

  /// Focus ring override (Canvas favourites cells pass white); null keeps
  /// the classic violet-on-TV grammar.
  final Color? ringColor;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  /// Fired when this card gains DPAD focus (TV only — see [_ArtPosterState]'s
  /// `onFocusChange`). The IPTV favourites rows use it to retune the hero's
  /// video region (boxed on classic, full-bleed on Canvas) to the focused
  /// channel's live stream; other favourites rows pass a clearing/stage
  /// callback so a live feed never lingers when focus moves off IPTV without
  /// passing through a catalog/CW card first.
  final VoidCallback? onFocused;

  const ArtPoster({
    super.key,
    required this.imageUrl,
    required this.title,
    this.showTitle = true,
    required this.isTelevision,
    required this.focusNode,
    required this.onOpen,
    this.imageFit = BoxFit.cover,
    this.badge,
    this.live = false,
    this.progress,
    this.ringColor,
    this.onFocused,
  });

  @override
  State<ArtPoster> createState() => _ArtPosterState();
}

class _ArtPosterState extends State<ArtPoster> {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  Widget _glyph() {
    final app = AppThemeScope.of(context);
    return Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 40,
        color: app.fade(app.home.chromeAccent, _active ? 1 : 0.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final url = widget.imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    // Focus visuals (scale + shadow + ring on one curve) live in the shared
    // [CardFocusRise] so tuning lands once for every board card.
    final posterCard = CardFocusRise(
      active: _active,
      isTelevision: widget.isTelevision,
      ringColor: widget.ringColor,
      children: [
        // Base gradient — the fallback backdrop and the ground behind
        // any letterboxed (contain-fit) logo.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A1D5C), Color(0xFF1A1440), Color(0xFF0D0B1A)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (hasImage)
          Padding(
            padding: widget.imageFit == BoxFit.contain
                ? const EdgeInsets.all(12)
                : EdgeInsets.zero,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: widget.imageFit,
              memCacheWidth: widget.isTelevision ? 320 : 480,
              // Short fade on TV (see HomeTheme.imageFadeIn) — cached loads
              // land settled with no fade.
              fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
              fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
              placeholder: (_, __) => _glyph(),
              errorWidget: (_, __, ___) => _glyph(),
            ),
          )
        else
          _glyph(),
        // Optional channel-number badge, top-left.
        if (widget.badge != null)
          Positioned(
            top: 10,
            left: 10,
            child: Text(
              widget.badge!,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        // "LIVE" pill, top-right — marks this as a channel currently
        // playing the shown artwork.
        if (widget.live)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: app.shape.br(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _kCwProgressRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Resume-progress bar along the bottom edge (Playlist row).
        if (widget.progress != null && widget.progress! > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: Colors.black.withValues(alpha: 0.4)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.progress!,
                    child: Container(color: _kCwProgressRed),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _keyDown = false;
        if (f) {
          widget.onFocused?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // TV glides too (was a hard jump) — see _StremioCard: repeated
              // DPAD moves retarget the in-flight scroll, so held browsing
              // stays one continuous motion. Short on purpose; 200ms trailed
              // the keypress on-device.
              duration: widget.isTelevision
                  ? const Duration(milliseconds: 140)
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              posterCard,
              if (widget.showTitle) ...[
                const SizedBox(height: _kArtTitleGap),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: _kArtTitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _active ? app.core.tx : app.fade(app.core.tx, 0.92),
                    fontSize: _kArtTitleFontSize,
                    fontWeight: FontWeight.w600,
                    height: _kArtTitleHeight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Catalog / Keyword / Lists mode selector.
class _ModeToggle extends StatelessWidget {
  final SearchBoardMode mode;
  final bool isTelevision;
  final bool listsAvailable;

  /// When true the two segments split the full available width (used when the
  /// toggle is stacked below the search box on narrow screens).
  final bool fullWidth;
  final ValueChanged<SearchBoardMode> onChanged;

  /// TV-only DPAD focus nodes for the segments (null off-TV, where the
  /// InkWell handles pointer taps and normal Tab traversal instead).
  final FocusNode? catalogNode;
  final FocusNode? keywordNode;
  final FocusNode? listsNode;
  final FocusNode? dropdownNode;

  /// Use a single DPAD-capable dropdown when three labelled segments cannot
  /// fit without squeezing or overflowing the search header.
  final bool compact;

  /// Leave the toggle back to the search field (arrow-up, or arrow-left off the
  /// leftmost segment) / down into the board content.
  final VoidCallback? onLeaveToField;
  final VoidCallback? onLeaveToContent;

  const _ModeToggle({
    required this.mode,
    required this.isTelevision,
    required this.listsAvailable,
    required this.onChanged,
    this.fullWidth = false,
    this.catalogNode,
    this.keywordNode,
    this.listsNode,
    this.dropdownNode,
    this.compact = false,
    this.onLeaveToField,
    this.onLeaveToContent,
  });

  List<SearchBoardMode> get _modes => [
    SearchBoardMode.catalog,
    if (ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch))
      SearchBoardMode.keyword,
    if (listsAvailable) SearchBoardMode.lists,
  ];

  FocusNode? _nodeFor(SearchBoardMode value) => switch (value) {
    SearchBoardMode.catalog => catalogNode,
    SearchBoardMode.keyword => keywordNode,
    SearchBoardMode.lists => listsNode,
  };

  String _labelFor(SearchBoardMode value) => switch (value) {
    SearchBoardMode.catalog => 'Catalog',
    SearchBoardMode.keyword => 'Keyword',
    SearchBoardMode.lists => 'Lists',
  };

  /// DPAD handling for a focused segment: select switches mode, arrows move
  /// between the segments and out to the field (up/left) or content (down).
  KeyEventResult _handleSegmentKey(SearchBoardMode value, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onChanged(value);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onLeaveToField?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onLeaveToContent?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      final index = _modes.indexOf(value);
      if (index > 0) {
        _nodeFor(_modes[index - 1])?.requestFocus();
      } else {
        onLeaveToField?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final index = _modes.indexOf(value);
      if (index >= 0 && index < _modes.length - 1) {
        _nodeFor(_modes[index + 1])?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final modes = _modes;
    if (modes.length <= 1) {
      return const SizedBox.shrink();
    }
    if (compact) {
      return SizedBox(
        width: fullWidth ? double.infinity : 156,
        child: StremioDropdown<SearchBoardMode>(
          label: 'Search',
          value: modes.contains(mode) ? mode : modes.first,
          options: [
            for (final value in modes)
              StremioDropdownOption(value, _labelFor(value)),
          ],
          onSelected: onChanged,
          isTelevision: isTelevision,
          focusNode: dropdownNode,
          onUpArrowPressed: onLeaveToField,
          onDownArrowPressed: onLeaveToContent,
        ),
      );
    }
    final catalog = _segment(
      context,
      SearchBoardMode.catalog,
      'Catalog',
      Icons.grid_view_rounded,
    );
    final keyword = _segment(
      context,
      SearchBoardMode.keyword,
      'Keyword',
      Icons.bolt_rounded,
    );
    final lists = _segment(
      context,
      SearchBoardMode.lists,
      'Lists',
      Icons.playlist_play_rounded,
    );
    final segments = <Widget>[
      catalog,
      if (modes.contains(SearchBoardMode.keyword)) keyword,
      if (modes.contains(SearchBoardMode.lists)) lists,
    ];
    return Container(
      height: isTelevision ? 54 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: app.shape.br(14),
        border: Border.all(color: app.fade(app.core.tx, 0.08)),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: fullWidth
            ? [for (final segment in segments) Expanded(child: segment)]
            : segments,
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    SearchBoardMode value,
    String label,
    IconData icon,
  ) {
    final app = AppThemeScope.of(context);
    final on = mode == value;
    final node = switch (value) {
      SearchBoardMode.catalog => catalogNode,
      SearchBoardMode.keyword => keywordNode,
      SearchBoardMode.lists => listsNode,
    };

    Widget content(bool focused) => AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: isTelevision ? 16 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? app.home.chromeAccent : Colors.transparent,
        borderRadius: app.shape.br(10),
        // A white ring shows the remote's DPAD position. Drawn whenever the
        // segment is focused — including the selected one, since focus lands
        // there first (its accent fill alone wouldn't signal focus moved).
        border: Border.all(
          color: focused ? app.fade(app.core.tx, 0.9) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            // Scored against the fill, not hardcoded white: chromeAccent IS
            // the accent, and 17 of the 18 selectable themes have one where
            // white fails — Noir's and Frost's are pure #FFFFFF, so the
            // selected segment was a white label on a white bar. inkOn
            // returns white on legacy's #7B5CFF (4.36, over the threshold),
            // so this is a no-op today.
            color: on
                ? app.inkOn(app.home.chromeAccent)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: isTelevision ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: on
                  ? app.inkOn(app.home.chromeAccent)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (node == null) {
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: app.shape.br(10),
        child: content(false),
      );
    }

    // The wrapping Focus owns the keyboard/DPAD focus node; the InkWell stays
    // pointer-only (canRequestFocus:false) so it doesn't compete for focus.
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) => _handleSegmentKey(value, event),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            onTap: () => onChanged(value),
            borderRadius: app.shape.br(10),
            canRequestFocus: false,
            child: content(focused),
          );
        },
      ),
    );
  }
}

/// A pushable manual sources list for a catalog title/episode. Searches its own
/// torrent sources (own loading), renders them as [TorrentResultRow]s, and on
/// tap plays via the isolated service with the FULL source list + content
/// metadata (so the in-player Sources switcher + Continue Watching both work).
