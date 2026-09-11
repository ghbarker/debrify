import 'dart:convert';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/services/collection_native_source_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/theme/tv_motion_scope.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

HomeCollection sampleCollection() => HomeCollection(
  id: 'sample',
  title: 'Sample collection',
  folders: [
    HomeCollectionFolder(
      id: 'folder',
      title: 'Folder',
      sources: [
        for (var i = 1; i <= 3; i++)
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
    TvMotionProfile motion = TvMotionProfile.snappy,
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
    Widget screen() => MediaQuery(
      data: MediaQueryData(
        size: const Size(960, 540),
        disableAnimations: reduced,
      ),
      child: TvMotionScope(
        profile: motion,
        child: CollectionFolderScreen(
          collection: sampleCollection(),
          nativeSources: native,
          isTelevision: tv,
          onOpenItem: onOpen ?? (_) {},
          onQuickPlay: onQuickPlay,
        ),
      ),
    );
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

  Future<void> distantColumn(WidgetTester tester) async {
    await enter(tester);
    for (var i = 0; i < 17; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_title_tmdb:117',
    );
  }

  for (final motion in [TvMotionProfile.snappy, TvMotionProfile.smooth]) {
    testWidgets(
      'adjacent cached row reveals distant column and opens focused card: $motion',
      (tester) async {
        final opened = <String>[];
        await mount(
          tester,
          motion: motion,
          onOpen: (item) => opened.add(item.id),
        );
        await distantColumn(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final focusBeforeSelect =
            FocusManager.instance.primaryFocus?.debugLabel;
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(opened, ['tmdb:217']);
        expect(focusBeforeSelect, 'collection_title_${opened.single}');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final orientation in HomeCardOrientation.values) {
    testWidgets(
      'Smooth animates adjacent row when carried column is not mounted: $orientation',
      (tester) async {
        await StorageService.setHomeCardOrientation(orientation);
        await mount(tester, motion: TvMotionProfile.smooth);
        await distantColumn(tester);
        if (orientation == HomeCardOrientation.landscape) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'collection_title_tmdb:217',
          );
        }
        final position = vertical(tester);
        final before = position.pixels;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final intermediate = position.pixels;
        await tester.pumpAndSettle();
        final end = position.pixels;
        expect(end, greaterThan(before));
        expect(intermediate, greaterThan(before));
        expect(intermediate, lessThan(end));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          orientation == HomeCardOrientation.landscape
              ? 'collection_title_tmdb:317'
              : 'collection_title_tmdb:217',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Select during deferred focus never opens an unfocused destination',
    (tester) async {
      final opened = <String>[];
      await mount(tester, onOpen: (item) => opened.add(item.id));
      await distantColumn(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      // No layout between direction and activation: the destination card is
      // outside the next row's horizontal cache and has not mounted yet.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(opened, isEmpty);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_tmdb:217',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(opened, ['tmdb:217']);
    },
  );

  testWidgets('a newer direction cancels deferred column focus', (
    tester,
  ) async {
    await mount(tester);
    await distantColumn(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'collection_title_tmdb:117',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deferred column focus cannot steal focus from a covering route',
    (tester) async {
      await mount(tester);
      await distantColumn(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      final navigator = Navigator.of(
        tester.element(find.byType(CollectionTvRails)),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TextButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Cover'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text('Cover'))).hasFocus, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot(startsWith('collection_title_')),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
