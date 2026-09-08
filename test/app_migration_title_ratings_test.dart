import 'package:debrify/services/app_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the one-time merge of the retired Home "Hide Titles and Ratings"
/// toggle and Discover's separate "Show titles"/"Show ratings" toggles into
/// the single `poster_title_ratings_visible` preference.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh profile with no old prefs migrates to visible', () async {
    final prefs = await SharedPreferences.getInstance();
    await AppMigrationService.migrateTitleRatingsVisibility(prefs);

    expect(prefs.getBool('poster_title_ratings_visible'), isTrue);
    expect(prefs.getBool('poster_title_ratings_migrated'), isTrue);
  });

  test('hidden on every old screen migrates to hidden', () async {
    SharedPreferences.setMockInitialValues({
      'home_hide_card_titles_and_ratings': true,
      'discover_show_titles': false,
      'discover_show_ratings': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await AppMigrationService.migrateTitleRatingsVisibility(prefs);

    expect(prefs.getBool('poster_title_ratings_visible'), isFalse);
  });

  test(
    'disagreement between old screens resolves to visible',
    () async {
      // Home hid them but Discover still showed both — the old screens
      // disagreed, so the merge favours visible.
      SharedPreferences.setMockInitialValues({
        'home_hide_card_titles_and_ratings': true,
        'discover_show_titles': true,
        'discover_show_ratings': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await AppMigrationService.migrateTitleRatingsVisibility(prefs);

      expect(prefs.getBool('poster_title_ratings_visible'), isTrue);
    },
  );

  test(
    'Discover hid only one of titles/ratings resolves to visible',
    () async {
      SharedPreferences.setMockInitialValues({
        'home_hide_card_titles_and_ratings': true,
        'discover_show_titles': false,
        'discover_show_ratings': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await AppMigrationService.migrateTitleRatingsVisibility(prefs);

      expect(prefs.getBool('poster_title_ratings_visible'), isTrue);
    },
  );

  test('Home alone did not hide them resolves to visible', () async {
    SharedPreferences.setMockInitialValues({
      'home_hide_card_titles_and_ratings': false,
      'discover_show_titles': false,
      'discover_show_ratings': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await AppMigrationService.migrateTitleRatingsVisibility(prefs);

    expect(prefs.getBool('poster_title_ratings_visible'), isTrue);
  });

  test('runs once — a later manual change is not overwritten', () async {
    SharedPreferences.setMockInitialValues({
      'home_hide_card_titles_and_ratings': true,
      'discover_show_titles': false,
      'discover_show_ratings': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await AppMigrationService.migrateTitleRatingsVisibility(prefs);
    expect(prefs.getBool('poster_title_ratings_visible'), isFalse);

    // The user turns it back on afterwards.
    await prefs.setBool('poster_title_ratings_visible', true);

    // A later launch's migration attempt must not stomp the user's choice.
    await AppMigrationService.migrateTitleRatingsVisibility(prefs);
    expect(prefs.getBool('poster_title_ratings_visible'), isTrue);
  });
}
