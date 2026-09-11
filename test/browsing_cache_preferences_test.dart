import 'dart:convert';

import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BrowsingCachePreferences.resetForTesting();
    ProfileRuntime.debugReset();
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'unset choices preserve normal artwork caching and opt into movie discovery',
    () async {
      await BrowsingCachePreferences.initialize();
      expect(BrowsingCachePreferences.current.rememberTitles, isFalse);
      expect(BrowsingCachePreferences.current.expandedArtwork, isFalse);
      expect(BrowsingCachePreferences.current.prefetchMovieStreams, isTrue);
    },
  );

  test(
    'saved choices survive a process-style reload without entering a profile namespace',
    () async {
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'alice', dataGeneration: 1, sessionEpoch: 1),
      );
      await BrowsingCachePreferences.update(
        const BrowsingCacheOptions(
          rememberTitles: true,
          titleSizeMb: 50,
          expandedArtwork: true,
          artworkSizeMb: 1024,
          prefetchMovieStreams: false,
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {BrowsingCachePreferences.key});
      expect(
        DevicePreferences.allowedKeys,
        contains(BrowsingCachePreferences.key),
      );
      expect(
        ProfilePreferencePortability.allowsKey(BrowsingCachePreferences.key),
        isFalse,
      );
      BrowsingCachePreferences.resetForTesting();
      ProfileRuntime.publish(
        ProfileScope(profileId: 'bob', dataGeneration: 1, sessionEpoch: 2),
      );
      await BrowsingCachePreferences.initialize();
      final current = BrowsingCachePreferences.current;
      expect(current.rememberTitles, isTrue);
      expect(current.titleBudgetBytes, 50 * 1024 * 1024);
      expect(current.artworkBudgetBytes, 1024 * 1024 * 1024);
      expect(current.prefetchMovieStreams, isFalse);
    },
  );

  test('concurrent updates retain request order across restart', () async {
    await Future.wait([
      BrowsingCachePreferences.update(
        const BrowsingCacheOptions(artworkSizeMb: 128),
      ),
      BrowsingCachePreferences.update(
        const BrowsingCacheOptions(artworkSizeMb: 2048),
      ),
      BrowsingCachePreferences.update(
        const BrowsingCacheOptions(artworkSizeMb: 256),
      ),
    ]);
    BrowsingCachePreferences.resetForTesting();
    await BrowsingCachePreferences.initialize();
    expect(BrowsingCachePreferences.current.artworkSizeMb, 256);
  });

  for (final value in [
    'broken-json',
    '[]',
    '{"artworkSizeMb":-5,"titleSizeMb":999999}',
    '{"artworkSizeMb":512.0,"titleSizeMb":"25"}',
  ]) {
    test('invalid stored sizes remain bounded: $value', () async {
      SharedPreferences.setMockInitialValues({
        BrowsingCachePreferences.key: value,
      });
      await BrowsingCachePreferences.initialize();
      expect(BrowsingCachePreferences.current.artworkSizeMb, 512);
      expect(BrowsingCachePreferences.current.titleSizeMb, 25);
    });
  }

  test('unsupported programmatic sizes cannot be persisted', () async {
    await BrowsingCachePreferences.update(
      const BrowsingCacheOptions(titleSizeMb: -1, artworkSizeMb: 99999999),
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(BrowsingCachePreferences.key)!);
    expect(saved['titleSizeMb'], 25);
    expect(saved['artworkSizeMb'], 512);
  });
}
