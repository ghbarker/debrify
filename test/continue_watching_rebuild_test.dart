import 'package:debrify/services/storage/playback_progress_store.dart';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/search/continue_watching_row.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CW refresh builds Home and its row once and preserves focus', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('cw-rebuild-'),
    ))!;
    final previousFonts = GoogleFonts.config.allowRuntimeFetching;
    final previousRebuild = debugOnRebuildDirtyWidget;
    final previousRevision = StorageService.localCompletionRevision.value;
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    SecretVault.debugReset(deviceIdOverride: 'cw-rebuild-test');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
    // Typography is outside this pin; satisfy the loading screen's font from
    // the bundled regular face without fetching a font from the network.
    await tester.runAsync(() async {
      final data = await rootBundle.load('AssetManifest.bin');
      final manifest = Map<Object?, Object?>.from(
        const StandardMessageCodec().decodeMessage(data) as Map,
      );
      final aliases = [
        for (final weight in ['SemiBold', 'ExtraBold', 'Bold', 'Medium'])
          'assets/fonts/Poppins-$weight.ttf',
      ];
      final font = await rootBundle.load('assets/fonts/Poppins-Regular.ttf');
      for (final alias in aliases) {
        manifest[alias] = [
          {'asset': alias},
        ];
      }
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key == 'AssetManifest.bin') {
          return const StandardMessageCodec().encodeMessage(manifest);
        }
        if (aliases.contains(key)) return font;
        return messenger.delegate.send('flutter/assets', message);
      });
      rootBundle.evict('AssetManifest.bin');
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(() async {
      debugOnRebuildDirtyWidget = previousRebuild;
      messenger.setMockMessageHandler('flutter/assets', null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      rootBundle.evict('AssetManifest.bin');
      GoogleFonts.config.allowRuntimeFetching = previousFonts;
      StorageService.localCompletionRevision.value = previousRevision;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      ProfileSessionMemory.clearAll();
      StorageService.resetProfileCaches();
      SecretVault.debugReset();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      await tester.runAsync(() => root.delete(recursive: true));
    });
    await StorageService.setTvHomeStyle('classic');
    await StorageService.setHomeHeroTrailerEnabled(false);
    await StorageService.setHomeContinueWatchingEnabled(true);
    Future<void> save(String id, String title) =>
        PlaybackProgressStore.saveContinueWatchingItem(
          imdbId: id,
          title: title,
          contentType: 'movie',
        );
    await save('tt0000001', 'First movie');
    await save('tt0000002', 'Second movie');

    // Poster placeholders can keep ticking. Measure across a bounded window,
    // including subsequent frames, rather than waiting for all animations.
    Future<void> pumpFrames() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    try {
      await tester.pumpWidget(
        const MaterialApp(home: SearchScreen(isTelevision: true)),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await pumpFrames();
      final rowFinder = find.byType(ContinueWatchingRow);
      expect(rowFinder, findsOneWidget);
      ContinueWatchingRow row() => tester.widget(rowFinder);
      final firstNode = row().row.nodes.first;
      firstNode.requestFocus();
      await pumpFrames();
      expect(firstNode.hasFocus, isTrue);

      var hostBuilds = 0;
      var rowBuilds = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousRebuild?.call(element, builtOnce);
        if (element.widget is SearchScreenHost) hostBuilds++;
        if (element.widget is ContinueWatchingRow) rowBuilds++;
      };
      // The public completion signal runs the actual local controller loader.
      // No copied loader, fake host, or private-State method invocation.
      await save('tt0000002', 'Updated movie');
      StorageService.localCompletionRevision.value++;
      await pumpFrames();
      expect(row().row.items.first.name, 'Updated movie');
      expect(find.text('Updated movie'), findsWidgets);
      expect(hostBuilds, 1);
      expect(rowBuilds, 1);
      expect(row().row.nodes.first, same(firstNode));
      expect(firstNode.hasFocus, isTrue);

      // Real DPAD still traverses the surviving row after the refresh.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await pumpFrames();
      expect(row().row.nodes[1].hasFocus, isTrue);

      // Host notification is also needed when the last row disappears.
      hostBuilds = 0;
      rowBuilds = 0;
      await StorageService.setHomeContinueWatchingEnabled(false);
      StorageService.localCompletionRevision.value++;
      await pumpFrames();
      expect(rowFinder, findsNothing);
      expect(hostBuilds, 1);
      expect(rowBuilds, 0);
      expect(tester.takeException(), isNull);
    } finally {
      debugOnRebuildDirtyWidget = previousRebuild;
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpFrames();
      // Let the image cache's delayed housekeeping finish after unmount.
      await tester.pump(const Duration(seconds: 11));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  });
}
