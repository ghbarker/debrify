import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Characterization follow-up to #90, NOT a pre-extraction commit.
// Run unchanged on ee33b3cba678ab914ed242e484cc9e5aed15e3c0, the direct
// parent of move 65b970026561cc768da9241abb101e9c0dd2b893, and current main.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    root = await Directory.systemTemp.createTemp('keyword-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    LocalEngineStorage.instance.resetProfileScope();
    EngineRegistry.instance.invalidateProfileScope();
    await EngineRegistry.instance.initialize();
  });

  tearDown(() async {
    ProfileSessionMemory.clearAll();
    EngineRegistry.instance.invalidateProfileScope();
    LocalEngineStorage.instance.resetProfileScope();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await root.delete(recursive: true);
  });

  testWidgets('keyword entry is submit-based and clearing dismisses failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SearchScreen(searchMode: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keyword'));
    await tester.pumpAndSettle();
    expect(find.text('Keyword torrent search'), findsOneWidget);
    expect(find.text('Search torrents by keyword'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  origin fixture  ');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Keyword torrent search'), findsOneWidget);
    expect(find.text('Search failed'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Search failed'), findsOneWidget);
    expect(
      find.text(
        'No sources enabled. Turn on at least one source in '
        'Sources, then try again.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Search failed'), findsNothing);
    expect(find.text('Keyword torrent search'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'imported keyword results render and Name resets sort direction',
    (tester) async {
      // Import the same YAML a user can import. Only the HTTP response is fake;
      // lib owns request construction, parsing, merging, sorting and rendering.
      await tester.runAsync(() async {
        await LocalEngineStorage.instance.saveEngine(
          engineId: 'origin_fixture',
          fileName: 'origin_fixture.yaml',
          yamlContent: _engineYaml,
          displayName: 'Origin Fixture',
        );
        await EngineRegistry.instance.reload();
      });
      expect(EngineRegistry.instance.getEngineIds(), ['origin_fixture']);
      await tester.pumpWidget(
        const MaterialApp(home: SearchScreen(searchMode: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keyword'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  origin fixture  ');

      final requests = <Uri>[];
      await http.runWithClient(
        () async {
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'infohash': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  'name': 'Zulu Origin 1080p',
                  'seeders': 90,
                  'size_bytes': 2000000000,
                },
                {
                  'infohash': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                  'name': 'Alpha Origin 720p',
                  'seeders': 5,
                  'size_bytes': 1000000000,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(requests, [
        Uri.parse('https://origin-fixture.invalid/search?q=origin+fixture'),
      ]);
      expect(find.text('Zulu Origin 1080p'), findsOneWidget);
      expect(find.text('Alpha Origin 720p'), findsOneWidget);

      Future<void> chooseSort(String label) async {
        await tester.tap(find.textContaining('Sort ·'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }

      await chooseSort('Seeders');
      expect(
        tester.getTopLeft(find.text('Zulu Origin 1080p')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha Origin 720p')).dy),
      );
      await chooseSort('Name');
      expect(
        tester.getTopLeft(find.text('Alpha Origin 720p')).dy,
        lessThan(tester.getTopLeft(find.text('Zulu Origin 1080p')).dy),
        reason: 'Name starts ascending even after descending Seeders',
      );
      expect(requests, hasLength(1), reason: 'Sorting uses the loaded results');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

const _engineYaml = '''
id: origin_fixture
display_name: Origin Fixture
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://origin-fixture.invalid/search
  method: GET
query_params:
  type: query_params
  param_name: q
response_format:
  type: direct_json
  results_path: results
field_mappings:
  infohash: infohash
  name: name
  seeders: seeders
  size_bytes: size_bytes
''';
