import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/screens/search/stages/tv_home_stage_dispatch.dart';
import 'package:debrify/services/storage_service.dart';

/// G1 step 5 characterisation of the TV Home stage layouts **before** each
/// `_build*Board` moves to `lib/screens/search/stages/`. Pin commit must
/// stay green on its own.
///
/// Quirks pinned here (keep, do not "fix"):
/// * Frozen `tv_home_style` strings: canvas / atrium / mosaic / promenade /
///   deck / tonight / spotlight / classic.
/// * Empty Spotlight shelves `break` to classic (favourites are not
///   `StremioMeta`).
/// * Canvas / Atrium / Mosaic / Promenade / Deck / Tonight paint
///   `BrandLoadingStage` when the resolved rail (or Tonight queue+rails) is
///   empty; Spotlight always builds `SpotlightBoard` and lets dispatch fall
///   through instead.
/// * `_buildDiscoverStage` is Discover chrome, not a Home stage.
/// * Classic hero/rows `LayoutBuilder` stays on the host.
String _hostSource() =>
    File('lib/screens/search_screen.dart').readAsStringSync();

/// Host plus any extracted stage files so this suite stays green after the
/// verbatim move (bodies keep the same `_build*Board` names).
String _layoutSources() {
  final buf = StringBuffer(_hostSource());
  final dir = Directory('lib/screens/search/stages');
  if (dir.existsSync()) {
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buf.writeln(entity.readAsStringSync());
      }
    }
  }
  return buf.toString();
}

