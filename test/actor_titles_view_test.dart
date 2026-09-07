import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_person_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/actor_titles_view.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

const _member = CastMember(
  name: 'Tim Robbins',
  character: 'Andy Dufresne',
  nameId: 'nm0000209',
);

// Posters and photos are deliberately null: a URL would make the tiles reach
// for the network under test.
const _person = ImdbPerson(
  nameId: 'nm0000209',
  name: 'Tim Robbins',
  knownFor: [
    StremioMeta(
      id: 'tt0111161',
      imdbId: 'tt0111161',
      type: 'movie',
      name: 'The Shawshank Redemption',
      year: '1994',
    ),
    StremioMeta(
      id: 'tt2364582',
      imdbId: 'tt2364582',
      type: 'series',
      name: 'Castle Rock',
      year: '2018',
    ),
  ],
);

Widget _host(Widget child) => MaterialApp(
  home: AppThemeScope(
    theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
    child: child,
  ),
);

void main() {
  testWidgets('shows a spinner, then the known-for titles', (tester) async {
    final gate = Completer<ImdbPerson?>();
    await tester.pumpWidget(
      _host(
        ActorTitlesView(
          member: _member,
          onOpenTitle: (_) {},
          loader: (_) => gate.future,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Tim Robbins'), findsOneWidget);
    expect(find.text('as Andy Dufresne'), findsOneWidget);

    gate.complete(_person);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('The Shawshank Redemption'), findsOneWidget);
    expect(find.text('1994 · Movie'), findsOneWidget);
    expect(find.text('Castle Rock'), findsOneWidget);
    expect(find.text('2018 · Series'), findsOneWidget);
  });

  testWidgets('tapping a title invokes the opener with its id and type', (
    tester,
  ) async {
    final opened = <StremioMeta>[];
    final requested = <String>[];
    await tester.pumpWidget(
      _host(
        ActorTitlesView(
          member: _member,
          onOpenTitle: opened.add,
          loader: (id) async {
            requested.add(id);
            return _person;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requested, ['nm0000209']);

    await tester.tap(find.byKey(const ValueKey('actor-title-tt2364582')));
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.id, 'tt2364582');
    expect(opened.single.type, 'series');
  });

  testWidgets('TV: DPAD lands on the first poster and OK opens it', (
    tester,
  ) async {
    final opened = <StremioMeta>[];
    await tester.pumpWidget(
      _host(
        ActorTitlesView(
          member: _member,
          onOpenTitle: opened.add,
          loader: (_) async => _person,
          isTelevision: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(opened.map((m) => m.id), ['tt0111161']);

    // RIGHT walks the grid; OK opens the neighbour.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(opened.map((m) => m.id), ['tt0111161', 'tt2364582']);
  });

  testWidgets('an empty known-for list says so', (tester) async {
    await tester.pumpWidget(
      _host(
        ActorTitlesView(
          member: _member,
          onOpenTitle: (_) {},
          loader: (_) async => const ImdbPerson(
            nameId: 'nm0000209',
            name: 'Tim Robbins',
            knownFor: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No titles found for Tim Robbins.'), findsOneWidget);
  });

  testWidgets('a failed lookup says so instead of throwing', (tester) async {
    await tester.pumpWidget(
      _host(
        ActorTitlesView(
          member: _member,
          onOpenTitle: (_) {},
          loader: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load titles for Tim Robbins.'), findsOneWidget);
  });

  testWidgets('a member without a name id never calls the loader', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        ActorTitlesView(
          member: const CastMember(name: 'Anon'),
          onOpenTitle: (_) {},
          loader: (_) async {
            calls++;
            return _person;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Could not load titles for Anon.'), findsOneWidget);
  });

  testWidgets('show() pushes a route the back button pops', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => ActorTitlesView.show(
              context,
              member: _member,
              onOpenTitle: (_) {},
              loader: (_) async => _person,
              routeName: 'detail',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ActorTitlesView), findsOneWidget);
    expect(find.text('Castle Rock'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ActorTitlesView), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
