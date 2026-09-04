import 'package:flutter/material.dart';

import 'search_screen_shells.dart';

/// Discover tab (MainTab 18). One browsable grid with a Source dropdown
/// (Continue Watching / Trakt / …) instead of the Home board's stacked rails.
///
/// Shares [HomeBoardController], [CatalogSearchController], and
/// [TitleOpener] with Home and Search via the host wired in G1 step 4.
/// TV stage layouts stay on the host (G1 step 5).
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  int get tabIndex =>
      searchScreenTabIndex(searchMode: false, discoverMode: true);

  String get variantKey =>
      searchScreenVariantKey(searchMode: false, discoverMode: true);

  String get analyticsName =>
      searchScreenAnalyticsName(searchMode: false, discoverMode: true);

  List<String> get sharedControllers => kSearchScreenSharedControllerNames;

  @override
  Widget build(BuildContext context) {
    // Host wiring (`SearchScreenHost(discoverMode: true)`) lands in the move.
    return const SizedBox.shrink();
  }
}
