import 'package:flutter/material.dart';

import 'search_screen_shells.dart';

/// Dedicated Search tab (MainTab 17). Field + Catalog/Keyword/Lists over a
/// blank prompt until the user types — no Home hero/board.
///
/// Shares [HomeBoardController], [CatalogSearchController], and
/// [TitleOpener] with Home and Discover via [host] ([SearchScreenHost]).
class CatalogSearchScreen extends StatelessWidget {
  const CatalogSearchScreen({super.key, this.isTelevision = false, this.host});

  final bool isTelevision;

  /// Shared host from `search_screen.dart`. Optional so pin tests can
  /// construct this type without mounting the 18k State.
  final Widget? host;

  int get tabIndex =>
      searchScreenTabIndex(searchMode: true, discoverMode: false);

  String get variantKey =>
      searchScreenVariantKey(searchMode: true, discoverMode: false);

  String get analyticsName =>
      searchScreenAnalyticsName(searchMode: true, discoverMode: false);

  List<String> get sharedControllers => kSearchScreenSharedControllerNames;

  @override
  Widget build(BuildContext context) => host ?? const SizedBox.shrink();
}
