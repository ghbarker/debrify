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
      expect(chunk, contains('return _CanvasBoardStage(host: this);'));
      expect(chunk, contains('return _AtriumBoardStage(host: this);'));
      expect(chunk, contains('return _MosaicBoardStage(host: this);'));
      expect(chunk, contains('return _PromenadeBoardStage(host: this);'));
      expect(chunk, contains('return _DeckBoardStage(host: this);'));
      expect(chunk, contains('return _TonightBoardStage(host: this);'));
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
    test('all seven Home stage builders exist', () {
      for (final name in kTvHomeStageBuilderNames) {
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
        '_CanvasBoardStage',
        '_AtriumBoardStage',
        '_MosaicBoardStage',
        '_PromenadeBoardStage',
        '_DeckBoardStage',
        '_TonightBoardStage',
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
        final body = _methodBody(layouts, '_buildTonightBoard');
        expect(body, contains('final queue = _tonightQueue;'));
        expect(body, contains('final rails = _stageRails;'));
        expect(body, contains('if (queue.isEmpty && rails.isEmpty) {'));
        expect(
          body,
          contains(
            'return BrandLoadingStage(isTelevision: widget.isTelevision);',
          ),
        );
        expect(
          body,
          contains(
            'if (_tonightZoneIsQueue && queue.isEmpty) _tonightZoneIsQueue = false;',
          ),
        );
        expect(
          body,
          contains(
            'if (!_tonightZoneIsQueue && rails.isEmpty) _tonightZoneIsQueue = true;',
          ),
        );
        expect(body, contains('_seedStageFocusOnce();'));
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
