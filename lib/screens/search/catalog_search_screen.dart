import 'package:flutter/material.dart';

import 'search_screen_shells.dart';

/// Dedicated Search tab (MainTab 17). Field + Catalog/Keyword/Lists over a
/// blank prompt until the user types — no Home hero/board.
///
/// Shares [HomeBoardController], [CatalogSearchController], and
/// [TitleOpener] with Home and Discover via the host wired in G1 step 4.
class CatalogSearchScreen extends StatelessWidget {
  const CatalogSearchScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  int get tabIndex =>
      searchScreenTabIndex(searchMode: true, discoverMode: false);

  String get variantKey =>
      searchScreenVariantKey(searchMode: true, discoverMode: false);

  String get analyticsName =>
      searchScreenAnalyticsName(searchMode: true, discoverMode: false);

  List<String> get sharedControllers => kSearchScreenSharedControllerNames;

  @override
  Widget build(BuildContext context) {
    // Host wiring (`SearchScreenHost(searchMode: true)`) lands in the move.
    return const SizedBox.shrink();
  }
}
