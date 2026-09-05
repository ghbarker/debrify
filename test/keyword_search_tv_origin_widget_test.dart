import 'dart:io';

import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Post-merge #90 characterization. Run unchanged on original move parent
// ee33b3cba678ab914ed242e484cc9e5aed15e3c0 and the submitted #101 head.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    root = await Directory.systemTemp.createTemp('keyword-tv-origin-');
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

  testWidgets(
    'TV DPAD enters Keyword and navigates field, Sources and toolbar',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousSidebar = MainPageBridge.focusTvSidebar;
      var sidebarCalls = 0;
      MainPageBridge.focusTvSidebar = () => sidebarCalls++;
      addTearDown(() => MainPageBridge.focusTvSidebar = previousSidebar);

      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(searchMode: true, isTelevision: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        MediaQuery.sizeOf(tester.element(find.byType(SearchScreenHost))),
        const Size(1920, 1080),
      );
      // Seed the field as if the shell handed focus into the Search tab. Every
      // subsequent transition uses real keyboard events, never State methods.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      void expectFocusedLabel(String label) {
        final focusedWidget =
            FocusManager.instance.primaryFocus!.context!.widget;
        expect(
          find.descendant(
            of: find.byWidget(focusedWidget),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }

      await press(LogicalKeyboardKey.arrowUp);
      expectFocusedLabel('Catalog');
      await press(LogicalKeyboardKey.arrowRight);
      expectFocusedLabel('Keyword');
      await press(LogicalKeyboardKey.enter);
      expect(find.text('Keyword torrent search'), findsOneWidget);
      expect(find.text('Search torrents by keyword'), findsOneWidget);
      await press(LogicalKeyboardKey.arrowUp);
      expect(field.focusNode.hasFocus, isTrue);
      await press(LogicalKeyboardKey.arrowDown);
      expect(field.focusNode.hasFocus, isFalse);
      expectFocusedLabel('Sources');
      await press(LogicalKeyboardKey.arrowLeft);
      expect(sidebarCalls, 1, reason: 'One key press hands off exactly once');
      await press(LogicalKeyboardKey.arrowUp);
      expect(field.focusNode.hasFocus, isTrue);
      expect(find.text('Keyword torrent search'), findsOneWidget);

      // One ordinary imported engine makes the results toolbar reachable. Only
      // transport is mocked; request/parse/render/focus all remain in lib.
      await tester.runAsync(() async {
        await LocalEngineStorage.instance.saveEngine(
          engineId: 'tv_origin',
          fileName: 'tv_origin.yaml',
          yamlContent: _engineYaml,
          displayName: 'TV Origin',
        );
        await EngineRegistry.instance.reload();
      });
      var requests = 0;
      await tester.enterText(find.byType(TextField), 'focus fixture');
      await http.runWithClient(
        () async {
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          requests++;
          expect(
            request.url,
            Uri.parse('https://tv-origin.invalid/search?q=focus+fixture'),
          );
          return http.Response(
            '''{"results":[{
        "infohash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "name":"Focus Fixture 1080p", "seeders":12, "size_bytes":1000000000
      }]}''',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(requests, 1);
      // Both original State and extracted screen settle on Sort, not the row.
      expectFocusedLabel('Sort · Relevance');
      await press(LogicalKeyboardKey.arrowDown);
      expectFocusedLabel('Focus Fixture 1080p');
      await press(LogicalKeyboardKey.arrowUp);
      expectFocusedLabel('Sort · Relevance');
      await press(LogicalKeyboardKey.arrowRight);
      expectFocusedLabel('Filters');
      await press(LogicalKeyboardKey.arrowDown);
      expectFocusedLabel('Focus Fixture 1080p');
      await press(LogicalKeyboardKey.arrowUp);
      expectFocusedLabel('Sort · Relevance');
      await press(LogicalKeyboardKey.arrowUp);
      expect(field.focusNode.hasFocus, isTrue);
      expect(requests, 1, reason: 'DPAD navigation must not re-run search');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

const _engineYaml = '''
id: tv_origin
display_name: TV Origin
icon: travel_explore
categories: [general]
capabilities:
  keyword_search: true
  imdb_search: false
  series_support: false
api:
  base_url: https://tv-origin.invalid/search
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
