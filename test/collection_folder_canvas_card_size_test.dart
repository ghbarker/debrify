import 'package:debrify/models/home_collection.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/screens/search/board_cell.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/home_rail_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'search_board_runtime_origin_test.dart' show installCatalog, page;
import 'support/prefs_harness.dart';

/// Pins the fix for the collection folder rail's card size: it used to
/// always match the classic board's `homeRailPosterWidth` formula, even
/// though Canvas — the shipped TV default — sizes its own shelf by a
/// completely different formula (`canvasRailCardSize`). A folder rail
/// rendered at classic's size never matched the Home the viewer actually
/// sees on the default layout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final folder = const HomeCollectionFolder(
    id: 'f1',
    title: 'Origin',
    heroBackdropUrl: 'https://example.invalid/backdrop.jpg',
    sources: [
      CollectionCatalogSource(
        addonId: 'board.origin',
        type: 'movie',
        catalogId: 'rail',
      ),
    ],
  );
  final collection = HomeCollection(
    id: 'c1',
    title: 'Streaming',
    folders: [folder],
  );

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CollectionFolderScreen(
        collection: collection,
        onOpenItem: (_) {},
        isTelevision: true,
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> runBooted(
    WidgetTester tester,
    Future<void> Function() setStyle,
    Future<void> Function() body,
  ) async {
    final unexpected = <String>[];
    await http.runWithClient(() async {
      await installLegacyPrefs();
      await setStyle();
      await installCatalog();
      await boot(tester);
      expect(tester.takeException(), isNull);
      await body();
      expect(unexpected, isEmpty);
    }, () => MockClient((request) async {
      final url = request.url.toString();
      if (url == 'https://board-origin.invalid/catalog/movie/rail.json') {
        return page(0, 12);
      }
      unexpected.add(url);
      return http.Response('{}', 404);
    }));
  }

  testWidgets(
    'classic TV Home Layout: folder rail cards match homeRailPosterWidth',
    (tester) async {
      await runBooted(tester, () => StorageService.setTvHomeStyle('classic'),
          () async {
        final cell = find.byType(BoardCell).first;
        expect(cell, findsOneWidget);
        final size = tester.getSize(cell);
        final expectedW = homeRailPosterWidth(
          tester.element(cell),
          isTelevision: true,
        );
        expect(size.width, closeTo(expectedW, 0.5));
        expect(size.height, closeTo(expectedW * 1.5, 0.5));
      });
    },
  );

  testWidgets(
    'Canvas TV Home Layout: folder rail cards match canvasRailCardSize, '
    'not the classic formula',
    (tester) async {
      await runBooted(tester, () async {
        await StorageService.setTvHomeStyle('canvas');
        await HomePrefs.setHomeCardOrientation(HomeCardOrientation.portrait);
      }, () async {
        final cell = find.byType(BoardCell).first;
        expect(cell, findsOneWidget);
        final size = tester.getSize(cell);
        final expected = canvasRailCardSize(
          tester.element(cell),
          landscapeCards: false,
        );
        expect(size.width, closeTo(expected.width, 0.5));
        expect(size.height, closeTo(expected.height, 0.5));
        // Not the classic figure — the two formulas disagree at 1080p.
        final classicW = homeRailPosterWidth(
          tester.element(cell),
          isTelevision: true,
        );
        expect(size.width, isNot(closeTo(classicW, 0.5)));
      });
    },
  );
}
