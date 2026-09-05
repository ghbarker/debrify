import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/player/identify_title_sheet.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identifyTitleSearchInitialQuery matches origin ladders', () {
    expect(
      identifyTitleSearchInitialQuery('Show.Name.S01E02.1080p.mkv'),
      isNotEmpty,
    );
    expect(
      identifyTitleSearchInitialQuery('The.Movie.2020.1080p.mkv'),
      'The Movie',
    );
    expect(
      identifyTitleSearchInitialQuery('Some_File.Name.mkv'),
      'Some File Name',
    );
  });

  test(
    'filterIdentitySearchResults keeps tt movie/series and scores poster',
    () {
      final kept = filterIdentitySearchResults([
        const StremioMeta(id: 'x', type: 'movie', name: 'No id'),
        const StremioMeta(
          id: 'tt1',
          imdbId: 'tt1',
          type: 'channel',
          name: 'Live',
        ),
        const StremioMeta(
          id: 'tt2',
          imdbId: 'tt2',
          type: 'movie',
          name: 'Plain',
          year: '1999',
        ),
        const StremioMeta(
          id: 'tt2',
          imdbId: 'tt2',
          type: 'movie',
          name: 'Poster',
          poster: 'https://p/a.jpg',
        ),
      ]);
      expect(kept.single.name, 'Poster');
    },
  );

  test('normaliseIdentifyPosterUrl and identityMetaSubtitle quirks', () {
    expect(
      normaliseIdentifyPosterUrl('//cdn.example/p.jpg'),
      'https://cdn.example/p.jpg',
    );
    expect(normaliseIdentifyPosterUrl('   '), isNull);
    expect(
      identityMetaSubtitle(
        const StremioMeta(id: 'a', type: 'channel', name: 'X', year: '  '),
      ),
      'Movie',
    );
  });

  testWidgets('identify sheet close returns null; chrome says FIX THE TITLE', (
    tester,
  ) async {
    StremioMeta? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showIdentifyTitleSearchSheet(
                  context: context,
                  initialQuery: '',
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('FIX THE TITLE'), findsOneWidget);
    expect(find.text('Search movie or show'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('result tile on a pushed route returns the meta', (tester) async {
    const meta = StremioMeta(
      id: 'tt1',
      imdbId: 'tt1',
      type: 'movie',
      name: 'Picked',
    );
    StremioMeta? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<StremioMeta>(
                  MaterialPageRoute(
                    builder: (ctx) =>
                        Scaffold(body: buildIdentifyTitleResultTile(ctx, meta)),
                  ),
                );
              },
              child: const Text('push'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Picked'));
    await tester.pumpAndSettle();
    expect(popped?.name, 'Picked');
  });

  for (final tv in [false, true]) {
    testWidgets('Spotlight episode validation, apply and cancel (TV=$tv)', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(tv);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      SeasonEpisodeSelection? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await requestSeasonEpisodeForIdentity(
                  context,
                  'Pinned show',
                );
                completed = true;
              },
              child: const Text('episode'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('episode'));
      await tester.pumpAndSettle();
      expect(find.text('Which episode?'), findsOneWidget);
      expect(find.text('Pinned show'), findsOneWidget);
      if (tv) {
        // The real Spotlight recommended action must autofocus and handle OK.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('Apply'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid season and episode.'), findsOneWidget);
      expect(completed, isFalse);
      await tester.enterText(find.byType(TextField).at(0), ' 2 ');
      await tester.enterText(find.byType(TextField).at(1), ' 3 ');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result!.season, 2);
      expect(result!.episode, 3);
      completed = false;
      await tester.tap(find.text('episode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
    });
  }
}
