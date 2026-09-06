import 'package:debrify/services/storage/home_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'favourites_rows_origin_test.dart'
    show prepareFavourites, mountFavourites, closeFavourites;
import 'search_board_runtime_origin_test.dart' show installCatalog, page;

// Diagnostic only: one actual Home mount, no navigation replay or green pin.
// The existing helper's font transport/text scale are unchanged from the held
// origin. No error is consumed: every original details object is forwarded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('attribute the existing Atrium layout overflow without hiding it', (
    tester,
  ) async {
    final originalHandler = FlutterError.onError!;
    var captures = 0;
    var attributedFlexes = 0;
    void dumpBox(RenderObject object, int depth) {
      if (depth > 5) return;
      final prefix = 'ATTRIBUTION depth=$depth ${object.runtimeType}';
      if (object is RenderBox) {
        debugPrintSynchronously(
          '$prefix constraints=${object.constraints} '
          'size=${object.hasSize ? object.size : "unlaid"} '
          'parentData=${object.parentData} creator=${object.debugCreator}',
        );
      }
      if (object is RenderParagraph) {
        debugPrintSynchronously(
          '$prefix text=${object.text.toPlainText()} '
          'span=${object.text.toStringDeep()} scaler=${object.textScaler} '
          'maxLines=${object.maxLines} strut=${object.strutStyle} '
          'textHeightBehavior=${object.textHeightBehavior}',
        );
      }
      object.visitChildren((child) => dumpBox(child, depth + 1));
    }

    FlutterError.onError = (details) {
      try {
        if (captures == 0 &&
            details.exceptionAsString().contains('RenderFlex overflowed')) {
          captures++;
          debugPrintSynchronously('ATTRIBUTION original=${details.exceptionAsString()}');
          debugPrintSynchronously('ATTRIBUTION stack=${details.stack} context=${details.context}');
          for (final node in details.informationCollector?.call() ??
              const <DiagnosticsNode>[]) {
            debugPrintSynchronously('ATTRIBUTION details=${node.toStringDeep()}');
            final value = node.value;
            if (value is RenderFlex) {
              attributedFlexes++;
              debugPrintSynchronously('ATTRIBUTION emittingFlex=${value.toStringShort()} direction=${value.direction}');
              dumpBox(value, 0);
            }
          }
        }
      } finally {
        originalHandler(details);
      }
    };
    try {
      await prepareFavourites(tester);
      expect(tester.view.physicalSize, const Size(1920, 1080));
      await StorageService.setTvHomeStyle('atrium');
      await HomePrefs.setHomeHeroSource((
        mode: HomeHeroSourceMode.auto,
        ids: const [],
      ));
      await installCatalog(rows: 3);
      await http.runWithClient(
        () async {
          try {
            await mountFavourites(tester);
            debugPrintSynchronously('ATTRIBUTION result captures=$captures flexes=$attributedFlexes');
            expect(captures, 1, reason: 'No second attempt if the overflow is absent.');
            expect(attributedFlexes, 1, reason: 'Unattributed means stop, not retry.');
          } finally {
            await closeFavourites(tester);
          }
        },
        () => MockClient((request) async {
          expect(request.url.host, 'board-origin.invalid');
          final match = RegExp(r'^rail([1-2]?)\.json$')
              .firstMatch(request.url.pathSegments.last);
          if (match == null) fail('Unexpected Atrium request: ${request.url}');
          return page((int.tryParse(match.group(1)!) ?? 0) * 100, 12);
        }),
      );
    } finally {
      FlutterError.onError = originalHandler;
    }
  });
}
