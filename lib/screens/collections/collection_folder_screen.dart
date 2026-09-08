import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/collection_folder_loader.dart';
import '../../services/home_collections_store.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/home_rail_metrics.dart';
import '../../widgets/collections/folder_hero_band.dart';
import '../../widgets/collections/rail_header_focus.dart';
import '../../widgets/home/row_tag_pill.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/stremio_dropdown.dart';
import '../../widgets/skeleton_poster.dart';
import '../see_all/catalog_see_all_screen.dart';
import '../search/board_shelf_row.dart';

/// Full-screen browser for one folder of an imported collection — where a
/// folder tile on the Home board and the collection row's tap land.
///
/// Each catalog in a folder is its own list. Two layouts, chosen in
/// Settings › Home Screen › Collections:
///
///  * **Rows** — plain stacked rails, styled and spaced like the Home board
///    (no hero band, no filter dropdowns): a minimal header, then one rail
///    per list. Tapping/selecting a rail's header opens that list's regular
///    catalog browser; a collection with `showAllTab` also gets a leading
///    "All" row that switches to one merged grid of every list. Folder
///    switching lives on Home (every folder is already its own tile in the
///    collection's row) so it isn't duplicated here — Back returns to it.
///  * **Tabs** — a hero band, Folder/List/Sort dropdowns, and one list at a
///    time as a full poster grid (plus "All" when the collection enables
///    it), like Nuvio.
///
/// Neither layout shows a "See all" link or a position counter on a
/// collection rail — those only ever belonged to the regular catalog
/// See-All screens.
///
/// Lists switched off in the Home Rows manager (`collectionlist:` ids in the
/// disabled set) are left out of every view.
///
/// Rails render through [BoardShelfRow] — the same [BoardCell] widget (art,
/// [CardFocusRise] scale/shadow/focus-ring, hover-grow) and row gutter Home's
/// own board rails paint, so a folder reads as an actual Home row rather
/// than an approximation of one. This screen owns paging, folder switching
/// and the vertical DPAD ladder between rails (a rail's header → its cards →
/// the next rail's header); [BoardShelfRow] owns only the row itself. The
/// merged "All" grid and the Tabs layout's single-list view stay on
/// [SeeAllPosterGrid] — they're full poster walls, not rows, and were never
/// meant to read as Home.
class CollectionFolderScreen extends StatefulWidget {
  final HomeCollection collection;
  final int initialFolderIndex;
  final void Function(StremioMeta item) onOpenItem;
  final void Function(StremioMeta item)? onQuickPlay;
  final void Function(StremioMeta item)? onItemFocused;
  final bool Function(StremioMeta item)? isBound;
  final bool isTelevision;

  const CollectionFolderScreen({
    super.key,
    required this.collection,
    required this.onOpenItem,
    this.initialFolderIndex = 0,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.isTelevision = false,
  });

  @override
  State<CollectionFolderScreen> createState() => _CollectionFolderScreenState();
}

/// Rows layout: stacked rails, or the merged grid.
enum _View { lists, all }

/// Tabs layout: the merged grid's value in the List chip.
const int _kAllTab = -1;

/// One catalog list inside the folder: its resolved addon/catalog, the pages
/// loaded so far, and the focus plumbing for its rail.
class _Rail {
  _Rail({required this.source, required this.addon, required this.catalog});

  final CollectionCatalogSource source;
  final StremioAddon addon;
  final StremioAddonCatalog catalog;
  final GlobalKey<BoardShelfRowState> gridKey = GlobalKey();
  final GlobalKey containerKey = GlobalKey();
  final FocusNode headerNode = FocusNode(debugLabel: 'collection_rail_header');
  final List<StremioMeta> items = [];
  int nextSkip = 0;
  bool loadingInitial = true;
  bool loadingMore = false;
  bool exhausted = false;

  /// "Popular Movies · Action" — the Home row title plus the source's genre.
  String get title {
    final base = CatalogSection.rowTitle(catalog);
    final genre = source.genre;
    return genre == null ? base : '$base · $genre';
  }

  /// Hidden once loaded empty — an empty rail is noise, like on Home.
  bool get visible => loadingInitial || items.isNotEmpty;

