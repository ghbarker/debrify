import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/home/card_focus_rise.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = ValueKey('capture');
const _card = ValueKey('card');
const _art = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [Color(0x99432569), Color(0xFF16718A)]),
  ),
);

Widget _scene({
  required bool retained,
  required bool active,
  double ratio = 2 / 3,
  bool tv = true,
  AppTheme? theme,
  Color? veil,
  Widget art = _art,
  double offset = 0,
}) {
  final children = [art];
  return MaterialApp(
    home: AppThemeScope(
      theme: theme ?? AppThemes.legacy,
      child: Center(
        child: RepaintBoundary(
          key: _capture,
          child: SizedBox(
            width: 360,
            height: 400,
            child: ColoredBox(
              color: const Color(0xFF282034),
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: SizedBox(
                    width: 160,
                    child: retained
                        ? CollectionCardFocusRise(
                            key: _card,
                            active: active,
                            isTelevision: tv,
                            aspectRatio: ratio,
                            ringColor: Colors.orange,
                            restVeil: veil,
                            children: children,
                          )
                        : CardFocusRise(
                            key: _card,
                            active: active,
                            isTelevision: tv,
                            aspectRatio: ratio,
                            ringColor: Colors.orange,
                            restVeil: veil,
                            children: children,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void _sameAppearance(Uint8List original, Uint8List retained, String sample) {
  expect(retained.length, original.length);
  var total = 0;
  var largest = 0;
  for (var i = 0; i < original.length; i++) {
    final difference = (original[i] - retained[i]).abs();
    total += difference;
    if (difference > largest) {
      largest = difference;
    }
  }
  // Layer opacity quantizes separately from shadow colour. Allow small channel
  // rounding, but reject missing shadows/rings, changed clips or timing/scale.
  expect(largest, lessThanOrEqualTo(3), reason: sample);
  expect(total / original.length, lessThan(0.15), reason: sample);
}

Future<List<Uint8List>> _transition(
  WidgetTester tester, {
  required bool retained,
  required double ratio,
  Color? veil,
  bool tv = true,
  AppTheme? theme,
}) async {
  await tester.pumpWidget(const SizedBox());
  Widget scene(bool active) => _scene(
    retained: retained,
    active: active,
    ratio: ratio,
    veil: veil,
    tv: tv,
    theme: theme,
  );
  await tester.pumpWidget(scene(false));
  final samples = [await _pixels(tester)];
  await tester.pumpWidget(scene(true));
  for (final elapsed in [16, 32, 72]) {
    await tester.pump(Duration(milliseconds: elapsed));
    samples.add(await _pixels(tester));
  }
  await tester.pumpWidget(scene(false));
  await tester.pump(const Duration(milliseconds: 32));
  samples.add(await _pixels(tester));
  // Reverse an unfinished fade, as real repeated DPAD traversal does.
  await tester.pumpWidget(scene(true));
  await tester.pump(const Duration(milliseconds: 16));
  samples.add(await _pixels(tester));
  await tester.pumpAndSettle();
  samples.add(await _pixels(tester));
  return samples;
}

void main() {
  for (final ratio in [2 / 3, 1.0, 16 / 9]) {
    _testWithShadows(
      'retained chrome preserves pixels through reversal: $ratio',
      (tester) async {
        final original = await _transition(
          tester,
          retained: false,
          ratio: ratio,
          veil: const Color(0x55000000),
        );
        final retained = await _transition(
          tester,
          retained: true,
          ratio: ratio,
          veil: const Color(0x55000000),
        );
        for (var i = 0; i < original.length; i++) {
          _sameAppearance(original[i], retained[i], 'ratio=$ratio sample=$i');
        }
      },
    );
  }

  _testWithShadows(
    'focus and translated frames reuse shadow and content painting',
    (tester) async {
      Future<(int, int)> count(bool retained) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_scene(retained: retained, active: true));
        await tester.pumpAndSettle();
        var shadows = 0;
        var clips = 0;
        final oldCallback = debugOnProfilePaint;
        debugOnProfilePaint = (object) {
          oldCallback?.call(object);
          if (object is RenderDecoratedBox &&
              object.decoration is BoxDecoration &&
              ((object.decoration as BoxDecoration).boxShadow?.isNotEmpty ??
                  false)) {
            shadows++;
          }
          if (object is RenderClipRRect) {
            clips++;
          }
        };
        try {
          // Both layers have painted once. Repeated focus reversals and movement
          // should compose those same layers instead of recording them again.
          for (var step = 0; step < 4; step++) {
            await tester.pumpWidget(
              _scene(retained: retained, active: step.isOdd, offset: step * 3),
            );
            for (var frame = 0; frame < 5; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
          }
        } finally {
          debugOnProfilePaint = oldCallback;
        }
        return (shadows, clips);
      }

      final original = await count(false);
      final retained = await count(true);
      // Measured paint callbacks, not assertions about the widget source shape.
      expect(original.$1, greaterThanOrEqualTo(20));
      expect(original.$2, greaterThanOrEqualTo(20));
      expect(retained.$1, 0);
      expect(retained.$2, 0);
      debugPrint(
        'focus paint callbacks: original=$original retained=$retained',
      );
    },
  );

  _testWithShadows(
    'retained content updates and resizes without stale layers',
    (tester) async {
      await tester.pumpWidget(_scene(retained: true, active: true));
      final before = await _pixels(tester);
      const changed = ColoredBox(color: Colors.green);
      await tester.pumpWidget(
        _scene(retained: true, active: true, art: changed, ratio: 16 / 9),
      );
      await tester.pumpAndSettle();
      final after = await _pixels(tester);
      expect(after, isNot(orderedEquals(before)));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _scene(retained: false, active: true, art: changed, ratio: 16 / 9),
      );
      _sameAppearance(await _pixels(tester), after, 'updated artwork and size');
    },
  );

  for (final tv in [false, true]) {
    _testWithShadows('shared fallback remains unchanged: tv=$tv', (
      tester,
    ) async {
      final theme = tv ? AppThemes.byId('noir') : AppThemes.legacy;
      if (tv) {
        expect(theme.isLegacy, isFalse);
      }
      final original = await _transition(
        tester,
        retained: false,
        ratio: 2 / 3,
        tv: tv,
        theme: theme,
      );
      final retained = await _transition(
        tester,
        retained: true,
        ratio: 2 / 3,
        tv: tv,
        theme: theme,
      );
      for (var i = 0; i < original.length; i++) {
        expect(retained[i], orderedEquals(original[i]));
      }
    });
  }
}

void _testWithShadows(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = previous;
    }
  });
}
