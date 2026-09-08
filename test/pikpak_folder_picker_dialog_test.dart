import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/pikpak_folder_picker_dialog.dart';

/// Enough root folders that a short test viewport can only ever mount a
/// handful of rows at once -- the ListView.builder recycles the rest, which
/// is exactly the condition that made the old "jump straight to the last
/// FocusNode" code a silent no-op (or a focus jump to an off-screen row).
List<Map<String, dynamic>> _folders(int count) => List.generate(
  count,
  (i) => {
    'id': 'folder-${i.toString().padLeft(2, '0')}',
    'name': 'Folder ${i.toString().padLeft(2, '0')}',
    'kind': 'drive#folder',
  },
);

Future<void> _openDialog(
  WidgetTester tester, {
  required int folderCount,
  Size viewportSize = const Size(700, 700),
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<Map<String, dynamic>>(
              context: context,
              builder: (ctx) => PikPakFolderPickerDialog(
                isTelevisionOverride: true,
                listFilesOverride:
                    ({parentId, limit = 100, pageToken}) async {
                      if (parentId != null) {
                        // No nested children in this fixture.
                        return (
                          files: <Map<String, dynamic>>[],
                          nextPageToken: null,
                        );
                      }
                      return (files: _folders(folderCount), nextPageToken: null);
                    },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The [ButtonStyleButton] (FilledButton/TextButton) rendering [label]'s
/// text -- used to reach into its explicit `focusNode:` param and drive
/// focus directly, the way a real remote's D-pad would after landing there.
FocusNode _buttonFocusNode(WidgetTester tester, String label) {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  return tester.widget<ButtonStyleButton>(finder).focusNode!;
}

/// Global rect of whatever currently holds primary focus, e.g. a folder
/// row's `Focus` widget.
Rect _primaryFocusRect(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus!.context!;
  final renderObject = context.findRenderObject()! as RenderBox;
  final topLeft = renderObject.localToGlobal(Offset.zero);
  return topLeft & renderObject.size;
}

/// Whether [target] sits fully inside [viewport], within [tolerance] px.
/// `Rect.contains` treats the right/bottom edges as exclusive, which makes a
/// row that is scrolled exactly flush with the viewport's edge (as happens
/// here: the last folder is also the end of the scroll extent, so there's no
/// room left for tvRevealMinimal's usual margin) register as "outside" by a
/// fraction of a pixel -- a false negative this tolerance avoids.
bool _fullyVisible(Rect target, Rect viewport, {double tolerance = 6}) {
  return target.left >= viewport.left - tolerance &&
      target.top >= viewport.top - tolerance &&
      target.right <= viewport.right + tolerance &&
      target.bottom <= viewport.bottom + tolerance;
}

void main() {
  testWidgets(
    'TV: DPAD UP from New Folder scrolls the last folder into view and focuses it',
    (tester) async {
      await _openDialog(tester, folderCount: 35);

      // Sanity: far more folders exist than the short viewport can show, so
      // the ListView.builder has not built the tail of the list yet.
      expect(find.text('Folder 34'), findsNothing);

      _buttonFocusNode(tester, 'New Folder').requestFocus();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'new-folder-button');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      // Landed on the actual last folder's FocusNode...
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'folder-item-34',
      );
      // ...and it's now built and visible, not off-screen.
      expect(find.text('Folder 34'), findsOneWidget);
      final viewport = tester.getRect(find.byType(ListView));
      final focused = _primaryFocusRect(tester);
      expect(
        _fullyVisible(focused, viewport),
        isTrue,
        reason:
            'focused last folder $focused is outside the list viewport $viewport',
      );
    },
  );

  testWidgets(
    'TV: DPAD UP from Cancel and Confirm also lands on the visible last folder',
    (tester) async {
      await _openDialog(tester, folderCount: 40);

      _buttonFocusNode(tester, 'Cancel').requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'folder-item-39');
      expect(find.text('Folder 39'), findsOneWidget);
      var viewport = tester.getRect(find.byType(ListView));
      var focused = _primaryFocusRect(tester);
      expect(
        _fullyVisible(focused, viewport),
        isTrue,
        reason: 'Cancel->UP landed outside the list viewport: $focused vs $viewport',
      );

      // Select the first folder so the Confirm ("Select") button is enabled,
      // then repeat the same DPAD-UP check from there. UP just parked focus
      // at the bottom of the list, so scroll back up to reach it.
      if (find.text('Folder 00').evaluate().isEmpty) {
        await tester.drag(find.byType(ListView), const Offset(0, 4000));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Folder 00'));
      await tester.pumpAndSettle();

      _buttonFocusNode(tester, 'Select').requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'folder-item-39');
      expect(find.text('Folder 39'), findsOneWidget);
      viewport = tester.getRect(find.byType(ListView));
      focused = _primaryFocusRect(tester);
      expect(
        _fullyVisible(focused, viewport),
        isTrue,
        reason: 'Confirm->UP landed outside the list viewport: $focused vs $viewport',
      );
    },
  );

  testWidgets(
    'TV: DPAD DOWN from the last folder still returns to New Folder',
    (tester) async {
      await _openDialog(tester, folderCount: 35);

      // Land on the last folder the same way the UP-from-buttons fix does,
      // then confirm the already-correct forward direction (small, one-row
      // traversal, not a cross-list jump) still hands off to the button row.
      _buttonFocusNode(tester, 'New Folder').requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'folder-item-34');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'new-folder-button',
        reason: 'DOWN from the last folder must hand focus back to New Folder',
      );
    },
  );
}
