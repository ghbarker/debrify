import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';
import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/screens/search/source_binding_routes.dart';
import 'package:debrify/widgets/sources/source_binding_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Drives the real pre-correction dialog and observes its actual route builder.
// Cloud screen constructors are inspected without mounting network-heavy States.
class _Routes extends NavigatorObserver {
  final events = <String>[];
  Widget? destination;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('push');

    if (previousRoute != null && route is MaterialPageRoute) {
      destination = route.builder(navigator!.context);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('pop');
  }
}

const _old = SeriesSource(
  torrentHash: 'old',
  torrentName: 'Old',
  debridService: 'realdebrid',
  debridTorrentId: '1',
  boundAt: 1,
);
const _picked = SeriesSource(
  torrentHash: 'new',
  torrentName: 'Picked',
  debridService: 'realdebrid',
  debridTorrentId: '2',
  boundAt: 2,
);

Future<void> _open(
  WidgetTester tester,
  _Routes routes, {
  required String type,
  required bool edit,
  required Future<void> Function() refresh,
  bool Function()? mounted,
}) async {
  final credentialsRead = Completer<void>();
  bool hostMounted() {
    if (!credentialsRead.isCompleted) credentialsRead.complete();
    return mounted?.call() ?? true;
  }

  final item = StremioMeta(id: 'tt1', type: type, name: 'Pinned title');
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [routes],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            if (edit) {
              unawaited(
                SourceBindingDialogs.showEdit(
                  cloudRoutes: SourceBindingRoutes.cloud,
                  context: context,
                  item: item,
                  initial: [_old],
                  onRefreshBound: refresh,
                  onTorrentSearch: (_) {},
                  onKeywordSearch: (_) {},
                  onSnack: (_) {},
                  isHostMounted: hostMounted,
                ),
              );
            } else {
              unawaited(
                SourceBindingDialogs.showAdd(
                  cloudRoutes: SourceBindingRoutes.cloud,
                  context: context,
                  item: item,
                  onRefreshBound: refresh,
                  onTorrentSearch: (_) {},
                  onKeywordSearch: (_) {},
                  onSnack: (_) {},
                  isHostMounted: hostMounted,
                ),
              );
            }
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  Future<void> waitForCredentials() async {
    for (var i = 0; i < 100 && !credentialsRead.isCompleted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(
      credentialsRead.isCompleted,
      isTrue,
      reason: 'credential reads completed',
    );
  }

  await tester.tap(find.text('Open'));
  if (!edit) await waitForCredentials();
  await tester.pumpAndSettle();
  if (edit) {
    await tester.tap(
      find.text(type == 'movie' ? 'Change Source' : 'Add Source'),
    );
    await waitForCredentials();
    await tester.pumpAndSettle();
  }
}

Future<void> Function(SeriesSource) _selection(Widget widget, String provider) {
  switch (provider) {
    case 'Real-Debrid':
      final screen = widget as DebridDownloadsScreen;
      expect(screen.isPushedRoute, isTrue);
      expect(screen.selectSourceMode, isTrue);
      expect(screen.initialSearchQuery, 'Pinned title');
      return screen.onSourceSelected! as Future<void> Function(SeriesSource);
    case 'TorBox':
      final screen = widget as TorboxDownloadsScreen;
      expect(screen.isPushedRoute, isTrue);
      expect(screen.selectSourceMode, isTrue);
      expect(screen.initialSearchQuery, 'Pinned title');
      return screen.onSourceSelected! as Future<void> Function(SeriesSource);
    case 'Premiumize':
      final screen = widget as PremiumizeFilesScreen;
      expect(screen.isPushedRoute, isTrue);
      expect(screen.selectSourceMode, isTrue);
      expect(screen.initialSearchQuery, 'Pinned title');
      return screen.onSourceSelected!;
    case 'AllDebrid':
      final screen = widget as AllDebridFilesScreen;
      expect(screen.isPushedRoute, isTrue);
      expect(screen.selectSourceMode, isTrue);
      expect(screen.initialSearchQuery, 'Pinned title');
      return screen.onSourceSelected!;
    case 'PikPak':
      // PikPak has no initialSearchQuery constructor parameter.
      final screen = widget as PikPakFilesScreen;
      expect(screen.isPushedRoute, isTrue);
      expect(screen.selectSourceMode, isTrue);
      return screen.onSourceSelected!;
    default:
      throw StateError(provider);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'v1-route-pin');
    final credential = await SecretVault.seal('fixture-key');
    SharedPreferences.setMockInitialValues({
      'real_debrid_api_key': credential,
      'torbox_api_key': credential,
      'premiumize_api_key': credential,
      'premiumize_integration_enabled': true,
      'alldebrid_api_key': credential,
      'pikpak_enabled': true,
    });
  });

  for (final provider in [
    'Real-Debrid',
    'TorBox',
    'Premiumize',
    'AllDebrid',
    'PikPak',
  ]) {
    for (final type in ['movie', 'series']) {
      for (final edit in [false, true]) {
        testWidgets(
          '$provider $type via ${edit ? "edit" : "add"} preserves route and persist-before-refresh',
          (tester) async {
            tester.view.physicalSize = const Size(1200, 1600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await SeriesSourceService.setSources('tt1', [_old]);
            final routes = _Routes();
            final releaseRefresh = Completer<void>();
            var refreshes = 0;
            List<String>? sourcesAtRefresh;
            await _open(
              tester,
              routes,
              type: type,
              edit: edit,
              refresh: () async {
                sourcesAtRefresh = (await SeriesSourceService.getSources(
                  'tt1',
                )).map((s) => s.torrentHash).toList();
                refreshes++;
                await releaseRefresh.future;
              },
            );
            routes.events.clear();
            await tester.tap(find.text(provider));
            expect(routes.events, ['pop', 'push']);
            final select = _selection(routes.destination!, provider);
            // Remove the navigator before the next frame can mount the cloud State.
            await tester.pumpWidget(const SizedBox.shrink());
            var completed = false;
            final saving = select(_picked).then((_) => completed = true);
            await tester.pump();
            expect(refreshes, 1);
            expect(
              sourcesAtRefresh,
              type == 'movie' ? ['new'] : ['old', 'new'],
            );
            expect(completed, isFalse);
            releaseRefresh.complete();
            await saving;
            expect(completed, isTrue);
          },
        );
      }
    }
  }

  testWidgets('cancel picker writes nothing and does not refresh or route', (
    tester,
  ) async {
    await SeriesSourceService.setSources('tt1', [_old]);
    final routes = _Routes();
    var refreshes = 0;
    await _open(
      tester,
      routes,
      type: 'movie',
      edit: false,
      refresh: () async {
        refreshes++;
      },
    );
    routes.events.clear();
    routes.navigator!.pop();
    await tester.pumpAndSettle();
    expect(routes.destination, isNull);
    expect(routes.events, ['pop']);
    expect(refreshes, 0);
    expect(
      (await SeriesSourceService.getSources('tt1')).single.torrentHash,
      'old',
    );
  });

  testWidgets('unmounted host after credential reads never opens picker', (
    tester,
  ) async {
    final routes = _Routes();
    await _open(
      tester,
      routes,
      type: 'movie',
      edit: false,
      mounted: () => false,
      refresh: () async => fail('unexpected refresh'),
    );
    expect(find.text('Torrent Search (IMDb)'), findsNothing);
    expect(routes.destination, isNull);
  });

  testWidgets(
    'Premiumize needs toggle as well as key; other cloud choices remain',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('premiumize_integration_enabled', false);
      final routes = _Routes();
      await _open(
        tester,
        routes,
        type: 'movie',
        edit: false,
        refresh: () async {},
      );
      expect(find.text('Premiumize'), findsNothing);
      for (final label in ['Real-Debrid', 'TorBox', 'AllDebrid', 'PikPak']) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );
}
