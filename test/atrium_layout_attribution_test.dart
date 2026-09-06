import 'dart:convert';

import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, pumpFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart' show installCatalog, page;

// Red attribution is retained in commit f66cff53 and its original raw log.
// These are real Home geometry regressions, not an Atrium extraction pin.
List<RenderParagraph> checkActualWall(WidgetTester tester, int expectedRows) {
  final lists = find.byType(ListView).evaluate().where((e) {
    final key = e.widget.key;
    return key is ValueKey<String> && key.value.startsWith('atrium-rail-');
  }).toList();
  expect(lists, isNotEmpty);
  Element columnAbove(Element e) {
    Element? column;
    e.visitAncestorElements((ancestor) {
      if (ancestor.widget is Column) {
        column = ancestor;
        return false;
      }
      return true;
    });
    return column!;
  }

  final rows = lists.map(columnAbove).toList();
  final wall = columnAbove(rows.first).findRenderObject()! as RenderFlex;
  var actualChildrenHeight = 0.0;
  wall.visitChildren((child) {
    actualChildrenHeight += (child as RenderBox).size.height;
  });
  // Independent actual RenderObject dimensions, no copied budget helper.
  expect(wall.size.height, closeTo(actualChildrenHeight, 0.000001));
  final paragraphs = <RenderParagraph>[];
  for (final row in rows) {
    final render = row.findRenderObject()! as RenderFlex;
    render.visitChildren((child) {
      if (child is RenderParagraph) paragraphs.add(child);
    });
  }
  final board = wall.parent! as RenderBox;
  debugPrint('ATRIUM geometry view=${tester.view.physicalSize} '
      'dpr=${tester.view.devicePixelRatio} board=${board.size} '
      'boardConstraints=${board.constraints} wall=${wall.size} '
      'wallConstraints=${wall.constraints} children=$actualChildrenHeight '
      'labels=${paragraphs.map((p) => '${p.size}/${p.constraints}').join(';')}');
  expect(board.size, tester.view.physicalSize / tester.view.devicePixelRatio);
  expect(wall.constraints.isTight, isTrue);
  expect(paragraphs, hasLength(lists.length));
  for (final paragraph in paragraphs) {
    expect(paragraph.size.height, greaterThan(0));
    expect(paragraph.maxLines, 1);
    expect(paragraph.overflow, TextOverflow.ellipsis);
    expect(paragraph.strutStyle, isNull);
  }
  expect(lists, hasLength(expectedRows));
  expect(tester.takeException(), isNull);
  return paragraphs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = [
    (name: 'original 1920x1080 label budget matches actual paragraphs',
      height: 1080.0, rows: 2, scale: 0.8, inheritedHeight: 1.4,
      bold: false, rtl: false, spacing: false, longTitle: false),
    (name: 'inherited taller italic style and scaler preserve actual budget',
      height: 1080.0, rows: 2, scale: 1.2, inheritedHeight: 1.9,
      bold: false, rtl: false, spacing: false, longTitle: false),
    (name: 'bold RTL long ellipsis uses the actual inherited paragraph',
      height: 1080.0, rows: 2, scale: 1.1, inheritedHeight: 1.4,
      bold: true, rtl: true, spacing: false, longTitle: true),
    (name: 'spacing overrides replace inherited height with null strut',
      height: 1080.0, rows: 2, scale: 1.0, inheritedHeight: 2.2,
      bold: true, rtl: true, spacing: true, longTitle: true),
    (name: 'below two-row threshold keeps one truthful row',
      height: 436.0, rows: 1, scale: 0.8, inheritedHeight: 1.4,
      bold: false, rtl: false, spacing: false, longTitle: false),
    (name: 'above two-row threshold fits both truthful rows',
      height: 440.0, rows: 2, scale: 0.8, inheritedHeight: 1.4,
      bold: false, rtl: false, spacing: false, longTitle: false),
  ];
  for (final scenario in cases) {
    testWidgets(scenario.name, (tester) async {
      final originalTheme = scenario.scale == 0.8;
      await prepareFavourites(tester);
      tester.view.physicalSize = Size(1920, scenario.height);
      await StorageService.setTvHomeStyle('atrium');
      await HomePrefs.setHomeHeroSource((mode: HomeHeroSourceMode.auto, ids: const []));
      await installCatalog(rows: 3);
      if (scenario.longTitle) {
        final prefs = await SharedPreferences.getInstance();
        final addons = jsonDecode(prefs.getString('stremio_addons_v1')!) as List;
        for (final catalog in (addons.first as Map)['catalogs'] as List) {
          (catalog as Map)['name'] = List.filled(60, 'مرحبا Origin rail').join(' ');
        }
        await prefs.setString('stremio_addons_v1', jsonEncode(addons));
      }
      await http.runWithClient(() async {
        try {
          final theme = ThemeData.light();
          await tester.pumpWidget(originalTheme ? MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(0.8),
              ),
              child: child!,
            ),
            home: const SearchScreen(isTelevision: true),
          ) : MaterialApp(
            theme: theme.copyWith(textTheme: theme.textTheme.copyWith(
              bodyMedium: theme.textTheme.bodyMedium!.copyWith(
                height: scenario.inheritedHeight,
                fontStyle: scenario.inheritedHeight == 1.9 ? FontStyle.italic : FontStyle.normal,
              ),
            )),
            locale: const Locale('en', 'GB'),
            supportedLocales: const [Locale('en', 'GB')],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scenario.scale),
                boldText: scenario.bold,
              ).applyTextStyleOverrides(
                lineHeightScaleFactorOverride: scenario.spacing ? 1.6 : null,
                letterSpacingOverride: scenario.spacing ? 2.5 : null,
                wordSpacingOverride: scenario.spacing ? 4.0 : null,
                paragraphSpacingOverride: null,
              ),
              child: Directionality(
                textDirection: scenario.rtl ? TextDirection.rtl : TextDirection.ltr,
                child: DefaultTextHeightBehavior(
                  textHeightBehavior: TextHeightBehavior(
                    applyHeightToFirstAscent: !scenario.spacing,
                    applyHeightToLastDescent: !scenario.spacing,
                  ),
                  child: child!,
                ),
              ),
            ),
            home: const SearchScreen(isTelevision: true),
          ));
          await pumpFavourites(tester);
          final labels = checkActualWall(tester, scenario.rows);
          for (final paragraph in labels) {
            final style = (paragraph.text as TextSpan).style!;
            expect(style.fontWeight, scenario.bold ? FontWeight.bold : FontWeight.w800);
            if (originalTheme) {
              expect(style.height, Theme.of(find.byType(SearchScreenHost).evaluate().single).textTheme.bodyMedium!.height);
              expect(paragraph.textHeightBehavior, isNull);
            } else {
              expect(style.height, scenario.spacing ? 1.6 : scenario.inheritedHeight);
            }
            expect(paragraph.textScaler.scale(12), 12 * scenario.scale);
            expect(paragraph.textDirection, scenario.rtl ? TextDirection.rtl : TextDirection.ltr);
            expect(paragraph.locale?.languageCode, 'en');
            if (scenario.longTitle) expect(paragraph.didExceedMaxLines, isTrue);
            if (scenario.spacing) {
              expect(style.letterSpacing, 2.5);
              expect(style.wordSpacing, 4);
              expect(paragraph.textHeightBehavior!.applyHeightToFirstAscent, isFalse);
            }
          }
        } finally {
          await closeFavourites(tester);
        }
      }, () => MockClient((request) async {
        expect(request.url.host, 'board-origin.invalid');
        final match = RegExp(r'^rail([1-2]?)\.json$').firstMatch(request.url.pathSegments.last);
        if (match == null) fail('Unexpected Atrium request: ${request.url}');
        return page((int.tryParse(match.group(1)!) ?? 0) * 100, 12);
      }));
    });
  }
}
