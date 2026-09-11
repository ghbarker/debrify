import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/services/collection_native_source_service.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/theme/tv_motion_scope.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/collections/collection_list_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IsolateProbeCollection extends HomeCollection {
  _IsolateProbeCollection(this.events, this.uiIsolate, {required super.folders})
    : super(id: 'large', title: 'Synthetic large collection');
  final SendPort events, uiIsolate;
  @override
  Map<String, dynamic> toJson() {
    final onUi = Isolate.current.controlPort == uiIsolate;
    events.send(onUi);
    if (onUi) throw StateError('Collection encoded on UI isolate');
    // Hold only the worker so the host can change session while encoding.
    sleep(const Duration(milliseconds: 100));
    return super.toJson();
  }
}

HomeCollection sampleCollection({int listCount = 3}) => HomeCollection(
  id: 'sample',
  title: 'Sample collection',
  folders: [
    HomeCollectionFolder(
      id: 'folder',
      title: 'Folder',
      sources: [
        for (var i = 1; i <= listCount; i++)
          CollectionCatalogSource.fromJson({
            'provider': 'tmdb',
            'tmdbSourceType': 'COMPANY',
            'tmdbId': i,
            'title': 'List $i',
          })!,
      ],
    ),
  ],
);

void main() {
  setUp(() {
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      'home_collections_folder_layout': 'rows',
      'home_card_orientation': 'landscape',
    });
    StremioService.instance.invalidateCache();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool tv = true,
    TvMotionProfile? motion = TvMotionProfile.snappy,
    int listCount = 3,
    bool reduced = false,
    bool route = false,
    void Function(StremioMeta)? onOpen,
    void Function(StremioMeta)? onQuickPlay,
    Future<http.Response> Function(http.Request)? fetch,
  }) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final native = CollectionNativeSourceService(
      tmdbToken: 'synthetic',
      resolveIds: false,
      client: MockClient(
        fetch ??
            (request) async {
              final company =
                  request.url.queryParameters['with_companies'] ?? '1';
              return http.Response(
                jsonEncode({
                  'results': [
                    for (var i = 0; i < 20; i++)
                      {
                        'id': int.parse(company) * 100 + i,
                        'title': 'Movie $company/$i',
                      },
                  ],
                  'total_pages': 1,
                }),
                200,
              );
            },
      ),
    );
    addTearDown(native.close);
    Widget screen() {
      final child = CollectionFolderScreen(
        collection: sampleCollection(listCount: listCount),
        nativeSources: native,
        isTelevision: tv,
        onOpenItem: onOpen ?? (_) {},
        onQuickPlay: onQuickPlay,
      );
      return MediaQuery(
        data: MediaQueryData(
          size: const Size(960, 540),
          disableAnimations: reduced,
        ),
        child: motion == null
            ? TvMotionRoot(child: child)
            : TvMotionScope(profile: motion, child: child),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: route
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => screen())),
                    child: const Text('Open folder'),
                  ),
                ),
              )
            : screen(),
      ),
    );
    if (route) {
      await tester.tap(find.text('Open folder'));
    }
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  FocusNode folderNode(WidgetTester tester) => tester
      .widgetList<StremioDropdown<int>>(find.byType(StremioDropdown<int>))
      .firstWhere((d) => d.label == 'Folder')
      .focusNode!;

  Future<void> enter(WidgetTester tester) async {
    folderNode(tester).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_title_tmdb:100',
    );
  }

  ScrollPosition vertical(WidgetTester tester) => tester
      .stateList<ScrollableState>(
        find.descendant(
          of: find.byType(CollectionTvRails),
          matching: find.byType(Scrollable),
        ),
      )
      .singleWhere((s) => s.axisDirection == AxisDirection.down)
      .position;

  testWidgets('TV rows are title shelves, not list gallery navigation', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byType(CollectionListGallery), findsNothing);
    final horizontal = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .where((s) => s.axisDirection == AxisDirection.right);
    expect(horizontal.length, greaterThanOrEqualTo(2));
    expect(find.text('List 1'), findsOneWidget);
    expect(find.text('List 2'), findsOneWidget);
  });

  testWidgets('Home hide preference updates visible rail identity live', (
    tester,
  ) async {
    await HomeCollectionsStore.instance.saveCollections([sampleCollection()]);
    await mount(tester);
    expect(find.text('Movie 1/0'), findsOneWidget);
    // Preference changes use the host configuration signature, not a test-only
    // widget override. The selected page remains the same collection.
    await StorageService.setHomeHideCardTitlesAndRatings(true);
    MainPageBridge.notifyHomeSettingsChanged();
    await tester.pumpAndSettle();
    expect(find.text('Movie 1/0'), findsNothing);
    expect(find.byType(CollectionTvRails), findsOneWidget);
    await StorageService.setHomeHideCardTitlesAndRatings(false);
    MainPageBridge.notifyHomeSettingsChanged();
    await tester.pumpAndSettle();
    expect(find.text('Movie 1/0'), findsOneWidget);
  });

  testWidgets('phone keeps list gallery', (tester) async {
    await mount(tester, tv: false);
    expect(find.byType(CollectionListGallery), findsOneWidget);
  });

  testWidgets(
    'DPAD skips inert headers, carries column and returns from a title route',
    (tester) async {
      final opened = <String>[];
      await mount(
        tester,
        route: true,
        onOpen: (item) {
          opened.add(item.id);
          Navigator.of(
            tester.element(find.byType(CollectionFolderScreen)),
          ).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Detail')),
            ),
          );
        },
      );
      await enter(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:201',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, ['tmdb:201']);
      expect(find.text('Detail'), findsOneWidget);
      Navigator.of(tester.element(find.text('Detail'))).pop();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:201',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:101',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(folderNode(tester).hasFocus, isTrue);
    },
  );

  for (final landscape in [true, false]) {
    testWidgets(
      'Classic Home card geometry and artwork orientation: landscape=$landscape',
      (tester) async {
        await StorageService.setHomeCardOrientation(
          landscape
              ? HomeCardOrientation.landscape
              : HomeCardOrientation.portrait,
        );
        await mount(tester);
        final card = find.byWidgetPredicate(
          (w) =>
              w is SizedBox &&
              w.key.toString().contains('collection_card_') &&
              w.key.toString().contains('_tmdb:100'),
        );
        expect(card, findsOneWidget);
        final expectedWidth = landscape ? 92 * 1.6 : 92.0;
        final size = tester.getSize(card);
        expect(size.width, closeTo(expectedWidth, .001));
        expect(
          size.height,
          closeTo(expectedWidth / (landscape ? 16 / 9 : 2 / 3), .001),
        );
        expect(
          tester
              .widget<CollectionTvRails>(find.byType(CollectionTvRails))
              .landscapeCards,
          landscape,
        );
      },
    );
  }

  testWidgets(
    'held DPAD crosses unmounted horizontal items and later rails without stale focus',
    (tester) async {
      await mount(tester);
      await enter(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 16; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:117',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:317',
      );
      expect(vertical(tester).pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  // Preserved tree 525e18e2: BoardCell passes 260ms to TvFocusScrollWrapper,
  // which preserves that duration for TV Snappy as well as Smooth.
  for (final mode in [null, TvMotionProfile.snappy, TvMotionProfile.smooth]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'collection keeps 260ms motion with Spotlight=$mode reduced=$reduced',
        (tester) async {
          if (mode == null) {
            await TvMotionController.warm();
            expect(TvMotionController.current, TvMotionProfile.snappy);
          }
          await StorageService.setHomeCardOrientation(
            HomeCardOrientation.portrait,
          );
          await mount(tester, motion: mode, reduced: reduced);
          await enter(tester);
          final position = vertical(tester);
          final before = position.pixels;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));
          final intermediate = position.pixels;
          await tester.pump(const Duration(milliseconds: 70));
          final halfway = position.pixels;
          await tester.pumpAndSettle();
          final end = position.pixels;
          expect(end, greaterThan(before));
          if (!reduced) {
            expect(intermediate, greaterThan(before));
            expect(intermediate, lessThan(end));
            expect(
              halfway,
              closeTo(
                before + (end - before) * Curves.easeOutCubic.transform(.5),
                .2,
              ),
              reason:
                  'Collections retain their 260ms glide independently of the Spotlight preference.',
            );
          } else {
            expect(intermediate, end);
          }
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'collection_title_tmdb:200',
          );
        },
      );
    }
  }

  testWidgets('Select hold quick-plays once; arrows cancel a pending hold', (
    tester,
  ) async {
    final opened = <String>[], played = <String>[];
    await mount(
      tester,
      onOpen: (m) => opened.add(m.id),
      onQuickPlay: (m) => played.add(m.id),
    );
    await enter(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 850));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(played, ['tmdb:100']);
    expect(opened, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 850));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(played, ['tmdb:100']);
    expect(opened, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(opened, ['tmdb:101']);
  });

  testWidgets('held Down and reversal retain visible focus across lazy rails', (
    tester,
  ) async {
    final opened = <String>[];
    await mount(tester, listCount: 20, onOpen: (item) => opened.add(item.id));
    await enter(tester);
    final position = vertical(tester);
    var immediateReveals = 0;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 11; i++) {
      final before = position.pixels;
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      if (position.pixels != before) immediateReveals++;
      await tester.pump(const Duration(milliseconds: 12));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_title_tmdb:1300',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 12));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_title_tmdb:700',
    );
    final focus =
        FocusManager.instance.primaryFocus!.context!.findRenderObject()!
            as RenderBox;
    final viewport = tester.getRect(find.byType(CollectionTvRails));
    final top = focus.localToGlobal(Offset.zero).dy;
    expect(top, greaterThanOrEqualTo(viewport.top));
    expect(top + focus.size.height, lessThanOrEqualTo(viewport.bottom));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(opened, ['tmdb:700']);
    expect(tester.takeException(), isNull);
    // Diagnostic, not a physical frame-pacing assertion: bursts can exceed
    // the bounded vertical cache and require the existing mount-time reveal.
    debugPrint(
      'Lazy-rail immediate reveals during 12ms repeats: $immediateReveals',
    );
  });

  testWidgets(
    'late first pages do not steal focus after exiting waiting content',
    (tester) async {
      final response = Completer<http.Response>();
      await mount(tester, fetch: (_) => response.future);
      folderNode(tester).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final before = FocusManager.instance.primaryFocus;
      expect(before?.debugLabel, 'collection_back');
      response.complete(
        http.Response(
          '{"results":[{"id":42,"title":"Late title"}],"total_pages":1}',
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(before));
    },
  );

  testWidgets('Down while loading enters first titles once they arrive', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    await mount(tester, fetch: (_) => response.future);
    folderNode(tester).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    response.complete(
      http.Response(
        '{"results":[{"id":42,"title":"Late title"}],"total_pages":1}',
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_title_tmdb:42',
    );
  });

  testWidgets(
    'unchanged live configuration retains rails/focus; orientation change rebuilds safely',
    (tester) async {
      await HomeCollectionsStore.instance.saveCollections([sampleCollection()]);
      await mount(tester);
      await enter(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final focus = FocusManager.instance.primaryFocus;
      final state = tester.state(find.byType(CollectionTvRails));
      MainPageBridge.notifyHomeSettingsChanged();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(CollectionTvRails)), same(state));
      expect(FocusManager.instance.primaryFocus, same(focus));
      await StorageService.setHomeCardOrientation(HomeCardOrientation.portrait);
      MainPageBridge.notifyHomeSettingsChanged();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CollectionTvRails>(find.byType(CollectionTvRails))
            .landscapeCards,
        isFalse,
      );
      expect(folderNode(tester).hasFocus, isTrue);
      await HomeCollectionsStore.instance.saveCollections([]);
      MainPageBridge.notifyHomeSettingsChanged();
      await tester.pumpAndSettle();
      expect(find.byType(CollectionTvRails), findsNothing);
      expect(find.text('This collection has no folders'), findsOneWidget);
    },
  );

  for (final changedSession in [false, true]) {
    testWidgets(
      '2250 catalogs / 1190 sources encode off UI; changed session=$changedSession',
      (tester) async {
        late ReceivePort events;
        late Completer<bool> encodedOnUi;
        await tester.runAsync(() async {
          events = ReceivePort();
          encodedOnUi = Completer<bool>();
          events.listen((value) => encodedOnUi.complete(value as bool));
        });
        addTearDown(events.close);
        final small = sampleCollection().folders.first;
        final large = _IsolateProbeCollection(
          events.sendPort,
          Isolate.current.controlPort,
          folders: [
            small,
            HomeCollectionFolder(
              id: 'other',
              title: 'Other folder',
              sources: [
                for (var i = 0; i < 1187; i++)
                  CollectionCatalogSource(
                    addonId: 'synthetic',
                    type: 'movie',
                    catalogId: 'c$i',
                  ),
              ],
            ),
          ],
        );
        final addon = StremioAddon(
          id: 'synthetic',
          name: 'Synthetic',
          manifestUrl: 'https://example.invalid/manifest.json',
          baseUrl: 'https://example.invalid',
          resources: ['catalog'],
          catalogs: [
            for (var i = 0; i < 2250; i++)
              StremioAddonCatalog(id: 'c$i', type: 'movie', name: 'Catalog $i'),
          ],
        );
        SharedPreferences.setMockInitialValues({
          'stremio_addons_v1': jsonEncode([addon.toJson()]),
          HomeCollectionsStore.folderLayoutKey: 'rows',
        });
        await tester.runAsync(() => StremioService.instance.getAddons());
        var requests = 0;
        final native = CollectionNativeSourceService(
          tmdbToken: 'synthetic',
          resolveIds: false,
          client: MockClient((_) async {
            requests++;
            return http.Response(
              '{"results":[{"id":42,"title":"Movie"}],"total_pages":1}',
              200,
            );
          }),
        );
        addTearDown(native.close);
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: large,
              nativeSources: native,
              isTelevision: true,
              onOpenItem: (_) {},
            ),
          ),
        );
        await tester.pump();
        expect(
          await tester.runAsync(
            () => encodedOnUi.future.timeout(const Duration(seconds: 5)),
          ),
          isFalse,
        );
        expect(requests, 0, reason: 'Worker signature has not committed yet');
        if (changedSession) {
          // captureSession includes active scope even in legacy compatibility.
          ProfileRuntime.scope.value = ProfileScope(
            profileId: 'replacement',
            dataGeneration: 1,
            sessionEpoch: 1,
          );
          addTearDown(() => ProfileRuntime.scope.value = null);
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await tester.pumpAndSettle();
        expect(
          requests,
          changedSession ? 0 : 3,
          reason:
              'Only the selected folder loads; retired sessions cannot publish',
        );
        expect(
          find.byType(CollectionTvRails),
          changedSession ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final revisit in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'off-cache traversal preserves glide and visible activation: revisit=$revisit reduced=$reduced',
        (tester) async {
          final opened = <String>[];
          await mount(
            tester,
            listCount: 20,
            reduced: reduced,
            onOpen: (item) => opened.add(item.id),
          );
          await enter(tester);
          if (revisit) {
            for (var i = 0; i < 12; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pumpAndSettle();
            }
          }
          final position = vertical(tester);
          final direction = revisit
              ? LogicalKeyboardKey.arrowUp
              : LogicalKeyboardKey.arrowDown;
          var animatedFrames = 0;
          await tester.sendKeyDownEvent(direction);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 12));
          for (var i = 0; i < 9; i++) {
            final before = position.pixels;
            await tester.sendKeyRepeatEvent(direction);
            final immediate = position.pixels;
            if (!reduced) {
              expect(
                immediate,
                before,
                reason:
                    'Recycling a row must not cause an immediate vertical jump.',
              );
            }
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 12));
            final frame = position.pixels;
            expect(
              frame,
              revisit
                  ? lessThanOrEqualTo(before)
                  : greaterThanOrEqualTo(before),
            );
            if (reduced) {
              expect(frame, immediate);
            } else if (frame != before) {
              animatedFrames++;
            }
          }
          await tester.sendKeyUpEvent(direction);
          await tester.pumpAndSettle();
          if (!reduced) expect(animatedFrames, greaterThan(5));
          final expected = revisit ? 'tmdb:300' : 'tmdb:1100';
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'collection_title_$expected',
          );
          final focus =
              FocusManager.instance.primaryFocus!.context!.findRenderObject()!
                  as RenderBox;
          final viewport = tester.getRect(find.byType(CollectionTvRails));
          final top = focus.localToGlobal(Offset.zero).dy;
          expect(top, greaterThanOrEqualTo(viewport.top));
          expect(top + focus.size.height, lessThanOrEqualTo(viewport.bottom));
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(opened, [expected]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  Future<void> passVerticalCache(WidgetTester tester) async {
    await enter(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 9; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  }

  testWidgets(
    'off-cache focus wait rejects activation until destination mounts',
    (tester) async {
      final opened = <String>[], played = <String>[];
      await mount(
        tester,
        listCount: 20,
        onOpen: (item) => opened.add(item.id),
        onQuickPlay: (item) => played.add(item.id),
      );
      await passVerticalCache(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 850));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      expect(opened, isEmpty);
      expect(played, isEmpty);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:1100',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(opened, ['tmdb:1100']);
    },
  );

  for (final cancel in ['cover', 'dispose', 'interrupt']) {
    testWidgets('off-cache focus wait stops safely on $cancel', (tester) async {
      await mount(tester, listCount: 20);
      await passVerticalCache(tester);
      final focusBeforeCancellation = FocusManager.instance.primaryFocus;
      if (cancel == 'cover') {
        Navigator.of(tester.element(find.byType(CollectionTvRails))).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: TextButton(
                autofocus: true,
                onPressed: () {},
                child: const Text('Cover rails'),
              ),
            ),
          ),
        );
      } else if (cancel == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else {
        final position = vertical(tester);
        position.jumpTo(position.pixels);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (cancel == 'cover') {
        expect(
          Focus.of(tester.element(find.text('Cover rails'))).hasFocus,
          isTrue,
        );
      } else if (cancel == 'interrupt') {
        expect(
          FocusManager.instance.primaryFocus,
          same(focusBeforeCancellation),
        );
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  testWidgets(
    'long off-cache traversal accepts reversal after origin row recycles',
    (tester) async {
      final opened = <String>[];
      await mount(tester, listCount: 60, onOpen: (item) => opened.add(item.id));
      await enter(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      for (var i = 0; i < 39; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_rails_navigation',
      );
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      }
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:3600',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(opened, ['tmdb:3600']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'off-cache final animation frame mounts and focuses destination',
    (tester) async {
      await mount(tester, listCount: 20);
      await passVerticalCache(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 261));
      expect(vertical(tester).isScrollingNotifier.value, isFalse);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:1100',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final returningUp in [false, true]) {
    testWidgets(
      'off-cache reversal stays on rail input after recycling: returningUp=$returningUp',
      (tester) async {
        final opened = <String>[];
        await mount(
          tester,
          listCount: 20,
          onOpen: (item) => opened.add(item.id),
        );
        await enter(tester);
        if (returningUp) {
          for (var i = 0; i < 19; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
        }
        final oldCard = FocusManager.instance.primaryFocus!;
        final direction = returningUp
            ? LogicalKeyboardKey.arrowUp
            : LogicalKeyboardKey.arrowDown;
        final reverse = returningUp
            ? LogicalKeyboardKey.arrowDown
            : LogicalKeyboardKey.arrowUp;
        await tester.sendKeyDownEvent(direction);
        for (var i = 0; i < 18; i++) {
          await tester.sendKeyRepeatEvent(direction);
        }
        await tester.sendKeyUpEvent(direction);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 8));
        }
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'collection_rails_navigation',
        );
        // Velocity-preserving bursts no longer jump straight to the newest
        // curve's initial speed. Wait for actual recycling, not its old 48ms
        // timestamp, while still reversing before the destination takes focus.
        for (var i = 0; oldCard.context?.mounted == true && i < 24; i++) {
          await tester.pump(const Duration(milliseconds: 8));
        }
        expect(oldCard.context?.mounted, isNot(true));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'collection_rails_navigation',
        );
        await tester.sendKeyEvent(reverse);
        await tester.pumpAndSettle();
        final expected = returningUp ? 'tmdb:200' : 'tmdb:1900';
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'collection_title_$expected',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(opened, [expected]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
