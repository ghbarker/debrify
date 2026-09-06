import 'package:debrify/services/player_visibility.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_save_feedback.dart';
import 'package:debrify/widgets/webdav_sync/webdav_save_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('both player owners hide all feedback without losing receipts', (
    tester,
  ) async {
    final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
    final flutterPlayer = Object();
    final nativePlayer = Object();
    addTearDown(() {
      PlayerVisibility.closed(flutterPlayer);
      PlayerVisibility.closed(nativePlayer);
      feedback.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: WebDavSaveStatus(
          feedback: feedback,
          child: const Scaffold(body: Text('Player')),
        ),
      ),
    );
    feedback.saved(1);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    PlayerVisibility.opened(flutterPlayer);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    feedback.saved(2);
    feedback.waiting();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(feedback.hasPending, isTrue);
    PlayerVisibility.opened(nativePlayer);
    PlayerVisibility.closed(flutterPlayer);
    await tester.pump();
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    feedback.finished(2, published: true);
    await tester.pump();
    expect(find.text('Synced to WebDAV'), findsNothing);
    feedback.saved(3);
    feedback.waiting();
    await tester.pump();
    PlayerVisibility.closed(nativePlayer);
    await tester.pump();
    expect(find.text('Saved locally · Sync pending'), findsOneWidget);
    expect(feedback.hasPending, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('player opening dismisses save dialog and blocks new dialogs', (
    tester,
  ) async {
    final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
    final owner = Object();
    addTearDown(() {
      PlayerVisibility.closed(owner);
      feedback.dispose();
    });
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    feedback.saved(1);
    final dialog = showWebDavSaveProgress(pageContext, 0, feedback: feedback);
    await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    PlayerVisibility.opened(owner);
    await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    await dialog;
    expect(find.byType(AlertDialog), findsNothing);
    await showWebDavSaveProgress(pageContext, 0, feedback: feedback);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(feedback.hasPending, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'phone status clears navigation and collapses with accessible Retry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
      addTearDown(feedback.dispose);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              WebDavSaveStatus(feedback: feedback, child: child!),
          home: Scaffold(
            bottomNavigationBar: SizedBox(
              height: 80,
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Discover'),
              ),
            ),
          ),
        ),
      );
      feedback.saved(1);
      await tester.pump();
      final banner = find.text('Saved locally · Syncing to WebDAV…');
      expect(
        tester.getRect(banner).bottom,
        lessThan(tester.getRect(find.text('Discover')).top),
      );
      await tester.tap(find.text('Discover'));
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(banner, findsNothing);
      feedback.waiting();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Retry'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'pending publication is restored after restart and cleared only on success',
    () async {
      SharedPreferences.setMockInitialValues({
        WebDavSyncSaveFeedback.pendingKey: true,
      });
      final feedback = WebDavSyncSaveFeedback(persistent: true);
      await feedback.initialize();
      feedback.setEnabled(true);
      expect(feedback.hasPending, isTrue);
      expect(feedback.phase, WebDavSavePhase.pending);
      feedback.finished(feedback.revision, published: false);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          WebDavSyncSaveFeedback.pendingKey,
        ),
        isTrue,
      );
      feedback.finished(feedback.revision, published: true);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          WebDavSyncSaveFeedback.pendingKey,
        ),
        isFalse,
      );
      feedback.dispose();
    },
  );

  test('inactive retry never leaves a permanent spinner', () async {
    final feedback = WebDavSyncSaveFeedback()
      ..setEnabled(true)
      ..saved(1);
    feedback.finished(1, published: false);
    feedback.retryAction = () async {};
    await feedback.retry();
    expect(feedback.phase, WebDavSavePhase.pending);
    expect(feedback.hasPending, isTrue);
    feedback.dispose();
  });

  test('a cycle acknowledges only the edits in its starting snapshot', () {
    final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
    feedback.saved(1);
    feedback.started();
    feedback.saved(2);
    feedback.finished(1, published: true);
    expect(feedback.hasPending, isTrue);
    expect(feedback.confirmedRevision, 1);
    feedback.finished(2, published: false);
    expect(feedback.phase, WebDavSavePhase.pending);
    feedback.finished(2, published: true);
    expect(feedback.phase, WebDavSavePhase.synced);
    expect(feedback.hasPending, isFalse);
    feedback.dispose();
  });

  test('disarming hides feedback without acknowledging pending saves', () {
    final feedback = WebDavSyncSaveFeedback()
      ..setEnabled(true)
      ..saved(1);
    feedback.setEnabled(false);
    expect(feedback.phase, WebDavSavePhase.inactive);
    expect(feedback.hasPending, isTrue);
    feedback.setEnabled(true);
    expect(feedback.phase, WebDavSavePhase.pending);
    feedback.dispose();
  });

  for (final outcome in [
    'timeout',
    'continue',
    'success',
    'failure',
    'disabled',
  ]) {
    testWidgets(
      'profile save dialog handles $outcome without canceling pending work',
      (tester) async {
        final feedback = WebDavSyncSaveFeedback()
          ..setEnabled(outcome != 'disabled');
        var returned = false;
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) =>
                WebDavSaveStatus(feedback: feedback, child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final before = feedback.revision;
                    if (feedback.enabled) feedback.saved(1);
                    await showWebDavSaveProgress(
                      context,
                      before,
                      feedback: feedback,
                    );
                    returned = true;
                  },
                  child: const Text('Save'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (outcome == 'disabled') {
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          switch (outcome) {
            case 'timeout':
              await tester.pump(const Duration(seconds: 15));
            case 'continue':
              await tester.tap(find.text('Continue in background'));
            case 'success':
              feedback.finished(1, published: true);
            case 'failure':
              feedback.finished(1, published: false);
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(AlertDialog), findsNothing);
          expect(feedback.hasPending, outcome != 'success');
          if (outcome == 'timeout') {
            expect(
              find.text('Sync is taking longer. Your change is saved locally.'),
              findsOneWidget,
            );
          }
          if (outcome == 'failure') expect(find.text('Retry'), findsOneWidget);
        }
        expect(returned, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        feedback.dispose();
      },
    );
  }
}