String _methodBody(String source, String name) {
  final start = source.indexOf('Widget $name(');
  expect(start, isNonNegative, reason: 'missing Widget $name(');
  final brace = source.indexOf('{', start);
  expect(brace, greaterThan(start), reason: '$name has no body');
  var depth = 0;
  for (var i = brace; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$name: unmatched brace');
}

String _homeSwitchChunk(String host) {
  const marker = '// STAGE layouts: each owns the whole screen';
  final idx = host.indexOf(marker);
  expect(idx, isNonNegative, reason: 'missing Home stage dispatch comment');
  final classic = host.indexOf('return LayoutBuilder(', idx);
  expect(
    classic,
    greaterThan(idx),
    reason: 'classic LayoutBuilder must follow the switch',
  );
  return host.substring(idx, classic);
}

const _deckDispatch =
    'return DeckStage(bindings: _deckBindings, isTelevision: widget.isTelevision);';

String _deckSource() =>
    File('lib/screens/search/stages/deck_board_stage.dart').readAsStringSync();

void _expectDeckEmpty(String stage) {
  final body = _methodBody(stage, 'build');
  expect(body, contains('bindings.resolveRail()'));
  expect(body, matches(RegExp(
    r'if \(view == null\)\s*\{\s*'
    r'return BrandLoadingStage\(isTelevision: isTelevision\);\s*\}',
  )));
}

void _expectDeckSource(String host, String stage) {
  expect(_homeSwitchChunk(host), contains(_deckDispatch));
  expect(stage, contains('class DeckStage extends StatelessWidget'));
  expect(_methodBody(stage, 'build'), contains('return LayoutBuilder('));
  _expectDeckEmpty(stage);
  expect(_methodBody(stage, 'build'), contains('bindings.seedFocus();'));
}

const _mosaicDispatch =
    'return MosaicStage(bindings: _mosaicBindings, isTelevision: widget.isTelevision);';

String _mosaicSource() =>
    File('lib/screens/search/stages/mosaic_board_stage.dart').readAsStringSync();

void _expectMosaicEmpty(String stage) {
  final body = _methodBody(stage, 'build');
  expect(body, contains('bindings.resolveRail()'));
  expect(body, matches(RegExp(
    r'if \(view == null\)\s*\{\s*'
    r'return BrandLoadingStage\(isTelevision: isTelevision\);\s*\}',
  )));
}

void _expectMosaicSource(String host, String stage) {
  expect(_homeSwitchChunk(host), contains(_mosaicDispatch));
  expect(stage, contains('class MosaicStage extends StatelessWidget'));
  expect(_methodBody(stage, 'build'), contains('return LayoutBuilder('));
  _expectMosaicEmpty(stage);
  expect(_methodBody(stage, 'build'), contains('bindings.seedFocus();'));
}

const _promenadeDispatch =
    'return PromenadeStage(bindings: _promenadeBindings, isTelevision: widget.isTelevision);';

String _promenadeSource() =>
    File('lib/screens/search/stages/promenade_board_stage.dart').readAsStringSync();

void _expectPromenadeEmpty(String stage) {
  final body = _methodBody(stage, 'build');
  expect(body, contains('bindings.resolveRail()'));
  expect(body, matches(RegExp(
    r'if \(view == null\)\s*\{\s*'
    r'return BrandLoadingStage\(isTelevision: isTelevision\);\s*\}',
  )));
}

void _expectPromenadeSource(String host, String stage) {
  expect(_homeSwitchChunk(host), contains(_promenadeDispatch));
  expect(stage, contains('class PromenadeStage extends StatelessWidget'));
  expect(_methodBody(stage, 'build'), contains('return LayoutBuilder('));
  _expectPromenadeEmpty(stage);
  expect(_methodBody(stage, 'build'), contains('bindings.seedFocus();'));
}

const _canvasDispatch =
    'return CanvasStage(bindings: _canvasBindings, isTelevision: widget.isTelevision);';

String _canvasSource() =>
    File('lib/screens/search/stages/canvas_board_stage.dart')
        .readAsStringSync().replaceAll('\r\n', '\n');

const _canvasEmptyGuard = '''if (view == null) {
      // First batch still streaming (or every loaded row is empty) — hold
      // the brand stage rather than an empty black canvas.
      return BrandLoadingStage(isTelevision: isTelevision);
    }''';

void _expectCanvasEmpty(String stage) {
  final body = _methodBody(stage, 'build');
  expect(body, contains('bindings.resolveRail()'));
  expect(body, contains(_canvasEmptyGuard));
}

void _expectCanvasSource(String host, String stage) {
  expect(_homeSwitchChunk(host), contains(_canvasDispatch));
  expect(stage, contains('class CanvasStage extends StatelessWidget'));
  expect(_methodBody(stage, 'build'), contains('return LayoutBuilder('));
  _expectCanvasEmpty(stage);
  expect(_methodBody(stage, 'build'), contains('bindings.seedFocus();'));
}

void main() {
  late String host;
  late String layouts;

  setUpAll(() {
    host = _hostSource();
    layouts = _layoutSources();
  });

  group('frozen tv_home_style strings', () {
    test('dispatch set matches StorageService.kTvHomeStyles', () {
      expect(kTvHomeStageStyleValues, StorageService.kTvHomeStyles);
      expect(kTvHomeStageStyleValues, {
        'canvas',
        'classic',
        'atrium',
        'mosaic',
        'promenade',
        'deck',
        'tonight',
        'spotlight',
      });
    });

    test('product default stays canvas', () {
      expect(StorageService.tvHomeStyleCached, 'canvas');
    });
  });

  group('switch (_homeStyleEffective) dispatch', () {
    test('each stage style maps to itself when Spotlight has shelves', () {
      for (final style in [
        'canvas',
        'atrium',
        'mosaic',
        'promenade',
        'deck',
        'tonight',
        'spotlight',
      ]) {
        expect(
          resolveTvHomeStageLayout(
            homeStyleEffective: style,
            spotlightShelvesAllEmpty: false,
          ),
          style,
        );
      }
    });

    test('classic and unknown fall through to classic', () {
      expect(
        resolveTvHomeStageLayout(
          homeStyleEffective: 'classic',
          spotlightShelvesAllEmpty: false,
        ),
        'classic',
      );
      expect(
        resolveTvHomeStageLayout(
          homeStyleEffective: 'shelf',
          spotlightShelvesAllEmpty: false,
        ),
        'classic',
        reason: 'removed style coerced by storage still must not paint a stage',
      );
    });

    test('empty Spotlight shelves break to classic', () {
      expect(
        resolveTvHomeStageLayout(
          homeStyleEffective: 'spotlight',
          spotlightShelvesAllEmpty: true,
        ),
        'classic',
        reason:
            'quirk: `_spotlightShelves.every((s) => s.items.isEmpty) break;`',
      );
      expect(
        resolveTvHomeStageLayout(
          homeStyleEffective: 'canvas',
          spotlightShelvesAllEmpty: true,
        ),
        'canvas',
        reason: 'empty-shelf quirk is Spotlight-only',
      );
    });

    test('host switch still has the empty-Spotlight break before classic', () {
      final chunk = _homeSwitchChunk(host);
      expect(chunk, contains("case 'canvas':"));
      expect(chunk, contains("case 'atrium':"));
      expect(chunk, contains("case 'mosaic':"));
      expect(chunk, contains("case 'promenade':"));
      expect(chunk, contains("case 'deck':"));
      expect(chunk, contains("case 'tonight':"));
      expect(chunk, contains("case 'spotlight':"));
      expect(
        chunk,
        contains('if (_spotlightShelves.every((s) => s.items.isEmpty)) break;'),
      );
      expect(chunk, isNot(contains('_buildDiscoverStage')));
      expect(chunk, isNot(contains("case 'classic':")));
      expect(chunk, contains(_canvasDispatch));
      expect(chunk, contains('return _AtriumBoardStage(host: this);'));
      expect(chunk, contains(_mosaicDispatch));
      expect(chunk, contains(_promenadeDispatch));
      expect(chunk, contains(_deckDispatch));
      expect(chunk, contains('return TonightStage(content: _tonight, isTelevision: widget.isTelevision);'));
      expect(chunk, contains('return SpotlightStage(readFrame: () {'));
    });

    test('classic LayoutBuilder hero/rows stay after the switch', () {
      final idx = host.indexOf('// STAGE layouts: each owns the whole screen');
      final classic = host.indexOf('return LayoutBuilder(', idx);
      final hero = host.indexOf('_tvHeroBudget', classic);
      expect(hero, greaterThan(classic));
      expect(
        host.substring(classic, hero + 80),
        contains('Size the hero from the board'),
      );
    });
  });

  group('stage builders (source pin)', () {
    test('Canvas source inventory rejects dispatch, empty guard and seed removal', () {
      final stage = _canvasSource();
      _expectCanvasSource(host, stage);
      // Finite source-copy controls, not runtime or origin behavior evidence.
      expect(
        () => _expectCanvasSource(host.replaceFirst(_canvasDispatch, ''), stage),
        throwsA(isA<TestFailure>()),
      );
      expect(_canvasEmptyGuard.allMatches(stage), hasLength(1));
      expect(
        () => _expectCanvasSource(host, stage.replaceFirst(_canvasEmptyGuard, '')),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => _expectCanvasSource(host, stage.replaceFirst('bindings.seedFocus();', '')),
        throwsA(isA<TestFailure>()),
      );
    });
    test('Promenade source inventory rejects dispatch, empty guard and seed removal', () {
      final stage = _promenadeSource();
      _expectPromenadeSource(host, stage);
      // Finite source-copy controls, not runtime or origin behavior evidence.
      expect(
        () => _expectPromenadeSource(host.replaceFirst(_promenadeDispatch, ''), stage),
        throwsA(isA<TestFailure>()),
      );
      final emptyGuard = RegExp(
        r'if \(view == null\)\s*\{\s*'
        r'return BrandLoadingStage\(isTelevision: isTelevision\);\s*\}',
      );
      expect(emptyGuard.allMatches(stage), hasLength(1));
      expect(
        () => _expectPromenadeSource(host, stage.replaceFirst(emptyGuard, '')),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => _expectPromenadeSource(host, stage.replaceFirst('bindings.seedFocus();', '')),
        throwsA(isA<TestFailure>()),
      );
    });
    test('Mosaic source inventory rejects dispatch, empty guard and seed removal', () {
      final stage = _mosaicSource();
      _expectMosaicSource(host, stage);
      // Finite source-copy controls, not runtime or origin behavior evidence.
      expect(
        () => _expectMosaicSource(host.replaceFirst(_mosaicDispatch, ''), stage),
        throwsA(isA<TestFailure>()),
      );
      final emptyGuard = RegExp(
        r'if \(view == null\)\s*\{\s*'
        r'return BrandLoadingStage\(isTelevision: isTelevision\);\s*\}',
      );
      expect(emptyGuard.allMatches(stage), hasLength(1));
      expect(
        () => _expectMosaicSource(host, stage.replaceFirst(emptyGuard, '')),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => _expectMosaicSource(host, stage.replaceFirst('bindings.seedFocus();', '')),
        throwsA(isA<TestFailure>()),
      );
    });
    test('Deck source inventory rejects dispatch, empty guard and seed removal', () {
      final stage = _deckSource();
      _expectDeckSource(host, stage);
      // Finite source-copy controls, not runtime or origin behavior evidence.
      expect(
        () => _expectDeckSource(host.replaceFirst(_deckDispatch, ''), stage),
        throwsA(isA<TestFailure>()),
      );
      final emptyGuard = RegExp(
        r'if \(view == null\)\s*\{\s*'
        r'return BrandLoadingStage\(isTelevision: isTelevision\);\s*\}',
      );
      expect(emptyGuard.allMatches(stage), hasLength(1));
      expect(
        () => _expectDeckSource(host, stage.replaceFirst(emptyGuard, '')),
        throwsA(isA<TestFailure>()),
      );
      expect(
        () => _expectDeckSource(host, stage.replaceFirst('bindings.seedFocus();', '')),
        throwsA(isA<TestFailure>()),
      );
    });
    test('all seven Home stage builders exist', () {
      for (final name in kTvHomeStageBuilderNames) {
        if (name == '_buildCanvasBoard') {
          expect(_methodBody(_canvasSource(), 'build'), contains('return LayoutBuilder('));
          continue;
        }
        if (name == '_buildPromenadeBoard') {
          expect(_methodBody(_promenadeSource(), 'build'), contains('return LayoutBuilder('));
          continue;
        }
        if (name == '_buildMosaicBoard') {
          expect(_methodBody(_mosaicSource(), 'build'), contains('return LayoutBuilder('));
          continue;
        }
        if (name == '_buildDeckBoard') {
          expect(_methodBody(_deckSource(), 'build'), contains('return LayoutBuilder('));
          continue;
        }
        if (name == '_buildTonightBoard') {
          final stage = File(
            'lib/screens/search/stages/tonight_board_stage.dart',
          ).readAsStringSync();
          expect(_methodBody(stage, 'build'), contains('return LayoutBuilder('));
          continue;
        }
        if (name == '_buildSpotlightBoard') {
          final stage = File(
            'lib/screens/search/stages/spotlight_board_stage.dart',
          ).readAsStringSync();
          expect(
            _methodBody(stage, 'build'),
            contains('return SpotlightBoard('),
          );
          continue;
        }
        expect(layouts.contains('Widget $name('), isTrue, reason: name);
      }
    });

    test('each board is its own widget under search/stages/', () {
      const widgets = [
        'CanvasStage',
        '_AtriumBoardStage',
        'MosaicStage',
        'PromenadeStage',
        'DeckStage',
        'TonightStage',
        'SpotlightStage',
      ];
      for (final name in widgets) {
        expect(
          layouts.contains('class $name extends StatelessWidget'),
          isTrue,
          reason: name,
        );
      }
    });

    test(
      'Canvas / Atrium / Mosaic / Promenade / Deck empty → BrandLoadingStage',
      () {
        for (final name in [
          '_buildCanvasBoard',
          '_buildAtriumBoard',
          '_buildMosaicBoard',
          '_buildPromenadeBoard',
          '_buildDeckBoard',
        ]) {
          if (name == '_buildCanvasBoard') {
            _expectCanvasEmpty(_canvasSource());
            continue;
          }
          if (name == '_buildPromenadeBoard') {
            _expectPromenadeEmpty(_promenadeSource());
            continue;
          }
          if (name == '_buildMosaicBoard') {
            _expectMosaicEmpty(_mosaicSource());
            continue;
          }
          if (name == '_buildDeckBoard') {
            _expectDeckEmpty(_deckSource());
            continue;
          }
          final body = _methodBody(layouts, name);
          expect(
            body,
            contains(
              'return BrandLoadingStage(isTelevision: widget.isTelevision);',
            ),
            reason: name,
          );
          expect(body, contains('_resolveStageRail()'), reason: name);
        }
      },
    );

    test(
      'Tonight empty queue+rails → BrandLoadingStage; dead zone cannot hold focus',
      () {
        final stage = File(
          'lib/screens/search/stages/tonight_board_stage.dart',
        ).readAsStringSync();
        final body = _methodBody(stage, 'build');
        expect(body, contains('final queue = content.queue;'));
        expect(body, contains('final rails = content.bindings.readStageRails();'));
        expect(body, contains('if (queue.isEmpty && rails.isEmpty) {'));
        expect(
          body,
          contains(
            'return BrandLoadingStage(isTelevision: isTelevision);',
          ),
        );
        expect(
          body,
          contains(
            'if (content.zoneIsQueue && queue.isEmpty) content.zoneIsQueue = false;',
          ),
        );
        expect(
          body,
          contains(
            'if (!content.zoneIsQueue && rails.isEmpty) content.zoneIsQueue = true;',
          ),
        );
        expect(body, contains('content.bindings.seedFocusOnce();'));
        expect(body.indexOf('final queue = content.queue;'),
            lessThan(body.indexOf('final rails = content.bindings.readStageRails();')));
        expect(body.indexOf('if (queue.isEmpty && rails.isEmpty)'),
            lessThan(body.indexOf('if (content.zoneIsQueue && queue.isEmpty)')));
        expect(body.indexOf('if (!content.zoneIsQueue && rails.isEmpty)'),
            lessThan(body.indexOf('content.bindings.seedFocusOnce();')));
      },
    );

    test(
      'Spotlight always builds SpotlightBoard; empty shelves are dispatch-only',
      () {
        final stage = File(
          'lib/screens/search/stages/spotlight_board_stage.dart',
        ).readAsStringSync();
        final body = _methodBody(stage, 'build');
        expect(
          stage,
          contains(
            'const SpotlightStage({super.key, required this.readFrame});',
          ),
        );
        expect(body, contains('final frame = readFrame();'));
        final frameMatch = RegExp(
          r'return SpotlightStage\(readFrame: \(\) \{([\s\S]*?)\n\s*\}\);',
        ).firstMatch(_homeSwitchChunk(host));
        expect(frameMatch, isNotNull);
        final frame = frameMatch!.group(1)!;
        expect(body, contains('return SpotlightBoard('));
        expect(body, contains('trailersEnabled: frame.trailersEnabled,'));
        expect(body, contains('onDwell: frame.onDwell,'));
        expect(body, contains('trailer: frame.trailer,'));
        expect(frame, contains('trailersEnabled: _heroTrailerEnabled,'));
        expect(
          frame,
          matches(
            r'onDwell: \(StremioMeta item\) =>\s*'
            r'_scheduleHeroTrailer\(item, fromSpotlight: true\),',
          ),
        );
        expect(frame, contains('fullBleed: true,'));
        expect(
          body,
          isNot(contains('BrandLoadingStage')),
          reason: 'empty Spotlight is a switch `break`, not a loading stage',
        );
      },
    );

    test(
      'Canvas / Promenade / Atrium / Mosaic / Deck seed stage focus once',
      () {
        for (final name in [
          '_buildCanvasBoard',
          '_buildPromenadeBoard',
          '_buildAtriumBoard',
          '_buildMosaicBoard',
          '_buildDeckBoard',
        ]) {
          if (name == '_buildCanvasBoard') {
            expect(_methodBody(_canvasSource(), 'build'), contains('bindings.seedFocus();'));
            continue;
          }
          if (name == '_buildPromenadeBoard') {
            expect(_methodBody(_promenadeSource(), 'build'), contains('bindings.seedFocus();'));
            continue;
          }
          if (name == '_buildMosaicBoard') {
            expect(_methodBody(_mosaicSource(), 'build'), contains('bindings.seedFocus();'));
            continue;
          }
          if (name == '_buildDeckBoard') {
            expect(_methodBody(_deckSource(), 'build'), contains('bindings.seedFocus();'));
            continue;
          }
          expect(
            _methodBody(layouts, name),
            contains('_seedStageFocusOnce();'),
            reason: name,
          );
        }
      },
    );

    test('_buildDiscoverStage is Discover chrome, not a Home stage', () {
      final discover = File(
        'lib/screens/search/discover_view.dart',
      ).readAsStringSync();
      expect(
        _methodBody(discover, '_buildDiscoverStage'),
        matches(RegExp(
          r'^Widget _buildDiscoverStage\(\s*BuildContext context,\s*'
          r'BoxConstraints c,\s*Widget panel,?\s*\)\s*\{',
        )),
      );
      expect(
        discover,
        contains("The Discover STAGE layout (`discover_layout` = 'stage'"),
      );
      final composition = File(
        'lib/screens/search/discover_screen.dart',
      ).readAsStringSync();
      final handoffs = RegExp(
        r'DiscoverView\(([\s\S]*?)\n\s*\)',
      ).allMatches(composition).toList();
      expect(handoffs, hasLength(1),
          reason: 'actual Discover composition must build one DiscoverView');
      final arguments = handoffs.single.group(1)!;
      expect(arguments, matches(RegExp(r'panel:\s*_buildDiscoverPanel\(\),')));
      expect(RegExp(r'_buildDiscoverPanel\(').allMatches(arguments), hasLength(1));
      expect(host, isNot(contains('Widget _buildDiscoverStage(')));
      expect(host, isNot(contains('Widget _buildDiscover(')));
      expect(host, isNot(contains('Widget _buildDiscoverPanel(')));
      expect(_homeSwitchChunk(host), isNot(contains('_buildDiscoverStage')));
      expect(_homeSwitchChunk(host), isNot(contains('DiscoverView')));
    });
  });
}
