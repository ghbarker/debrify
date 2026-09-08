import 'package:debrify/models/home_collection.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/widgets/collections/rail_header_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'search_board_runtime_origin_test.dart' show installCatalog, page;
import 'support/prefs_harness.dart';

/// Pins the fix for the collection folder rail's header: on TV it used to be
/// pressable — SELECT opened a full catalog browse — even though no Home
/// board row is a control; a row's name there is a plain label. Off TV the
/// tap-to-browse affordance a list title has always had is unchanged.
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

  Future<void> boot(WidgetTester tester, {required bool tv}) async {
    tester.view.physicalSize = tv ? const Size(1920, 1080) : const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CollectionFolderScreen(
        collection: collection,
        onOpenItem: (_) {},
        isTelevision: tv,
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> runBooted(WidgetTester tester, bool tv) async {
    final unexpected = <String>[];
    await http.runWithClient(() async {
      await installLegacyPrefs();
      await installCatalog();
      await boot(tester, tv: tv);
      expect(tester.takeException(), isNull);
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

  testWidgets('TV: the rail header is not pressable', (tester) async {
    await runBooted(tester, true);
    final header = tester.widget<RailHeaderFocus>(find.byType(RailHeaderFocus).last);
    expect(header.onPressed, isNull);
  });

  testWidgets('off TV: the rail header still opens the catalog browse', (
    tester,
  ) async {
    await runBooted(tester, false);
    final header = tester.widget<RailHeaderFocus>(find.byType(RailHeaderFocus).last);
    expect(header.onPressed, isNotNull);
  });
}
