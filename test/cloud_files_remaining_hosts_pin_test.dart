import 'dart:io';

import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/screens/cloud/cloud_browse_select_source.dart';
import 'package:debrify/screens/cloud_files/alldebrid_files_source.dart';
import 'package:debrify/screens/cloud_files/cloud_files_screen.dart';
import 'package:debrify/screens/cloud_files/pikpak_files_source.dart';
import 'package:debrify/screens/cloud_files/premiumize_files_source.dart';
import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';
import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G4 step 2 characterisation of Premiumize / AllDebrid / PikPak files
/// screens **before** they route onto [CloudFilesScreen].
///
/// Quirks pinned here (keep, do not "fix"):
/// * Selection bars stay on the host files (shape-manifest floor).
///   PM + AD use `BorderRadius.circular(12)`; PikPak uses `app.shape.br(12)`.
/// * Unconfigured Premiumize AppBar stays `'Premiumize'` even in
///   select-source mode (the `'Select Premiumize Source'` title is
///   configured-only).
/// * Pushed Premiumize first frame is `'Opening folder...'` (not torrent).
/// * AllDebrid always paints chrome: select-source title + magnet/web
///   sections, then `'Add your AllDebrid API key in Settings first.'`.
/// * AllDebrid search is live on both sections (`Search your magnets...`
///   / `Search your links...`); query is not torrent-only.
/// * PikPak has no `initialSearchQuery`; bind drops the query.
/// * PikPak deep-link splash is folder copy; 10s fail snack is
///   `'Failed to open folder. Please try again.'`.
/// * Sidebar destination ids stay `premiumize` / `alldebrid` / `pikpak`.
/// * Bind playback ids stay `premiumize` / `alldebrid` / `pikpak`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> drainOpenTimeout(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
  }

  Widget host(Widget screen) => MaterialApp(home: screen);

  Future<void> asyncBind(SeriesSource _) async {}

  group('PremiumizeFilesScreen', () {
    test('pushed root while initialLoad uses folder splash, not torrent', () {
      final src = _readHost(
        'lib/screens/premiumize/premiumize_files_screen.dart',
      );
      expect(
        src.contains('widget.isPushedRoute && _isAtRoot && _initialLoad'),
        isTrue,
      );
      expect(src.contains("title: const Text('Opening folder...')"), isTrue);
      expect(src.contains('Opening torrent...'), isFalse);
    });

    testWidgets('unconfigured copy ignores select-source title', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PremiumizeFilesScreen(
            isPushedRoute: true,
            selectSourceMode: true,
            initialSearchQuery: 'Show Title',
            onSourceSelected: asyncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PremiumizeFilesScreen), findsOneWidget);
      expect(find.text('Premiumize'), findsOneWidget);
      expect(find.text('Select Premiumize Source'), findsNothing);
      expect(find.text('Premiumize Not Configured'), findsOneWidget);
      expect(
        find.text(
          'Add your Premiumize API key in Settings to view and manage your cloud.',
        ),
        findsOneWidget,
      );
      expect(find.text('Go to Settings'), findsOneWidget);
      // Sections and search only exist once configured.
      expect(find.text('My Files'), findsNothing);
      expect(find.text('Transfers'), findsNothing);
      expect(find.text('Show Title'), findsNothing);
      expect(find.text('0 selected'), findsNothing);
      expect(find.text('Select All'), findsNothing);
    });

    testWidgets('tab root has no select-source title', (tester) async {
      await tester.pumpWidget(host(const PremiumizeFilesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Select Premiumize Source'), findsNothing);
      expect(find.text('Premiumize'), findsOneWidget);
      expect(find.text('Premiumize Not Configured'), findsOneWidget);
    });
  });

  group('AllDebridFilesScreen', () {
    testWidgets('select-source keeps magnet + web libraries and key error', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AllDebridFilesScreen(
            isPushedRoute: true,
            selectSourceMode: true,
            initialSearchQuery: 'Magnet query',
            onSourceSelected: asyncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AllDebridFilesScreen), findsOneWidget);
      expect(find.text('Select AllDebrid Source'), findsOneWidget);
      expect(find.text('Torrent Downloads'), findsOneWidget);
      expect(find.text('Web Downloads'), findsOneWidget);
      expect(
        find.text('Add your AllDebrid API key in Settings first.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      // Query is applied on the magnet section (not torrent-only drop).
      expect(find.text('Magnet query'), findsOneWidget);
      expect(find.text('Search your magnets...'), findsOneWidget);
      expect(find.text('0 selected'), findsNothing);
      expect(find.text('Select All'), findsNothing);

      await tester.tap(find.text('Web Downloads'));
      await tester.pumpAndSettle();

      expect(
        find.text('Add your AllDebrid API key in Settings first.'),
        findsOneWidget,
      );
      expect(find.text('Magnet query'), findsNothing);
      expect(find.text('Search your links...'), findsNothing);
      expect(find.text('Select AllDebrid Source'), findsOneWidget);
    });

    testWidgets('tab root has no select-source title; sections stay', (
      tester,
    ) async {
      await tester.pumpWidget(host(const AllDebridFilesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Select AllDebrid Source'), findsNothing);
      expect(find.text('Torrent Downloads'), findsOneWidget);
      expect(find.text('Web Downloads'), findsOneWidget);
      expect(
        find.text('Add your AllDebrid API key in Settings first.'),
        findsOneWidget,
      );
    });
  });

  group('PikPakFilesScreen', () {
    testWidgets('unconfigured empty copy', (tester) async {
      await tester.pumpWidget(
        host(
          PikPakFilesScreen(
            isPushedRoute: true,
            selectSourceMode: true,
            onSourceSelected: asyncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PikPakFilesScreen), findsOneWidget);
      expect(find.text('PikPak Files'), findsOneWidget);
      expect(find.text('Select PikPak Source'), findsNothing);
      expect(find.text('PikPak Not Configured'), findsOneWidget);
      expect(
        find.text(
          'Configure your PikPak account in Settings to view and manage files.',
        ),
        findsOneWidget,
      );
      expect(find.text('Go to Settings'), findsOneWidget);
      expect(find.text('0 selected'), findsNothing);
      // Pushed-route always schedules the 10s deep-link timer.
      await drainOpenTimeout(tester);
    });

    testWidgets('deep-link splash while a folder target is pending', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const PikPakFilesScreen(
            isPushedRoute: true,
            initialFolderId: 'folder-1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Opening folder...'), findsOneWidget);
      expect(find.text('Loading folder contents...'), findsOneWidget);
      expect(find.text('Opening torrent...'), findsNothing);

      await drainOpenTimeout(tester);
      expect(
        find.text('Failed to open folder. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('browse push without a folder target has no 10s fail snack', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const PikPakFilesScreen(isPushedRoute: true)),
      );
      await tester.pumpAndSettle();
      await drainOpenTimeout(tester);

      expect(
        find.text('Failed to open folder. Please try again.'),
        findsNothing,
      );
      expect(find.text('PikPak Not Configured'), findsOneWidget);
    });
  });

  group('bind constructors stay public types', () {
    test('CloudBrowseSelectSource keeps PM / AD / PikPak screens', () {
      final pm = CloudBrowseSelectSource.page(
        provider: 'premiumize',
        query: 'q',
        onSourceSelected: asyncBind,
      );
      expect(pm, isA<PremiumizeFilesScreen>());
      pm as PremiumizeFilesScreen;
      expect(pm.isPushedRoute, isTrue);
      expect(pm.selectSourceMode, isTrue);
      expect(pm.initialSearchQuery, 'q');
      expect(pm.onSourceSelected, isNotNull);

      final ad = CloudBrowseSelectSource.page(
        provider: 'alldebrid',
        query: 'q',
        onSourceSelected: asyncBind,
      );
      expect(ad, isA<AllDebridFilesScreen>());
      ad as AllDebridFilesScreen;
      expect(ad.isPushedRoute, isTrue);
      expect(ad.selectSourceMode, isTrue);
      expect(ad.initialSearchQuery, 'q');
      expect(ad.onSourceSelected, isNotNull);

      final pk = CloudBrowseSelectSource.page(
        provider: 'pikpak',
        query: 'q',
        onSourceSelected: asyncBind,
      );
      expect(pk, isA<PikPakFilesScreen>());
      pk as PikPakFilesScreen;
      expect(pk.isPushedRoute, isTrue);
      expect(pk.selectSourceMode, isTrue);
      expect(pk.onSourceSelected, isNotNull);
      // PikPak has no initialSearchQuery field — bind drops `query`.
    });
  });

  group('selection bar + destination ids stay on hosts', () {
    test('PM / AD circular bars; PikPak uses shape.br (manifest floor)', () {
      final pmBar = _methodBody(
        _readHost('lib/screens/premiumize/premiumize_files_screen.dart'),
        '_buildSelectionBar',
      );
      expect(pmBar.contains('borderRadius: BorderRadius.circular(12)'), isTrue);
      expect(pmBar.contains('app.shape.br'), isFalse);

      final adBar = _methodBody(
        _readHost('lib/screens/alldebrid/alldebrid_files_screen.dart'),
        '_buildSelectionBar',
      );
      expect(adBar.contains('borderRadius: BorderRadius.circular(12)'), isTrue);
      expect(adBar.contains('app.shape.br'), isFalse);

      final pkBar = _methodBody(
        _readHost('lib/screens/pikpak/pikpak_files_screen.dart'),
        '_buildSelectionBar',
      );
      expect(pkBar.contains('borderRadius: app.shape.br(12)'), isTrue);
    });

    test('frozen sidebar destination ids stay in host register calls', () {
      final pm = _readHost(
        'lib/screens/premiumize/premiumize_files_screen.dart',
      );
      expect(pm.contains("registerTabBackHandler("), isTrue);
      expect(pm.contains("'premiumize'"), isTrue);
      expect(pm.contains("unregisterTabBackHandler('premiumize')"), isTrue);

      final ad = _readHost('lib/screens/alldebrid/alldebrid_files_screen.dart');
      expect(ad.contains("registerTabBackHandler('alldebrid'"), isTrue);
      expect(ad.contains("unregisterTabBackHandler('alldebrid')"), isTrue);

      final pk = _readHost('lib/screens/pikpak/pikpak_files_screen.dart');
      expect(pk.contains("registerTabBackHandler('pikpak'"), isTrue);
      expect(pk.contains("unregisterTabBackHandler('pikpak')"), isTrue);
    });

    test('bind playback ids stay on hosts', () {
      expect(
        _readHost(
          'lib/screens/premiumize/premiumize_files_screen.dart',
        ).contains("debridService: 'premiumize'"),
        isTrue,
      );
      expect(
        _readHost(
          'lib/screens/alldebrid/alldebrid_files_screen.dart',
        ).contains("debridService: 'alldebrid'"),
        isTrue,
      );
      expect(
        _readHost(
          'lib/screens/pikpak/pikpak_files_screen.dart',
        ).contains("debridService: 'pikpak'"),
        isTrue,
      );
    });
  });

  group('CloudFilesSource (PM / AD / PikPak on the shared screen)', () {
    test('Premiumize destination id and My Files / Transfers sections', () {
      const source = PremiumizeFilesSource();
      expect(source.destinationId, 'premiumize');
      expect(source.selectSourceTitle, 'Select Premiumize Source');
      expect(source.openingTitle, 'Opening folder...');
      expect(source.sections.map((s) => s.label).toList(), [
        'My Files',
        'Transfers',
      ]);
    });

    test('AllDebrid destination id and magnet / web sections', () {
      const source = AllDebridFilesSource();
      expect(source.destinationId, 'alldebrid');
      expect(source.selectSourceTitle, 'Select AllDebrid Source');
      expect(source.sections.map((s) => s.label).toList(), [
        'Torrent Downloads',
        'Web Downloads',
      ]);
    });

    test('PikPak destination id, folder splash, empty sections', () {
      const source = PikPakFilesSource();
      expect(source.destinationId, 'pikpak');
      expect(source.selectSourceTitle, 'Select PikPak Source');
      expect(source.openingTitle, 'Opening folder...');
      expect(source.openingBody, 'Loading folder contents...');
      expect(
        source.openFailedMessage,
        'Failed to open folder. Please try again.',
      );
      expect(source.initialSearchQuery, isNull);
      expect(source.sections, isEmpty);
    });

    testWidgets('PremiumizeFilesScreen routes through CloudFilesScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PremiumizeFilesScreen(
            isPushedRoute: true,
            selectSourceMode: true,
            onSourceSelected: asyncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CloudFilesScreen), findsOneWidget);
      expect(find.byType(PremiumizeFilesScreen), findsOneWidget);
      expect(find.byType(PremiumizeCloudFilesHost), findsOneWidget);
      final screen = tester.widget<CloudFilesScreen>(
        find.byType(CloudFilesScreen),
      );
      expect(screen.source, isA<PremiumizeFilesSource>());
      expect(screen.source.destinationId, 'premiumize');
    });

    testWidgets('AllDebridFilesScreen routes through CloudFilesScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AllDebridFilesScreen(
            isPushedRoute: true,
            selectSourceMode: true,
            onSourceSelected: asyncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CloudFilesScreen), findsOneWidget);
      expect(find.byType(AllDebridFilesScreen), findsOneWidget);
      expect(find.byType(AllDebridCloudFilesHost), findsOneWidget);
      final screen = tester.widget<CloudFilesScreen>(
        find.byType(CloudFilesScreen),
      );
      expect(screen.source, isA<AllDebridFilesSource>());
      expect(screen.source.destinationId, 'alldebrid');
    });

    testWidgets('PikPakFilesScreen routes through CloudFilesScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          PikPakFilesScreen(
            isPushedRoute: true,
            selectSourceMode: true,
            onSourceSelected: asyncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CloudFilesScreen), findsOneWidget);
      expect(find.byType(PikPakFilesScreen), findsOneWidget);
      expect(find.byType(PikPakCloudFilesHost), findsOneWidget);
      final screen = tester.widget<CloudFilesScreen>(
        find.byType(CloudFilesScreen),
      );
      expect(screen.source, isA<PikPakFilesSource>());
      expect(screen.source.destinationId, 'pikpak');
      await drainOpenTimeout(tester);
    });
  });
}

String _readHost(String path) => File(path).readAsStringSync();

String _methodBody(String src, String name) {
  final start = src.indexOf('Widget $name()');
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $name');
  final rest = src.substring(start);
  final next = RegExp(
    r'\n  (?:Widget |void |Future|InputDecoration |bool |String )',
  ).firstMatch(rest.substring(1));
  return next == null ? rest : rest.substring(0, next.start + 1);
}
