import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Regression for #107, through actual Home State + CW controller. The only
// behavior dependency replaced is preference IO. No source scans, private
// State invocations, copied lifecycle code, or microtask-ordinal scheduling.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    SecretVault.debugReset(deviceIdOverride: 'cw-disposal-test');
    root = await Directory.systemTemp.createTemp('cw-disposal-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
    // Keep the loading screen's font offline; typography is not under test.
    final data = await rootBundle.load('AssetManifest.bin');
    final manifest = Map<Object?, Object?>.from(
      const StandardMessageCodec().decodeMessage(data) as Map,
    );
    const alias = 'assets/fonts/Poppins-SemiBold.ttf';
    final font = await rootBundle.load('assets/fonts/Poppins-Regular.ttf');
    manifest[alias] = [
      {'asset': alias},
    ];
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(manifest);
      }
      if (key == alias) return font;
      return messenger.delegate.send('flutter/assets', message);
    });
    rootBundle.evict('AssetManifest.bin');
    await StorageService.setTvHomeStyle('classic');
    await StorageService.setHomeHeroTrailerEnabled(false);
  });

  tearDown(() async {
    messenger.setMockMessageHandler('flutter/assets', null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    rootBundle.evict('AssetManifest.bin');
    ProfileSessionMemory.clearAll();
    StorageService.resetProfileCaches();
    SecretVault.debugReset();
    AppStorage.debugReset();
    ProfileRuntime.debugReset();
    await root.delete(recursive: true);
  });

  for (final television in [false, true]) {
    testWidgets(
      'disposed Home ignores held merge preferences (TV=$television)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1920, 1080);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final release = Completer<void>();
        final reached = <String>[];
        final returned = <String>[];
        var hold = false;
        var observeContinuation = false;
        var hostConfigurationReads = 0;
        Future<bool> readMergedRows(String provider) async {
          final value = await StorageService.getHomeCwMergedRows(provider);
          if (hold) {
            reached.add(provider);
            await release.future;
            returned.add(provider);
          }
          return value;
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              home: _ObservedHome(
                television: television,
                readCwMergedRows: readMergedRows,
                onConfigurationRead: () {
                  if (observeContinuation) hostConfigurationReads++;
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final host = tester.state<State<SearchScreenHost>>(
            find.byType(_ObservedHome),
          );
          expect(host.mounted, isTrue);

          // All initialization reads have finished. Hold only the settings
          // reload, after the earlier card-preference mounted check has passed.
          await StorageService.setHomeCwMergedRows('local', true);
          hold = true;
          MainPageBridge.notifyHomeSettingsChanged();
          await tester.pumpAndSettle();
          expect(reached, ['local', 'trakt', 'simkl', 'mdblist']);
          expect(returned, isEmpty);
          expect(host.mounted, isTrue);

          // Dispose before any held IO returns, then isolate the post-disposal
          // phase from the host's legitimate synchronous dispose/cache work.
          await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
          await tester.pumpAndSettle();
          expect(host.mounted, isFalse);
          final prefs = await SharedPreferences.getInstance();
          Map<String, Object?> snapshot() => {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          };
          final cacheBeforeRelease = snapshot();
          final ownerBeforeRelease = ProfileSessionMemory.captureOwner();
          observeContinuation = true;
          var hostBuilds = 0;
          final previousRebuild = debugOnRebuildDirtyWidget;
          debugOnRebuildDirtyWidget = (element, builtOnce) {
            previousRebuild?.call(element, builtOnce);
            if (element.widget is SearchScreenHost) hostBuilds++;
          };
          try {
            release.complete();
            await tester.pumpAndSettle();
            // A second pump also checks continuations following the helper's
            // return. State retains its widget after unmount, so absence of an
            // exception alone would miss the unwanted host/cache work.
            await tester.pump();
            expect(returned, ['local', 'trakt', 'simkl', 'mdblist']);
            expect(tester.takeException(), isNull);
            expect(
              hostConfigurationReads,
              0,
              reason:
                  'The disposed host must return before reading its '
                  'configuration to reload hero prefs/default view',
            );
            expect(hostBuilds, 0);
            expect(snapshot(), cacheBeforeRelease);
            expect(ProfileSessionMemory.captureOwner(), ownerBeforeRelease);
            expect(find.text('Replacement'), findsOneWidget);
            expect(find.byType(_ObservedHome), findsNothing);
            // A later notification must not start more preference IO. This does
            // not prove listener removal: the mounted guard also suppresses IO.
            MainPageBridge.notifyHomeSettingsChanged();
            await tester.pumpAndSettle();
            expect(reached, ['local', 'trakt', 'simkl', 'mdblist']);
          } finally {
            debugOnRebuildDirtyWidget = previousRebuild;
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );
  }
}

// Observe the first host action after the merge-preference await. The getter
// returns the real configuration unchanged; createState/build/dispose and all
// reload logic are inherited from lib, not replaced with a test implementation.
class _ObservedHome extends SearchScreenHost {
  const _ObservedHome({
    required this.television,
    required this.onConfigurationRead,
    required super.readCwMergedRows,
  });

  final bool television;
  final VoidCallback onConfigurationRead;

  @override
  bool get isTelevision {
    onConfigurationRead();
    return television;
  }
}
