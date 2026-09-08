import 'package:debrify/services/discover_prefs.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiscoverPrefs.debugReset();
  });

  test('Hold to Quick Play defaults off and persists changes', () async {
    expect(await HomePrefs.getHomeCwHoldToQuickPlay(), isFalse);

    await HomePrefs.setHomeCwHoldToQuickPlay(true);
    expect(await HomePrefs.getHomeCwHoldToQuickPlay(), isTrue);

    await HomePrefs.setHomeCwHoldToQuickPlay(false);
    expect(await HomePrefs.getHomeCwHoldToQuickPlay(), isFalse);
  });

  test('clearing Home settings resets Hold to Quick Play', () async {
    await HomePrefs.setHomeCwHoldToQuickPlay(true);

    await HomePrefs.clearAllHomePageSettings();

    expect(await HomePrefs.getHomeCwHoldToQuickPlay(), isFalse);
  });

  // Home's old standalone toggle merged into DiscoverPrefs.titleRatingsVisible
  // (Settings › Layout › Title & Ratings Visibility) — clearAllHomePageSettings
  // never owned this key, so there's nothing left for it to reset here.
  test('Title & Ratings Visibility defaults on and persists', () async {
    await DiscoverPrefs.warmUp();
    expect(DiscoverPrefs.titleRatingsVisible, isTrue);

    await DiscoverPrefs.setTitleRatingsVisible(false);
    expect(DiscoverPrefs.titleRatingsVisible, isFalse);

    // Restart: fresh cache, same on-disk pref.
    DiscoverPrefs.debugReset();
    await DiscoverPrefs.warmUp();
    expect(DiscoverPrefs.titleRatingsVisible, isFalse);
  });

  test('Hide Home catalog add-on names defaults off and persists', () async {
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isFalse);

    await HomePrefs.setHomeHideCatalogAddonNames(true);
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isTrue);

    await HomePrefs.clearAllHomePageSettings();
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isFalse);
  });
}
