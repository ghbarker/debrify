import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/player/identify_title_sheet.dart';
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

}
