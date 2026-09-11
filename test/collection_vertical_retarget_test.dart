import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/collections/collection_tv_rails.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Observe the framework's real activity, without a production diagnostic API.
ScrollActivity activityOf(ScrollPosition position) {
  // ignore: invalid_use_of_protected_member
  return position.activity!;
}

List<CollectionTvRail> rails(int count) => [
  for (var i = 0; i < count; i++)
    CollectionTvRail(
      id: '$i',
      title: 'Row $i',
      loading: false,
      items: [StremioMeta(id: '$i', type: 'movie', name: 'Movie $i')],
      onLoadMore: () {},
    ),
];

void main() {
  late GlobalKey<CollectionTvRailsState> owner;
  late ValueNotifier<List<CollectionTvRail>> rows;
  late ScrollController controller;
  setUp(() {
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    owner = GlobalKey<CollectionTvRailsState>();
    rows = ValueNotifier(rails(40));
  });
  tearDown(() => rows.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: rows,
            builder: (_, value, _) => CollectionTvRails(
              key: owner,
              rails: value,
              landscapeCards: true,
              onOpen: (_) {},
              onExitTop: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller = tester
        .widgetList<ListView>(find.byType(ListView))
        .singleWhere((list) => list.scrollDirection == Axis.vertical)
        .controller!;
    owner.currentState!.focusFirst();
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  for (final interval in [80, 112, 144]) {
    testWidgets('repeated Down preserves velocity and ticker at ${interval}ms', (
      tester,
    ) async {
      await mount(tester);
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      final position = controller.position;
      for (var press = 0; press < 5; press++) {
        final previous = activityOf(position);
        final offset = position.pixels;
        final velocity = previous.velocity;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        expect(position.pixels, offset);
        if (press > 0) {
          expect(
            activityOf(position),
            same(previous),
            reason: 'Retarget must retain the live ticker.',
          );
          expect(
            activityOf(position).velocity,
            closeTo(velocity, .000001),
            reason: 'Velocity must not reset at a key event.',
          );
          expect(velocity, greaterThan(0));
        }
        for (var frame = 0; frame < interval ~/ 8; frame++) {
          final before = position.pixels;
          await tester.pump(const Duration(milliseconds: 8));
          if (press > 0 || frame > 0) {
            expect(
              position.pixels,
              greaterThan(before),
              reason:
                  'An in-flight retarget must not insert a stationary first frame.',
            );
          }
        }
      }
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'collection_title_10',
      );
      expect(activityOf(position).isScrolling, isFalse);
    });
  }

  for (final nearEnd in [false, true]) {
    testWidgets('reversal brakes continuously within bounds nearEnd=$nearEnd', (
      tester,
    ) async {
      await mount(tester);
      final position = controller.position;
      controller.jumpTo(nearEnd ? position.maxScrollExtent - 30 : 30);
      final first = controller.animateTo(
        nearEnd ? position.maxScrollExtent : 0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      final driven = activityOf(position);
      final before = position.pixels;
      final velocity = driven.velocity;
      final target = nearEnd ? 0.0 : position.maxScrollExtent;
      final second = controller.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      expect(activityOf(position), same(driven));
      expect(position.pixels, before);
      expect(driven.velocity, closeTo(velocity, .000001));
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        position.pixels,
        nearEnd ? greaterThan(before) : lessThan(before),
        reason:
            'A reversal brakes the existing velocity instead of snapping its sign.',
      );
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
      }
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      expect(position.pixels, closeTo(target, .001));
    });
  }

  testWidgets(
    'direct interruption completes old activity and starts a fresh single glide',
    (tester) async {
      await mount(tester);
      final first = controller.animateTo(
        1200,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final old = activityOf(controller.position);
      controller.jumpTo(100);
      await first;
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.offset, 100);
      final second = controller.animateTo(
        300,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      expect(activityOf(controller.position), isNot(same(old)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(
        controller.offset,
        closeTo(100 + 200 * Curves.easeOutCubic.transform(.5), .001),
      );
      await tester.pumpAndSettle();
      await second;
      expect(controller.offset, 300);
    },
  );

  testWidgets(
    'shrinking and growing content honor metrics during an active glide',
    (tester) async {
      await mount(tester);
      final future = controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      rows.value = rails(10);
      await tester.pumpAndSettle();
      await future;
      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, .001),
      );
      rows.value = rails(50);
      await tester.pumpAndSettle();
      final next = controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pumpAndSettle();
      await next;
      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, .001),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposal completes a retargeted activity without further ticks',
    (tester) async {
      await mount(tester);
      final first = controller.animateTo(
        1200,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final second = controller.animateTo(
        2400,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pumpWidget(const SizedBox());
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fast reversal after metrics shrink brakes before the new boundary',
    (tester) async {
      await mount(tester);
      final position = controller.position;
      final first = controller.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      rows.value = rails(10);
      await tester.pump();
      final driven = activityOf(position);
      final velocity = driven.velocity;
      final room = position.maxScrollExtent - position.pixels;
      expect(
        velocity * .260 * 4 / 27,
        greaterThan(room),
        reason: 'This fixture must require the braking-space bound.',
      );
      final second = controller.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      expect(activityOf(position), same(driven));
      expect(driven.velocity, closeTo(velocity, .000001));
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
      }
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      expect(
        position.pixels,
        closeTo(0, .001),
        reason:
            'Hitting a boundary must not discard the requested reverse destination.',
      );
    },
  );

  testWidgets('touch interruption releases the driven activity', (
    tester,
  ) async {
    await mount(tester);
    final future = controller.animateTo(
      1500,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final driven = activityOf(controller.position);
    await tester.drag(find.byType(CollectionTvRails), const Offset(0, 80));
    await tester.pumpAndSettle();
    await future;
    expect(activityOf(controller.position), isNot(same(driven)));
    expect(controller.offset, isNot(closeTo(1500, 1)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retarget from the completing pixel notification starts a live activity',
    (tester) async {
      await mount(tester);
      Future<void>? next;
      void atDestination() {
        if (controller.offset >= 100 && next == null) {
          next = controller.animateTo(
            300,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
      }

      controller.addListener(atDestination);
      final first = controller.animateTo(
        100,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 264));
      await tester.pumpAndSettle();
      await first;
      expect(next, isNotNull);
      await next;
      expect(controller.offset, closeTo(300, .001));
      controller.removeListener(atDestination);
    },
  );
  testWidgets('review duplicate target preserves deadline and finite motion', (
    tester,
  ) async {
    await mount(tester);
    final p = controller.position;
    final futures = <Future<void>>[];
    futures.add(
      controller.animateTo(
        1000,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final before = p.pixels;
      final v = activityOf(p).velocity;
      futures.add(
        controller.animateTo(
          1000,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
      expect(p.pixels, before);
      expect(activityOf(p).velocity, v);
      expect(p.pixels.isFinite, isTrue);
    }
    await tester.pump(const Duration(milliseconds: 8));
    expect(p.pixels, closeTo(1000, .001));
    expect(activityOf(p).isScrolling, isFalse);
    await Future.wait(futures);
  });

  testWidgets('review shrinking bounds preserves a still valid reversal target', (
    tester,
  ) async {
    await mount(tester);
    rows.value = rails(10);
    await tester.pumpAndSettle();
    controller.jumpTo(100000);
    await tester.pumpAndSettle();
    final newMax = controller.position.maxScrollExtent;
    rows.value = rails(40);
    await tester.pumpAndSettle();
    final p = controller.position;
    controller.jumpTo(newMax - 40);
    await tester.pumpAndSettle();
    final first = controller.animateTo(
      newMax + 100,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final target = p.pixels - 20;
    expect(p.pixels, lessThan(newMax));
    final second = controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    // The new bound still contains both the current offset and the destination.
    // Only the outgoing braking excursion needs to adapt to the smaller range.
    rows.value = rails(10);
    await tester.pump();
    final initial = p.pixels;
    final initialVelocity = activityOf(p).velocity;
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(
      p.pixels,
      closeTo(target, .001),
      reason: 'initial=$initial velocity=$initialVelocity newMax=$newMax',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged dimensions preserve curve epoch and deadline', (
    tester,
  ) async {
    await mount(tester);
    final position = controller.position as ScrollPositionWithSingleContext;
    final future = controller.animateTo(
      1000,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await tester.pump();
    final driven = activityOf(position);
    for (var frame = 1; frame <= 32; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
      final velocity = driven.velocity;
      // Exercise the viewport correction protocol with unchanged dimensions;
      // applyNewDimensions cannot be called directly without pending layout.
      position.correctBy(0);
      position.applyContentDimensions(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      expect(activityOf(position), same(driven));
      expect(driven.velocity, velocity);
      expect(
        position.pixels,
        closeTo(1000 * Curves.easeOutCubic.transform(frame * 8 / 260), .001),
      );
    }
    await tester.pump(const Duration(milliseconds: 8));
    await future;
    expect(position.pixels, 1000);
    expect(activityOf(position).isScrolling, isFalse);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('changing dimensions keeps the existing animation deadline', (
    tester,
  ) async {
    await mount(tester);
    final position = controller.position;
    final first = controller.animateTo(
      1000,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final future = controller.animateTo(
      3000,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    final driven = activityOf(position);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      final velocity = driven.velocity;
      rows.value = rails(41 + i);
      await tester.pump();
      expect(activityOf(position), same(driven));
      expect(driven.velocity, closeTo(velocity, .000001));
    }
    await tester.pump(const Duration(milliseconds: 8));
    expect(position.pixels, closeTo(3000, .001));
    expect(activityOf(position).isScrolling, isFalse);
    await Future.wait([first, future]);
    await tester.pumpAndSettle();
  });
}