  void dispose() => headerNode.dispose();
}

class _CollectionFolderScreenState extends State<CollectionFolderScreen> {
  final StremioService _stremio = StremioService.instance;

  static const String _sortDefault = 'default';
  static const String _sortImdbDesc = 'imdbDesc';
  static const String _sortImdbAsc = 'imdbAsc';
  static const String _sortTitle = 'title';
  String _sort = _sortDefault;

  late int _folderIndex;
  CollectionFolderLayout _layout = CollectionFolderLayout.rows;
  _View _view = _View.lists;
  int _tab = 0;
  List<StremioAddon> _addons = const [];
  Set<String> _disabled = const {};
  bool _booted = false;
  bool _landscapeCards = false;

  List<_Rail> _rails = const [];
  List<String> _unresolved = const [];
  final ScrollController _railsScroll = ScrollController();
  final GlobalKey<SeeAllPosterGridState> _tabGridKey = GlobalKey();

  // The All (merged grid) view, shared by both layouts.
  final GlobalKey<SeeAllPosterGridState> _allGridKey = GlobalKey();
  CollectionFolderLoader? _loader;
  final List<StremioMeta> _allItems = [];
  bool _allStarted = false;
  bool _allLoadingInitial = false;
  bool _allLoadingMore = false;
  bool _allExhausted = false;

  // Bumped on every folder change so in-flight pages from the previous
  // folder are discarded when they land.
  int _reqToken = 0;

  final FocusNode _backNode = FocusNode(debugLabel: 'collection_back');
  final FocusNode _folderNode = FocusNode(debugLabel: 'collection_folder');
  final FocusNode _listNode = FocusNode(debugLabel: 'collection_list');
  final FocusNode _sortNode = FocusNode(debugLabel: 'collection_sort');
  final FocusNode _retryNode = FocusNode(debugLabel: 'collection_retry');

  /// Rows layout only: the header of the leading "All" row (Tabs reaches the
  /// same merged grid through the List chip's "All" option instead).
  final FocusNode _allRowNode = FocusNode(debugLabel: 'collection_all_row');

  HomeCollection get _collection => widget.collection;
  bool get _hasFolders => _collection.folders.isNotEmpty;
  HomeCollectionFolder get _folder => _collection.folders[_folderIndex];
  bool get _tabs => _layout == CollectionFolderLayout.tabs;

  /// The folder's lists minus the ones switched off in Home Rows.
  List<CollectionCatalogSource> get _enabledSources => [
    for (final s in _folder.sources)
      if (!_disabled.contains(
        HomeCollectionRowIds.folderList(_collection.id, _folder.id, s),
      ))
        s,
  ];

  bool get _offersAll => _collection.showAllTab && _rails.length > 1;

