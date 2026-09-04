import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/screens/cloud/cloud_browse_select_source.dart';
import 'package:debrify/screens/cloud_files/cloud_files_screen.dart';
import 'package:debrify/screens/cloud_files/real_debrid_files_source.dart';
import 'package:debrify/screens/cloud_files/torbox_files_source.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';
import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G4 characterisation of the current cloud-files screens **before** the
/// shared `CloudFilesScreen` extract. Pin commit must stay green on its own.
///
/// Quirks pinned here (keep, do not "fix"):
/// * RD sections are labelled "Torrent Downloads" / "DDL Downloads".
/// * TorBox sections are labelled "Torrents" / "Web Downloads".
/// * Select-source AppBar titles differ per provider (Real-Debrid / TorBox).
/// * Deep-link opening splash copy is identical: "Opening torrent..." /
///   "Loading torrent files..." / 10s fail snack "Failed to open torrent…".
/// * RD bind uses `debridService: 'rd'` (playback id), TorBox uses `'torbox'`.
/// * Sidebar destination ids stay `realdebrid` / `torbox` (tab back handlers).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> drainOpenTimeout(WidgetTester tester) async {
    // Both hosts schedule a 10s deep-link timeout when pushed with a target.
    await tester.pump(const Duration(seconds: 11));
  }

  Widget host(Widget screen) => MaterialApp(home: screen);

  Future<void> asyncBind(SeriesSource _) async {}
  void syncBind(SeriesSource _) {}

  group('Real-Debrid DebridDownloadsScreen', () {
    testWidgets('select-source shows torrent + DDL sections and RD title', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          DebridDownloadsScreen(
            isPushedRoute: true,
            selectSourceMode: true,
            initialSearchQuery: 'Show Title',
            onSourceSelected: syncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DebridDownloadsScreen), findsOneWidget);
      expect(find.text('Select Source from Real-Debrid'), findsOneWidget);
      expect(find.text('Torrent Downloads'), findsOneWidget);
      expect(find.text('DDL Downloads'), findsOneWidget);
      expect(find.text('Show Title'), findsOneWidget);
      expect(find.text('Search your torrents...'), findsOneWidget);

      await tester.tap(find.text('DDL Downloads'));
      await tester.pumpAndSettle();

      expect(find.text('Error Loading DDL Downloads'), findsOneWidget);
      expect(
        find.text(
          'No API key configured. Please add your Real Debrid API key in Settings.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      // Search is torrent-section only; DDL does not keep the query bar.
      expect(find.text('Show Title'), findsNothing);
      await drainOpenTimeout(tester);
    });

    testWidgets('torrent section error copy without an API key', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const DebridDownloadsScreen(
            isPushedRoute: true,
            selectSourceMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error Loading Torrent Downloads'), findsOneWidget);
      expect(
        find.text(
          'No API key configured. Please add your Real Debrid API key in Settings.',
        ),
        findsOneWidget,
      );
      await drainOpenTimeout(tester);
    });

    testWidgets('tab root has no select-source AppBar; sections stay', (
      tester,
    ) async {
      await tester.pumpWidget(host(const DebridDownloadsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Select Source from Real-Debrid'), findsNothing);
      expect(find.text('Torrent Downloads'), findsOneWidget);
      expect(find.text('DDL Downloads'), findsOneWidget);
    });

    testWidgets('deep-link splash while the RD folder tree is pending', (
      tester,
    ) async {
      final torrent = RDTorrent(
        id: 't1',
        filename: 'Folder Tree Pin.mkv',
        hash: 'abc',
        bytes: 1,
        host: 'real-debrid.com',
        split: 0,
        progress: 100,
        status: 'downloaded',
        added: '2026-01-01',
        links: const ['https://example/file'],
      );
      await tester.pumpWidget(
        host(
          DebridDownloadsScreen(
            isPushedRoute: true,
            initialTorrentForOptions: torrent,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Opening torrent...'), findsOneWidget);
      expect(find.text('Loading torrent files...'), findsOneWidget);
      // Folder tree is not entered without an API key — 10s fail snack.
      await drainOpenTimeout(tester);
      expect(
        find.text('Failed to open torrent. Please try again.'),
        findsOneWidget,
      );
    });
  });

  group('TorBox TorboxDownloadsScreen', () {
    testWidgets('select-source shows torrents + web-download sections', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          TorboxDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: 'Movie title',
            selectSourceMode: true,
            onSourceSelected: syncBind,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TorboxDownloadsScreen), findsOneWidget);
      expect(find.text('Select Source from TorBox'), findsOneWidget);
      expect(find.text('Torrents'), findsOneWidget);
      expect(find.text('Web Downloads'), findsOneWidget);
      expect(find.text('Movie title'), findsOneWidget);
      expect(find.text('Search your torrents...'), findsOneWidget);

      await tester.tap(find.text('Web Downloads'));
      await tester.pumpAndSettle();

      // Source-selection search is torrent-section only (quirk).
      expect(find.text('Movie title'), findsNothing);
      expect(find.textContaining('view web downloads'), findsOneWidget);
      expect(find.text('Open Torbox Settings'), findsOneWidget);
      await drainOpenTimeout(tester);
    });

    testWidgets('tab root has no select-source AppBar; sections stay', (
      tester,
    ) async {
      await tester.pumpWidget(host(const TorboxDownloadsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Select Source from TorBox'), findsNothing);
      expect(find.text('Torrents'), findsOneWidget);
      expect(find.text('Web Downloads'), findsOneWidget);
    });

    testWidgets('deep-link splash while TorBox folder tree is pending', (
      tester,
    ) async {
      final torrent = TorboxTorrent.fromJson({
        'id': 1,
        'hash': 'abc',
        'name': 'Folder Tree Pin',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'files': const [],
      });
      await tester.pumpWidget(
        host(
          TorboxDownloadsScreen(
            isPushedRoute: true,
            initialTorrentToOpen: torrent,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Opening torrent...'), findsOneWidget);
      expect(find.text('Loading torrent files...'), findsOneWidget);
      await drainOpenTimeout(tester);
      expect(
        find.text('Failed to open torrent. Please try again.'),
        findsOneWidget,
      );
    });
  });

  group('bind / playback entry constructors', () {
    test(
      'CloudBrowseSelectSource keeps public screen types and bind flags',
      () {
        final rd = CloudBrowseSelectSource.page(
          provider: 'debrid',
          query: 'q',
          onSourceSelected: asyncBind,
        );
        expect(rd, isA<DebridDownloadsScreen>());
        rd as DebridDownloadsScreen;
        expect(rd.isPushedRoute, isTrue);
        expect(rd.selectSourceMode, isTrue);
        expect(rd.initialSearchQuery, 'q');
        expect(rd.onSourceSelected, isNotNull);

        final tb = CloudBrowseSelectSource.page(
          provider: 'torbox',
          query: 'q',
          onSourceSelected: asyncBind,
        );
        expect(tb, isA<TorboxDownloadsScreen>());
        tb as TorboxDownloadsScreen;
        expect(tb.isPushedRoute, isTrue);
        expect(tb.selectSourceMode, isTrue);
        expect(tb.initialSearchQuery, 'q');
        expect(tb.onSourceSelected, isNotNull);
      },
    );
  });

  group('other providers (PM / AD / PikPak, also on CloudFilesScreen)', () {
    testWidgets('Premiumize unconfigured copy without an API key', (
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

      expect(find.text('Premiumize'), findsOneWidget);
      expect(find.text('Premiumize Not Configured'), findsOneWidget);
      await drainOpenTimeout(tester);
    });

    testWidgets('AllDebrid select-source keeps magnet + web libraries', (
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

      expect(find.text('Select AllDebrid Source'), findsOneWidget);
      expect(find.text('Torrent Downloads'), findsOneWidget);
      expect(find.text('Web Downloads'), findsOneWidget);
      await drainOpenTimeout(tester);
    });

    testWidgets('PikPak unconfigured empty copy', (tester) async {
      await tester.pumpWidget(
        host(const PikPakFilesScreen(isPushedRoute: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('PikPak Files'), findsOneWidget);
      expect(find.text('PikPak Not Configured'), findsOneWidget);
      await drainOpenTimeout(tester);
    });
  });

  group('CloudFilesSource (RD + TorBox on the shared screen)', () {
    test('RD destination id and sections match the frozen literals', () {
      const source = RealDebridFilesSource();
      expect(source.destinationId, 'realdebrid');
      expect(source.selectSourceTitle, 'Select Source from Real-Debrid');
      expect(source.openingTitle, 'Opening torrent...');
      expect(source.openingBody, 'Loading torrent files...');
      expect(
        source.openFailedMessage,
        'Failed to open torrent. Please try again.',
      );
      expect(source.sections.map((s) => s.label).toList(), [
        'Torrent Downloads',
        'DDL Downloads',
      ]);
    });

    test('TorBox destination id and web-download section', () {
      const source = TorBoxFilesSource();
      expect(source.destinationId, 'torbox');
      expect(source.selectSourceTitle, 'Select Source from TorBox');
      expect(source.openingTitle, 'Opening torrent...');
      expect(source.sections.map((s) => s.label).toList(), [
        'Torrents',
        'Web Downloads',
      ]);
    });

    testWidgets('DebridDownloadsScreen routes through CloudFilesScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const DebridDownloadsScreen(
            isPushedRoute: true,
            selectSourceMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CloudFilesScreen), findsOneWidget);
      expect(find.byType(DebridDownloadsScreen), findsOneWidget);
      expect(find.byType(RealDebridCloudFilesHost), findsOneWidget);
      final screen = tester.widget<CloudFilesScreen>(
        find.byType(CloudFilesScreen),
      );
      expect(screen.source, isA<RealDebridFilesSource>());
      expect(screen.source.destinationId, 'realdebrid');
      await drainOpenTimeout(tester);
    });

    testWidgets('TorboxDownloadsScreen routes through CloudFilesScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const TorboxDownloadsScreen(
            isPushedRoute: true,
            selectSourceMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CloudFilesScreen), findsOneWidget);
      expect(find.byType(TorboxDownloadsScreen), findsOneWidget);
      expect(find.byType(TorboxCloudFilesHost), findsOneWidget);
      final screen = tester.widget<CloudFilesScreen>(
        find.byType(CloudFilesScreen),
      );
      expect(screen.source, isA<TorBoxFilesSource>());
      expect(screen.source.destinationId, 'torbox');
      await drainOpenTimeout(tester);
    });
  });
}
