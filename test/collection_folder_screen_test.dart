import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/widgets/collections/folder_hero_band.dart';
import 'package:debrify/widgets/see_all/see_all_filter_bar.dart';
import 'package:debrify/widgets/see_all/see_all_header.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';

import 'support/prefs_harness.dart';

/// [CollectionFolderScreen]'s two layouts. No addon is installed in this
/// harness, so every folder's lists come back "unresolved" and the body
/// settles on its empty state — deterministic and network-free, and enough
/// to pin the chrome each layout does (and doesn't) show, plus the DPAD
/// ladder reaching all the way down to the Retry button with no dead ends.
/// A real network/addon harness would be needed to pin focus landing on an
/// actual loaded poster card; see the PR notes.
void main() {
  final folder = const HomeCollectionFolder(
    id: 'f1',
    title: 'Netflix',
    heroBackdropUrl: 'https://example.invalid/backdrop.jpg',
    sources: [
      CollectionCatalogSource(
        addonId: 'not.installed',
        type: 'movie',
        catalogId: 'top',
      ),
    ],
  );
  final collection = HomeCollection(
    id: 'c1',
    title: 'Streaming',
    folders: [folder],
  );

  Widget host({required bool tv}) => MaterialApp(
    home: CollectionFolderScreen(
      collection: collection,
      onOpenItem: (_) {},
      isTelevision: tv,
    ),
  );

  /// Sets the actual render-surface size (not just an informational
  /// MediaQuery) — the TV canvas and a representative phone width — then
  /// boots the screen. _boot() chains three SharedPreferences-backed
  /// awaits; a few pumps settle them without risking pumpAndSettle against
  /// the empty state's own (non-looping) widgets.
  Future<void> boot(WidgetTester tester, {required bool tv}) async {
    tester.view.physicalSize = tv
        ? const Size(1920, 1080)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(tv: tv));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  for (final tv in [true, false]) {
    final label = tv ? 'TV (1920×1080)' : 'phone width';

    testWidgets('$label: Rows shows no hero band and no filter bar', (
      tester,
    ) async {
      await installLegacyPrefs();
      await boot(tester, tv: tv);
      expect(tester.takeException(), isNull);

      expect(find.byType(FolderHeroBand), findsNothing);
      expect(find.byType(SeeAllFilterBar), findsNothing);
      // The minimal header survives: title + "N lists" subtitle.
      expect(find.text('Streaming'), findsOneWidget);
      expect(find.textContaining('list'), findsOneWidget);
      // No "See all" text anywhere in this layout.
      expect(find.textContaining('See all'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: Tabs keeps the hero band and filter bar', (
      tester,
    ) async {
      await installLegacyPrefs({HomeCollectionsStore.folderLayoutKey: 'tabs'});
      await boot(tester, tv: tv);
      expect(tester.takeException(), isNull);

      expect(find.byType(FolderHeroBand), findsOneWidget);
      expect(find.byType(SeeAllFilterBar), findsOneWidget);
      expect(find.textContaining('See all'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'TV: DPAD-down from the back button reaches the Retry button with '
    'nothing in between left dangling (Rows, empty folder)',
    (tester) async {
      await installLegacyPrefs();
      await boot(tester, tv: true);

      final header = tester.widget<SeeAllHeader>(find.byType(SeeAllHeader));
      header.backNode.requestFocus();
      await tester.pump();
      expect(header.backNode.hasFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      final retry = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Retry'),
      );
      expect(FocusManager.instance.primaryFocus, same(retry.focusNode));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TV: DPAD-down from the back button lands on the Folder chip in Tabs '
    '(regression guard — Tabs keeps its filter-bar ladder, unlike Rows)',
    (tester) async {
      await installLegacyPrefs({HomeCollectionsStore.folderLayoutKey: 'tabs'});
      await boot(tester, tv: true);

      final header = tester.widget<SeeAllHeader>(find.byType(SeeAllHeader));
      header.backNode.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      final folderChip = tester.widget<StremioDropdown<int>>(
        find.byWidgetPredicate(
          (w) => w is StremioDropdown<int> && w.label == 'Folder',
        ),
      );
      expect(FocusManager.instance.primaryFocus, same(folderChip.focusNode));
    },
  );
}