  /// Whether the merged grid is what's on screen.
  bool get _showingAll => _tabs ? _tab == _kAllTab : _view == _View.all;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('collection_folder');
    final count = _collection.folders.length;
    _folderIndex = count == 0
        ? 0
        : widget.initialFolderIndex.clamp(0, count - 1);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      _addons = await _stremio.getCatalogAddons();
    } catch (_) {
      _addons = const [];
    }
    try {
      _disabled = await HomePrefs.getHomeDisabledSections();
    } catch (_) {
      _disabled = const {};
    }
    try {
      _landscapeCards =
          (await HomePrefs.getHomeCardOrientation()) ==
          HomeCardOrientation.landscape;
    } catch (_) {
      _landscapeCards = false;
    }
    _layout = await HomeCollectionsStore.instance.getFolderLayout();
    if (!mounted) return;
    _booted = true;
    _rebuildFolder(autoFocus: true);
  }

  @override
  void dispose() {
    for (final r in _rails) {
      r.dispose();
    }
    _railsScroll.dispose();
    _backNode.dispose();
    _folderNode.dispose();
    _listNode.dispose();
    _sortNode.dispose();
    _retryNode.dispose();
    _allRowNode.dispose();
    super.dispose();
  }

  // ── Folder (re)build ───────────────────────────────────────────────────

  /// Resolve the current folder's enabled lists into rails and fetch their
  /// first pages. The All view is built lazily on first switch.
  void _rebuildFolder({bool autoFocus = false}) {
    final token = ++_reqToken;
    for (final r in _rails) {
      r.dispose();
    }
    final rails = <_Rail>[];
    final unresolved = <String>[];
    if (_hasFolders) {
      for (final s in _enabledSources) {
        final addon = HomeCollectionsStore.resolveAddon(s, _addons);
        final catalog = addon == null
            ? null
            : HomeCollectionsStore.resolveCatalog(s, addon);
        if (addon == null || catalog == null) {
          unresolved.add(
            addon == null
                ? s.addonId
                : '${s.addonId} → ${s.type}/${s.catalogId}',
          );
          continue;
        }
        rails.add(_Rail(source: s, addon: addon, catalog: catalog));
      }
    }
    setState(() {
      _rails = rails;
      _unresolved = unresolved;
      _loader = null;
      _allItems.clear();
      _allStarted = false;
      _allLoadingInitial = false;
      _allLoadingMore = false;
      _allExhausted = false;
      _tab = 0;
      if (!_collection.showAllTab || rails.length < 2) _view = _View.lists;
    });
    for (final r in rails) {
      unawaited(_loadRail(r, token));
    }
    if (_showingAll) unawaited(_startAll(token));
    if (autoFocus && widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _reqToken) return;
        _enterContent();
      });
    }
  }

  Future<void> _loadRail(_Rail r, int token) async {
    try {
      var rawCount = 0;
      final items = await _stremio.fetchCatalog(
        r.addon,
        r.catalog,
        genre: r.source.genre,
        onRawCount: (c) => rawCount = c,
      );
      if (!mounted || token != _reqToken) return;
      setState(() {
        r.items.addAll(items);
        r.nextSkip = rawCount > 0 ? rawCount : items.length;
        r.exhausted = items.isEmpty;
        r.loadingInitial = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        r.loadingInitial = false;
        r.exhausted = true;
      });
    }
  }

  Future<void> _loadMoreRail(_Rail r) async {
    if (r.loadingInitial || r.loadingMore || r.exhausted) return;
    final token = _reqToken;
    setState(() => r.loadingMore = true);
    try {
      var rawCount = 0;
      final page = await _stremio.fetchCatalog(
        r.addon,
        r.catalog,
        skip: r.nextSkip,
        genre: r.source.genre,
        onRawCount: (c) => rawCount = c,
      );
      if (!mounted || token != _reqToken) return;
      final seen = r.items.map((m) => m.id).toSet();
      final fresh = page.where((m) => seen.add(m.id)).toList();
      setState(() {
        r.nextSkip += rawCount > 0 ? rawCount : page.length;
        if (fresh.isEmpty) {
          r.exhausted = true;
        } else {
          r.items.addAll(fresh);
        }
        r.loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() => r.loadingMore = false);
    }
  }

  // ── All (merged grid) ──────────────────────────────────────────────────

  Future<void> _startAll(int token) async {
    if (_allStarted) return;
    _allStarted = true;
    final loader = CollectionFolderLoader(
      folder: _folder.copyWith(sources: _enabledSources),
      installedAddons: _addons,
    );
    setState(() {
      _loader = loader;
      _allLoadingInitial = true;
    });
    try {
      final page = await loader.nextPage();
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allItems.addAll(page);
        _allExhausted = loader.exhausted;
        _allLoadingInitial = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allLoadingInitial = false;
        _allExhausted = true;
      });
    }
  }

  Future<void> _loadMoreAll() async {
    final loader = _loader;
    if (loader == null ||
        _allLoadingInitial ||
        _allLoadingMore ||
        _allExhausted) {
      return;
    }
    final token = _reqToken;
    setState(() => _allLoadingMore = true);
    try {
      final page = await loader.nextPage();
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allItems.addAll(page);
        _allExhausted = loader.exhausted;
        _allLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allLoadingMore = false;
        _allExhausted = true;
      });
    }
  }

  /// Client-side sort over whatever is loaded. Default keeps addon order.
  List<StremioMeta> _sorted(List<StremioMeta> items) {
    if (_sort == _sortDefault) return items;
    final sorted = List<StremioMeta>.of(items);
    if (_sort == _sortTitle) {
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return sorted;
    }
    final asc = _sort == _sortImdbAsc;
    sorted.sort((a, b) {
      final ra = a.imdbRating, rb = b.imdbRating;
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1;
      if (rb == null) return -1;
      return asc ? ra.compareTo(rb) : rb.compareTo(ra);
    });
    return sorted;
  }

  // ── Handlers ───────────────────────────────────────────────────────────

  void _onFolderChanged(int index) {
    if (index == _folderIndex) return;
    setState(() => _folderIndex = index);
    _rebuildFolder();
  }

  void _onViewChanged(_View view) {
    if (view == _view) return;
    setState(() => _view = view);
    if (view == _View.all) unawaited(_startAll(_reqToken));
  }

  void _onTabChanged(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == _kAllTab) unawaited(_startAll(_reqToken));
  }

  void _onSortChanged(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
  }

  /// The regular catalog browser on this rail's catalog, seeded with what the
  /// rail already loaded (paging continues rather than restarts) and opened
  /// on the source's genre.
  void _openRailSeeAll(_Rail r) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogSeeAllScreen(
          addon: r.addon,
          initialCatalog: r.catalog,
          initialGenre: r.source.genre,
          seedItems: List<StremioMeta>.of(r.items),
          seedNextSkip: r.nextSkip,
          isTelevision: widget.isTelevision,
          onOpenItem: widget.onOpenItem,
          onQuickPlay: widget.onQuickPlay,
          onItemFocused: widget.onItemFocused,
          isBound: widget.isBound,
        ),
      ),
    );
  }

  // ── TV focus ladder ────────────────────────────────────────────────────

  List<_Rail> get _visibleRails => [
    for (final r in _rails)
      if (r.visible) r,
  ];

  _Rail? get _tabRail =>
      _tab >= 0 && _tab < _rails.length ? _rails[_tab] : null;

  /// Tabs-only: the filter bar's own DPAD row (Rows has no filter bar at
  /// all, so [_handleFilterKeys] never runs there).
  List<FocusNode> get _filterNodes => [
    _folderNode,
    if (_rails.isNotEmpty) _listNode,
    _sortNode,
  ];

  bool get _showingEmpty {
    if (!_booted) return false;
    if (_showingAll) return !_allLoadingInitial && _allItems.isEmpty;
    if (_tabs) {
      final r = _tabRail;
      return r == null || (!r.loadingInitial && r.items.isEmpty);
    }
    return _visibleRails.isEmpty;
  }

  /// DPAD-down from the header. Tabs keeps its filter bar's own ladder (this
  /// only fires from the bar's last chip or the header itself) and jumps
  /// straight into whichever grid is on screen. Rows always lands on the
  /// next rung down instead — the "All" row's header when the folder offers
  /// one, else the first rail's header — same as any other rail-to-rail
  /// step, so a second DPAD-down is what actually enters a grid. Either way,
  /// an empty result sends focus to the Retry button.
  void _enterContent() {
    if (_showingEmpty) {
      _retryNode.requestFocus();
      return;
    }
    if (_tabs) {
      if (_showingAll) {
        _allGridKey.currentState?.focusFirst();
      } else {
        _tabGridKey.currentState?.focusFirst();
      }
      return;
    }
    if (_offersAll) {
      _allRowNode.requestFocus();
      return;
    }
    final rails = _visibleRails;
    if (rails.isEmpty) {
      _retryNode.requestFocus();
      return;
    }
    rails.first.headerNode.requestFocus();
  }

  /// Where the grid hands focus back to on DPAD-up: the List chip (Tabs), the
  /// Folder chip when a folder with no lists left the filter bar as the only
  /// stop (Tabs), or the "All" row's header (Rows — the only way Rows reaches
  /// a merged grid is through that row).
  FocusNode get _gridExitNode {
    if (_tabs) return _rails.isNotEmpty ? _listNode : _folderNode;
    return _offersAll ? _allRowNode : _backNode;
  }

  void _focusRailAbove(_Rail r) {
    final rails = _visibleRails;
    final i = rails.indexOf(r);
    if (i <= 0) {
      if (_offersAll) {
        _allRowNode.requestFocus();
      } else {
        _backNode.requestFocus();
      }
      return;
    }
    rails[i - 1].gridKey.currentState?.focusFirst();
  }

  void _focusRailBelow(_Rail r) {
    final rails = _visibleRails;
    final i = rails.indexOf(r);
    if (i < 0 || i + 1 >= rails.length) return;
    rails[i + 1].headerNode.requestFocus();
  }

  /// DPAD-down from the "All" row's header: the first rail's header, mirroring
  /// how a rail's own header sits one rung above its grid.
  void _focusFirstRailHeader() {
    final rails = _visibleRails;
    if (rails.isNotEmpty) rails.first.headerNode.requestFocus();
  }

  void _ensureRailVisible(_Rail r) {
    final ctx = r.containerKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.15,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision) return KeyEventResult.ignored;
    return handleSeeAllFilterArrows(
      event,
      _filterNodes,
      onDown: _enterContent,
      onUp: () => _backNode.requestFocus(),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final subtitle = !_hasFolders
        ? 'No folders'
        : '${_folder.title} · ${_rails.length} '
              'list${_rails.length == 1 ? '' : 's'}';
    return Scaffold(
      backgroundColor: AppThemeScope.of(context).seeAll.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeeAllHeader(
              title: _collection.title,
              subtitle: subtitle,
              isTelevision: widget.isTelevision,
              backNode: _backNode,
              // Rows has no filter bar to land on — DPAD-down goes straight
              // into the rails (or the "All" row above them).
              onFilterDown: _tabs
                  ? () => _folderNode.requestFocus()
                  : _enterContent,
            ),
            if (_tabs && _hasFolders)
              FolderHeroBand(
                key: ValueKey('folder-hero-${_folder.id}'),
                folder: _folder,
                isTelevision: widget.isTelevision,
              ),
            if (_tabs) _buildFilterBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _sortChip() => StremioDropdown<String>(
    label: 'Sort',
    value: _sort,
    isTelevision: widget.isTelevision,
    focusNode: _sortNode,
    options: const [
      StremioDropdownOption(_sortDefault, 'Default'),
      StremioDropdownOption(_sortImdbDesc, 'IMDb Rating · High → Low'),
      StremioDropdownOption(_sortImdbAsc, 'IMDb Rating · Low → High'),
      StremioDropdownOption(_sortTitle, 'Title · A → Z'),
    ],
    onSelected: _onSortChanged,
  );

  /// Tabs layout only — Folder / List / Sort dropdowns under the hero band.
  /// Rows has no filter bar (see the class doc).
  Widget _buildFilterBar() {
    final folders = _collection.folders;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleFilterKeys,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: SeeAllFilterBar(
          isTelevision: widget.isTelevision,
          activeCount: _sort != _sortDefault ? 1 : 0,
          buildChips: () => [
            StremioDropdown<int>(
              label: 'Folder',
              value: _folderIndex,
              isTelevision: widget.isTelevision,
              focusNode: _folderNode,
              options: [
                for (var i = 0; i < folders.length; i++)
                  StremioDropdownOption(i, folders[i].title),
              ],
              onSelected: _onFolderChanged,
            ),
            if (_rails.isNotEmpty)
              StremioDropdown<int>(
                label: 'List',
                value: _tab,
                isTelevision: widget.isTelevision,
                focusNode: _listNode,
                options: [
                  for (var i = 0; i < _rails.length; i++)
                    StremioDropdownOption(i, _rails[i].title),
                  if (_offersAll) const StremioDropdownOption(_kAllTab, 'All'),
                ],
                onSelected: _onTabChanged,
              ),
            _sortChip(),
          ],
        ),
      ),
    );
  }

  /// Horizontal padding around a rail's header and row — matches Home's own
  /// board rail gutter.
  static const double _railHPad = 24;

  /// Same card geometry as the ACTIVE Home layout, so a folder reads as Home
  /// with different lists — not just some Home layout's cards. Canvas (the
  /// shipped TV default) sizes its shelf by a completely different formula
  /// than the classic board; matching whichever one is actually on screen is
  /// what makes the folder read as "this device's Home", not just "a Home".
  ({double width, double height}) _railCardSize(BuildContext context) {
    if (widget.isTelevision && StorageService.tvHomeStyleCached == 'canvas') {
      final size = canvasRailCardSize(
        context,
        landscapeCards: _landscapeCards,
      );
      return (width: size.width, height: size.height);
    }
    final posterW = homeRailPosterWidth(
      context,
      isTelevision: widget.isTelevision,
    );
    return (width: posterW, height: posterW * 1.5);
  }

  Widget _buildBody() {
    if (!_booted) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    // Tabs keeps its filter bar on screen at all times, so the merged grid
    // can simply take over the body — the List chip is still there to switch
    // away. Rows has no such permanent chrome, so its "All" toggle has to
    // stay on screen instead (see _buildLists): only Tabs replaces the body
    // outright.
    if (_tabs) return _showingAll ? _buildAll() : _buildTab();
    return _buildLists();
  }

  Widget _buildLists() {
    final size = _railCardSize(context);
    final posterW = size.width;
    final cellH = size.height;
    // The merged grid stays under the SAME "All" row rather than replacing
    // it — that row is the only way Rows offers back into it, so pressing it
    // again (now reading "Lists") is how you leave.
    if (_offersAll && _view == _View.all) {
      return Column(
        children: [
          _buildAllRow(),
          Expanded(child: _buildAll()),
        ],
      );
    }
    final rails = _visibleRails;
    if (rails.isEmpty) return _buildEmpty();
    final showAllRow = _offersAll;
    return ListView.builder(
      controller: _railsScroll,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: (showAllRow ? 1 : 0) + rails.length,
      itemBuilder: (context, i) {
        if (showAllRow && i == 0) return _buildAllRow();
        return _buildRail(
          rails[i - (showAllRow ? 1 : 0)],
          posterW: posterW,
          cellH: cellH,
        );
      },
    );
  }

  /// The leading row a `showAllTab` collection gets in Rows layout — where
  /// the removed View dropdown's Lists/All choice moved to. Reads "All" and
  /// switches to the merged grid (kept under this same header, so pressing
  /// it again — now reading "Lists" — is how you get back).
  Widget _buildAllRow() {
    final app = AppThemeScope.of(context);
    final tv = widget.isTelevision;
    final showingAll = _view == _View.all;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _railHPad,
        14,
        _railHPad,
        showingAll ? 8 : 14,
      ),
      child: RailHeaderFocus(
        node: _allRowNode,
        isTelevision: tv,
        onPressed: () => _onViewChanged(showingAll ? _View.lists : _View.all),
        onUp: () => _backNode.requestFocus(),
        onDown: showingAll
            ? () => _allGridKey.currentState?.focusFirst()
            : _focusFirstRailHeader,
        onFocused: () {},
        child: Row(
          children: [
            Text(
              showingAll ? 'Lists' : 'All',
              style: TextStyle(
                color: app.core.tx,
                fontSize: tv ? 18 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              showingAll ? 'Back to every list' : 'Every list merged',
              style: TextStyle(
                color: app.fade(app.core.tx, 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail(_Rail r, {required double posterW, required double cellH}) {
    final app = AppThemeScope.of(context);
    final tv = widget.isTelevision;
    return Column(
      key: r.containerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(_railHPad, 14, _railHPad, 0),
          child: RailHeaderFocus(
            node: r.headerNode,
            isTelevision: tv,
            // On TV a row's name is a label, exactly like Home's own row
            // names — not a control. Off TV it still opens the full catalog
            // browse, the tap affordance every list title has always had.
            onPressed: tv ? null : () => _openRailSeeAll(r),
            onUp: () => _focusRailAbove(r),
            onDown: () => r.gridKey.currentState?.focusFirst(),
            onFocused: () => _ensureRailVisible(r),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: tv ? 18 : 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                RowTagPill(r.addon.name),
              ],
            ),
          ),
        ),
        r.loadingInitial
            ? _railSkeleton(posterW: posterW, cellH: cellH)
            : BoardShelfRow(
                key: r.gridKey,
                items: r.items,
                isTelevision: tv,
                posterW: posterW,
                cellH: cellH,
                loadingMore: r.loadingMore,
                onOpen: widget.onOpenItem,
                onQuickPlay: widget.onQuickPlay,
                onItemFocused: (item) {
                  _ensureRailVisible(r);
                  widget.onItemFocused?.call(item);
                },
                isBound: widget.isBound,
                onLoadMore: () => _loadMoreRail(r),
                onExitTop: tv ? () => r.headerNode.requestFocus() : null,
                onExitBottom: tv ? () => _focusRailBelow(r) : null,
              ),
      ],
    );
  }

  /// Loading placeholder for one rail, in [BoardShelfRow]'s own row shape
  /// (same gutter, same card size) so real posters fill in with no layout
  /// shift once the fetch lands.
  Widget _railSkeleton({required double posterW, required double cellH}) {
    return SizedBox(
      height: cellH + 14,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        itemCount: 6,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Center(
            child: SizedBox(
              width: posterW,
              height: cellH,
              child: const ShimmerBox(),
            ),
          ),
        ),
      ),
    );
  }

  /// Tabs layout: the selected list as a full poster grid.
  Widget _buildTab() {
    final r = _tabRail;
    if (r == null) return _buildEmpty();
    if (r.loadingInitial) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (r.items.isEmpty) return _buildEmpty();
    return SeeAllPosterGrid(
      // Keyed per list so switching tabs remounts the grid (fresh scroll and
      // focus memory) instead of morphing one list into another.
      key: ValueKey('collection-tab-${r.source.key}'),
      items: _sorted(r.items),
      isTelevision: widget.isTelevision,
      loadingMore: r.loadingMore,
      exhausted: r.exhausted,
      onOpen: widget.onOpenItem,
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      isBound: widget.isBound,
      onLoadMore: () => _loadMoreRail(r),
      onExitTop: widget.isTelevision
          ? () => _gridExitNode.requestFocus()
          : null,
    );
  }

  Widget _buildAll() {
    if (_allLoadingInitial || (!_allStarted && _rails.isNotEmpty)) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (_allItems.isEmpty) return _buildEmpty();
    return SeeAllPosterGrid(
      key: _allGridKey,
      items: _sorted(_allItems),
      isTelevision: widget.isTelevision,
      loadingMore: _allLoadingMore,
      exhausted: _allExhausted,
      onOpen: widget.onOpenItem,
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      isBound: widget.isBound,
      onLoadMore: _loadMoreAll,
      onExitTop: widget.isTelevision
          ? () => _gridExitNode.requestFocus()
          : null,
    );
  }

  Widget _buildEmpty() {
    final app = AppThemeScope.of(context);
    final String title;
    final String detail;
    if (!_hasFolders) {
      title = 'This collection has no folders';
      detail = 'Import a file that lists folders with catalog sources.';
    } else if (_folder.sources.isEmpty) {
      title = 'This folder lists no catalogs';
      detail = 'Nothing to browse here.';
    } else if (_enabledSources.isEmpty) {
      title = 'Every list in this folder is switched off';
      detail =
          'Turn its lists back on under Settings › Home Screen › Home Rows.';
    } else if (_rails.isEmpty) {
      title = 'No matching addon installed';
      detail =
          'This folder needs an addon that isn\'t installed:\n'
          '${_unresolved.toSet().join('\n')}\n\n'
          'Install it under Addons, then come back.';
    } else if (_tabs && !_showingAll) {
      title = 'Nothing in this list';
      detail = 'The catalog may be empty, or the addon failed to respond.';
    } else {
      title = 'Nothing in this folder';
      detail = _unresolved.isNotEmpty
          ? 'The installed catalogs returned nothing. Some lists are '
                'missing an addon:\n${_unresolved.toSet().join('\n')}'
          : 'The catalogs may be empty, or the addon failed to respond.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 44,
                color: app.fade(app.core.tx, 0.25),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.4),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              Focus(
                onKeyEvent: (_, event) {
                  if (widget.isTelevision &&
                      event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _gridExitNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: OutlinedButton.icon(
                  focusNode: _retryNode,
                  onPressed: () => _rebuildFolder(autoFocus: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: app.core.tx,
                    side: BorderSide(color: app.seeAll.accentBorder),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: app.shape.br(11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
