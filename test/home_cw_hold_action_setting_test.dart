import 'package:debrify/services/storage/home_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  test('Hide Home card titles and ratings defaults off and persists', () async {
    expect(await HomePrefs.getHomeHideCardTitlesAndRatings(), isFalse);

    await HomePrefs.setHomeHideCardTitlesAndRatings(true);
    expect(await HomePrefs.getHomeHideCardTitlesAndRatings(), isTrue);

    await HomePrefs.clearAllHomePageSettings();
    expect(await HomePrefs.getHomeHideCardTitlesAndRatings(), isFalse);
  });

  test('Hide Home catalog add-on names defaults off and persists', () async {
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isFalse);

    await HomePrefs.setHomeHideCatalogAddonNames(true);
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isTrue);

    await HomePrefs.clearAllHomePageSettings();
    expect(await HomePrefs.getHomeHideCatalogAddonNames(), isFalse);
  });
}
