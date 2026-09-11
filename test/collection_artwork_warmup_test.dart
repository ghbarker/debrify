import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/artwork_cache_budget.dart';
import 'package:debrify/services/artwork_cache_file.dart';
import 'package:debrify/services/browsing_cache_preferences.dart';
import 'package:debrify/services/collection_artwork_warmup.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StremioMeta item(String id, {String? poster, String? background}) =>
    StremioMeta(
      id: id,
      type: 'movie',
      name: id,
      poster: poster ?? 'https://art.test/$id.jpg',
      background: background,
    );

class _LeaseBudget extends ArtworkCacheBudget {
  int releases = 0, handoffs = 0;
  @override
  void Function() pin(String path) {
    var released = false;
    return () {
      if (!released) {
        releases++;
        released = true;
      }
    };
  }

  @override
  void finishHandoff(String path) {
    handoffs++;
  }
}

void main() {
  late ValueNotifier<bool> scrolling;
  late CollectionArtworkWarmup warmup;
  late List<String> downloaded;
  late List<File> released;
  var current = true;
  var bytes = 0;

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      BrowsingCachePreferences.key: jsonEncode(
        const BrowsingCacheOptions(
          expandedArtwork: true,
          artworkSizeMb: 128,
        ).toJson(),
      ),
    });
    BrowsingCachePreferences.resetForTesting();
    scrolling = ValueNotifier(false);
    downloaded = [];
    released = [];
    current = true;
    bytes = 0;
  });
  tearDown(() {
    warmup.dispose();
    scrolling.dispose();
    ProfileRuntime.debugReset();
  });

  Future<void> start(
    WidgetTester tester, {
    Future<File> Function(String)? load,
    Future<int> Function()? size,
    ArtworkPresentationLoader? present,
    Future<ProfilePreferences> Function()? access,
    bool realRelease = false,
    void Function(int, int)? onProgress,
  }) async {
    warmup = CollectionArtworkWarmup(
      scrolling: scrolling,
      onProgress: onProgress,
      isCurrent: () => current,
      now: tester.binding.clock.now,
      loadFile:
          load ??
          (url) async {
            downloaded.add(url);
            return File(url);
          },
      releaseFile: realRelease ? null : released.add,
      cacheBytes: size ?? () async => bytes,
      present:
          present ??
          (value, {preferences, isRelevant}) async =>
              MetadataPresentation(value),
      openPreferences: access,
    );
    warmup.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets(
    'progress is numeric and observer failures do not stop the queue',
    (tester) async {
      final progress = <(int, int)>[];
      await start(
        tester,
        onProgress: (done, total) {
          progress.add((done, total));
          throw StateError('observer failure');
        },
      );
      warmup.update([item('a'), item('b')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(progress, [(0, 2), (1, 2), (2, 2)]);
      expect(downloaded.length, 2);
      warmup.dispose();
      warmup.update([item('c')], landscape: false);
      expect(progress.length, 3);
    },
  );

  testWidgets(
    '250ms idle cadence, one request at a time, release and URL dedup',
    (tester) async {
      final pending = Completer<File>();
      await start(
        tester,
        load: (url) {
          downloaded.add(url);
          return downloaded.length == 1
              ? pending.future
              : Future.value(File(url));
        },
      );
      warmup.update([
        item('a'),
        item('a'),
        item('b', poster: 'https://art.test/a.jpg'),
        item('c'),
      ], landscape: false);
      await tester.pump(const Duration(milliseconds: 249));
      expect(downloaded, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(downloaded, ['https://art.test/a.jpg']);
      await tester.pump(const Duration(seconds: 2));
      expect(downloaded.length, 1);
      final file = File('leased');
      pending.complete(file);
      await tester.pump();
      expect(released, [same(file)]);
      await tester.pump(const Duration(milliseconds: 250)); // duplicate URL
      expect(downloaded.length, 1);
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded.last, 'https://art.test/c.jpg');
      await tester.pump(const Duration(seconds: 2));
      expect(downloaded.length, 2);
    },
  );

  testWidgets('scrolling and lifecycle pause, then each resume waits 250ms', (
    tester,
  ) async {
    await start(tester);
    warmup.update([item('a'), item('b'), item('c')], landscape: false);
    await tester.pump(const Duration(milliseconds: 100));
    scrolling.value = true;
    await tester.pump(const Duration(seconds: 1));
    expect(downloaded, isEmpty);
    scrolling.value = false;
    await tester.pump(const Duration(milliseconds: 249));
    expect(downloaded, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(downloaded.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(downloaded.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 250));
    expect(downloaded.length, 2);
    warmup.dispose();
  });

  testWidgets('memory pressure and reported slow frames resume automatically', (
    tester,
  ) async {
    await start(tester);
    warmup.update([item('a'), item('b')], landscape: false);
    tester.binding.handleMemoryPressure();
    await tester.pump(const Duration(seconds: 29));
    expect(downloaded, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(downloaded.length, 1);
    tester.binding.platformDispatcher.onReportTimings!([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 30000,
        rasterStart: 30000,
        rasterFinish: 31000,
        rasterFinishWallTime: 31000,
      ),
    ]);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(downloaded.length, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(downloaded.length, 2);
  });

  testWidgets(
    'budget stops before churn and resumes after capacity is available',
    (tester) async {
      bytes = 96 * 1024 * 1024;
      await start(tester);
      warmup.update([item('a')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded, isEmpty);
      bytes = 0;
      await tester.pump(const Duration(seconds: 30));
      expect(downloaded.length, 1);
    },
  );

  testWidgets('disabled policy and a late changed budget block disk requests', (
    tester,
  ) async {
    final pending = Completer<int>();
    await start(tester, size: () => pending.future);
    BrowsingCachePreferences.notifier.value = const BrowsingCacheOptions();
    warmup.update([item('a')], landscape: false);
    await tester.pump(const Duration(seconds: 1));
    expect(downloaded, isEmpty);
    BrowsingCachePreferences.notifier.value = const BrowsingCacheOptions(
      expandedArtwork: true,
    );
    await tester.pump(const Duration(milliseconds: 250));
    BrowsingCachePreferences.notifier.value = const BrowsingCacheOptions();
    pending.complete(0);
    await tester.pump();
    expect(downloaded, isEmpty);
  });

  testWidgets(
    'raw imported policy invalidates pending presentation without notifier',
    (tester) async {
      final pending = Completer<MetadataPresentation>();
      var calls = 0;
      await start(
        tester,
        present: (value, {preferences, isRelevant}) {
          calls++;
          return calls == 1
              ? pending.future
              : Future.value(MetadataPresentation(item('new')));
        },
      );
      warmup.update([item('a')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      final prefs = await ProfilePreferences.instance();
      await prefs.setString(
        MetadataPreferencesService.key,
        jsonEncode(MetadataPreferences(language: 'fr-FR').toJson()),
      );
      pending.complete(MetadataPresentation(item('wrong-old')));
      await tester.pump();
      expect(downloaded, isEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded, ['https://art.test/new.jpg']);
    },
  );

  testWidgets(
    'profile switch during metadata drops old items until fresh update',
    (tester) async {
      final pending = Completer<MetadataPresentation>();
      var calls = 0;
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'a', dataGeneration: 1, sessionEpoch: 1),
      );
      await start(
        tester,
        present: (value, {preferences, isRelevant}) {
          calls++;
          return calls == 1
              ? pending.future
              : Future.value(MetadataPresentation(value));
        },
      );
      warmup.update([item('old'), item('also-old')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      ProfileRuntime.publish(
        ProfileScope(profileId: 'b', dataGeneration: 1, sessionEpoch: 2),
      );
      pending.complete(MetadataPresentation(item('old')));
      await tester.pump(const Duration(seconds: 1));
      expect(downloaded, isEmpty);
      warmup.update([item('fresh')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded, ['https://art.test/fresh.jpg']);
    },
  );

  testWidgets(
    'dispose during disk request releases real lease and prevents continuation',
    (tester) async {
      final pending = Completer<File>();
      final budget = _LeaseBudget();
      await start(
        tester,
        realRelease: true,
        load: (url) {
          downloaded.add(url);
          return pending.future;
        },
      );
      warmup.update([item('a'), item('b')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      warmup.dispose();
      pending.complete(ArtworkCacheFile(File('unused-file'), budget));
      await tester.pump(const Duration(seconds: 2));
      expect(downloaded.length, 1);
      expect(budget.releases, 1);
      expect(budget.handoffs, 1);
    },
  );

  testWidgets(
    'scroll interruption during metadata never starts a late file request',
    (tester) async {
      final pending = Completer<MetadataPresentation>();
      await start(
        tester,
        present: (value, {preferences, isRelevant}) => pending.future,
      );
      warmup.update([item('a')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      scrolling.value = true;
      scrolling.value = false;
      pending.complete(MetadataPresentation(item('a')));
      await tester.pump();
      expect(
        downloaded,
        isEmpty,
        reason: 'An idle-again state must not revive the cancelled generation',
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded.length, 1);
    },
  );

  testWidgets(
    'real provider refuses raw backdrop/poster when fallback is disabled',
    (tester) async {
      final providerId = 'addon:${List.filled(64, 'a').join()}';
      final prefs = await ProfilePreferences.instance();
      await prefs.setString(
        MetadataPreferencesService.key,
        jsonEncode(
          MetadataPreferences(
            providers: {MetadataCategory.backgrounds: providerId},
            fallback: false,
          ).toJson(),
        ),
      );
      final provider = MetadataProviderService(
        addonLoader: (_, _) async => null,
      );
      await start(tester, present: provider.present);
      warmup.update([
        item('a', background: 'https://wrong.test/raw.jpg'),
      ], landscape: true);
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded, isEmpty);
      await MetadataPreferencesService.save(
        MetadataPreferences(
          providers: {MetadataCategory.backgrounds: providerId},
          fallback: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded, ['https://wrong.test/raw.jpg']);
    },
  );

  testWidgets(
    'orientation and discovered replacement invalidate stale result',
    (tester) async {
      final pending = Completer<MetadataPresentation>();
      var calls = 0;
      await start(
        tester,
        present: (value, {preferences, isRelevant}) => ++calls == 1
            ? pending.future
            : Future.value(MetadataPresentation(value)),
      );
      warmup.update([item('a')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      warmup.update([
        item('a', background: 'https://art.test/wide.jpg'),
      ], landscape: true);
      pending.complete(MetadataPresentation(item('a')));
      await tester.pump();
      expect(downloaded, isEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded, ['https://art.test/wide.jpg']);
    },
  );

  testWidgets(
    'broken first file has bounded retries and does not starve next image',
    (tester) async {
      await start(
        tester,
        load: (url) async {
          downloaded.add(url);
          if (url.endsWith('/a.jpg')) {
            throw const FileSystemException('synthetic');
          }
          return File(url);
        },
      );
      warmup.update([item('a'), item('b')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      expect(downloaded, [
        'https://art.test/a.jpg',
        'https://art.test/a.jpg',
        'https://art.test/a.jpg',
        'https://art.test/b.jpg',
      ]);
    },
  );

  testWidgets(
    'oversized first image yields to later normal image after bounded retries',
    (tester) async {
      await start(
        tester,
        load: (url) async {
          downloaded.add(url);
          if (url.endsWith('/oversized.jpg')) throw const ArtworkCacheLimit();
          return File(url);
        },
      );
      warmup.update([item('oversized'), item('normal')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      expect(
        downloaded.where((url) => url.endsWith('/oversized.jpg')).length,
        3,
      );
      expect(downloaded.last, 'https://art.test/normal.jpg');
      expect(released.length, 1);
    },
  );

  testWidgets(
    'global capacity loss during transfer pauses without dropping the item',
    (tester) async {
      var attempts = 0;
      await start(
        tester,
        load: (url) async {
          downloaded.add(url);
          if (++attempts == 1) {
            bytes = 100 * 1024 * 1024;
            throw const ArtworkCacheLimit();
          }
          return File(url);
        },
      );
      warmup.update([item('a')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(seconds: 29));
      expect(attempts, 1);
      bytes = 0;
      await tester.pump(const Duration(seconds: 1));
      expect(attempts, 2);
      expect(released.length, 1);
    },
  );

  testWidgets(
    'unavailable policy pauses safely, and covered route resumes automatically',
    (tester) async {
      var reads = 0;
      await start(
        tester,
        access: () {
          if (++reads == 1) throw StateError('locked');
          return ProfilePreferences.instance();
        },
      );
      warmup.update([item('a')], landscape: false);
      await tester.pump(const Duration(milliseconds: 250));
      expect(downloaded, isEmpty);
      current = false;
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 1);
      current = true;
      await tester.pump(const Duration(seconds: 1));
      expect(downloaded.length, 1);
    },
  );

  testWidgets(
    'artwork presentation excludes information provider and preserves art policy',
    (tester) async {
      final info = 'addon:${List.filled(64, 'a').join()}';
      final posters = 'addon:${List.filled(64, 'b').join()}';
      final backgrounds = 'addon:${List.filled(64, 'c').join()}';
      final original = MetadataPreferences(
        providers: {MetadataCategory.information: info},
        fallback: true,
        language: 'fr-FR',
        artworkLanguage: 'ja',
      );
      await MetadataPreferencesService.save(original);
      final providerCalls = <String>[];
      final captured = <MetadataPreferences>[];
      final provider = MetadataProviderService(
        addonLoader: (source, value) async {
          providerCalls.add(source);
          return item(
            value.id,
            poster: 'https://art.test/custom-poster.jpg',
            background: 'https://art.test/custom-background.jpg',
          );
        },
      );
      await start(
        tester,
        present: (value, {preferences, isRelevant}) {
          captured.add(preferences!);
          return provider.present(
            value,
            preferences: preferences,
            isRelevant: isRelevant,
          );
        },
      );
      warmup.update([item('a')], landscape: true);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        captured.single.provider(MetadataCategory.information),
        MetadataPreferences.current,
      );
      expect(
        providerCalls,
        isEmpty,
        reason:
            'An information-only provider has no work in disk artwork warming',
      );
      expect(downloaded, ['https://art.test/a.jpg']);

      await MetadataPreferencesService.save(
        original.copyWith(
          providers: {
            MetadataCategory.information: info,
            MetadataCategory.posters: posters,
            MetadataCategory.backgrounds: backgrounds,
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      final request = captured.last;
      expect(
        request.provider(MetadataCategory.information),
        MetadataPreferences.current,
      );
      expect(request.provider(MetadataCategory.posters), posters);
      expect(request.provider(MetadataCategory.backgrounds), backgrounds);
      expect(request.language, original.language);
      expect(request.artworkLanguage, original.artworkLanguage);
      expect(request.fallback, original.fallback);
      expect(providerCalls, unorderedEquals([posters, backgrounds]));
      expect(downloaded.last, 'https://art.test/custom-background.jpg');
    },
  );
}
