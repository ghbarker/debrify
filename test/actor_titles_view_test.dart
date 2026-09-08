import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/episodes_screen.dart'
    show kCatalogDetailRouteName;
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_person_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/actor_titles_view.dart';
import 'package:debrify/widgets/detail/detail_rail_cards.dart';
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

  testWidgets(
    'TV: DPAD down through a long grid keeps a visible poster focused',
    (tester) async {
      // A Shield-sized frame: 1920x1080 at dpr 2. Two rows fit under the
      // header, so walking 30 titles down scrolls the grid several times.
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final many = ImdbPerson(
        nameId: 'nm0000209',
        name: 'Tim Robbins',
        knownFor: List.generate(
          30,
          (i) => StremioMeta(
            id: 'tt$i',
            imdbId: 'tt$i',
            type: 'movie',
            name: 'Title $i',
            year: '${1990 + i}',
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          ActorTitlesView(
            member: _member,
            onOpenTitle: (_) {},
            loader: (_) async => many,
            isTelevision: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = tester.getRect(find.byType(GridView));
      final seen = <String>{};
      // More presses than rows: the last few must stay put on the bottom row
      // rather than wandering off the grid.
      for (var step = 0; step < 12; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        final primary = FocusManager.instance.primaryFocus;
        final card = primary?.context
            ?.findAncestorWidgetOfExactType<DetailRecCard>();
        expect(
          card,
          isNotNull,
          reason:
              'after DOWN #${step + 1} focus is on '
              '${primary?.debugLabel ?? primary} rather than a poster',
        );
        final rect = tester.getRect(find.byWidget(card!));
        // The lifted card may poke a few px past the slot; the poster itself
        // must sit inside the grid's viewport.
        expect(
          grid.inflate(8).contains(rect.topLeft) &&
              grid.inflate(8).contains(rect.bottomRight),
          isTrue,
          reason:
              'after DOWN #${step + 1} focused poster $rect is outside '
              'the grid viewport $grid',
        );
        seen.add(card.rec.id);
      }
      // It actually reached the bottom row and never left the grid.
      expect(seen, contains('tt28'));

      String? focusedId() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<DetailRecCard>()
          ?.rec
          .id;

      // The bottom row is short (30 titles, 7 across: 2 posters). RIGHT past
      // its end is where the cursor used to vanish: the page-wide
      // key-handling Focus was a traversable node spanning every row's band,
      // so with no poster to the right it was the "nearest" candidate — and
      // from a node covering the whole screen no direction leads anywhere.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusedId(), 'tt29');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        focusedId(),
        isNotNull,
        reason:
            'RIGHT past the short bottom row left focus on '
            '${FocusManager.instance.primaryFocus?.debugLabel}',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(focusedId(), isNotNull);

      // Walk back UP: every stop is a visible poster until the header.
      var ups = 0;
      while (FocusManager.instance.primaryFocus?.debugLabel != 'actor-back') {
        expect(ups, lessThan(8), reason: 'UP never reached the back button');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        ups++;
        final primary = FocusManager.instance.primaryFocus;
        if (primary?.debugLabel == 'actor-back') break;
        final card = primary?.context
            ?.findAncestorWidgetOfExactType<DetailRecCard>();
        expect(
          card,
          isNotNull,
          reason:
              'after UP #$ups focus is on '
              '${primary?.debugLabel ?? primary} rather than a poster',
        );
        final rect = tester.getRect(find.byWidget(card!));
        expect(
          grid.inflate(8).contains(rect.topLeft) &&
              grid.inflate(8).contains(rect.bottomRight),
          isTrue,
          reason:
              'after UP #$ups focused poster $rect is outside '
              'the grid viewport $grid',
        );
      }
      // Four rows up, then the header: never a shortcut off the grid.
      expect(ups, greaterThanOrEqualTo(4));
    },
  );

  testWidgets('TV: UP from the first row lands on the back button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ActorTitlesView(
          member: _member,
          onOpenTitle: (_) {},
          loader: (_) async => _person,
          isTelevision: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<DetailRecCard>(),
      isNotNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'actor-back');

    // DOWN from the back button returns to the grid, never to the page.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<DetailRecCard>(),
      isNotNull,
    );
  });

  testWidgets('TV: Back/Escape still pops the page from a poster', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => ActorTitlesView.show(
              context,
              member: _member,
              onOpenTitle: (_) {},
              loader: (_) async => _person,
              isTelevision: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<DetailRecCard>(),
      isNotNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ActorTitlesView), findsNothing);
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

  testWidgets(
    'TV: one remote Back press returns to the detail page, not past it',
    (tester) async {
      final pops = _PopCounter();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [pops],
          home: AppThemeScope(
            theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    // The host marks every detail route this way and the
                    // actor page inherits the name — a pop that walks by
                    // name would tear both down, so the test pins it.
                    settings: const RouteSettings(
                      name: kCatalogDetailRouteName,
                    ),
                    builder: (_) => const _FakeDetailPage(),
                  ),
                ),
                child: const Text('home'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cast'));
      await tester.pumpAndSettle();
      expect(find.byType(ActorTitlesView), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<DetailRecCard>(),
        isNotNull,
      );

      await _pressRemoteBack(tester);
      await tester.pumpAndSettle();

      expect(
        pops.count,
        1,
        reason: 'one Back press must pop exactly the actor page',
      );
      expect(find.byType(ActorTitlesView), findsNothing);
      expect(find.text('detail page'), findsOneWidget);
      expect(find.text('home'), findsNothing);
    },
  );

  testWidgets('TV: the platform pop alone (tvOS Menu) pops the actor page', (
    tester,
  ) async {
    final pops = _PopCounter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [pops],
        home: AppThemeScope(
          theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
          child: const _FakeDetailPage(),
        ),
      ),
    );
    await tester.tap(find.text('cast'));
    await tester.pumpAndSettle();
    expect(find.byType(ActorTitlesView), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(pops.count, 1);
    expect(find.byType(ActorTitlesView), findsNothing);
    expect(find.text('detail page'), findsOneWidget);
  });
}

/// A Back press the way the Android embedding delivers it. KEYCODE_BACK
/// reaches the framework as a key DOWN then a key UP, and the Activity fires
/// the actual back action (onBackPressed → `popRoute`) from the UP — but only
/// once the framework has left that UP unhandled and the engine redispatched
/// it. A widget that consumes the DOWN and ignores the UP therefore gets BOTH
/// its own pop and the platform's from one press.
Future<void> _pressRemoteBack(WidgetTester tester) async {
  // The simulator has no physical key on file for GoBack; the remote's
  // physical key is irrelevant to the handlers, only the logical key counts.
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.goBack,
    platform: 'android',
    physicalKey: PhysicalKeyboardKey.escape,
  );
  final upHandled = await tester.sendKeyUpEvent(
    LogicalKeyboardKey.goBack,
    platform: 'android',
    physicalKey: PhysicalKeyboardKey.escape,
  );
  if (!upHandled) await tester.binding.handlePopRoute();
}

class _PopCounter extends NavigatorObserver {
  int count = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

/// Stands in for the merged/legacy detail page: it pushes the actor page the
/// way `_openActor` does — same navigator, same route name, TV mode.
class _FakeDetailPage extends StatelessWidget {
  const _FakeDetailPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const Text('detail page'),
        TextButton(
          onPressed: () => ActorTitlesView.show(
            context,
            member: _member,
            onOpenTitle: (_) {},
            loader: (_) async => _person,
            isTelevision: true,
            routeName: kCatalogDetailRouteName,
          ),
          child: const Text('cast'),
        ),
      ],
    ),
  );
}
