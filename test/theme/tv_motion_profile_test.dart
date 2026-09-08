import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/tv_motion_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

/// The TV motion profile, pinned at its three sources of truth: the device
/// default (a pure function of what the box reports), the pref it is stored
/// under, and the figures `AppMotion` vends for each profile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStylePrefs.tvMotionProfileCached = null;
    TvMotionController.debugReset();
  });
  tearDown(() => TvMotionController.debugReset());

  group('device default', () {
    test('Apple TV is smooth, whatever else it says', () {
      expect(
        TvMotionProfile.defaultFor(isTvOs: true, isAndroidTv: false),
        TvMotionProfile.smooth,
      );
    });

    test('the NVIDIA Shield is smooth, by any of its names', () {
      TvMotionProfile shield({
        String? manufacturer,
        String? model,
        String? board,
        String? hardware,
        String? deviceName,
      }) => TvMotionProfile.defaultFor(
        isTvOs: false,
        isAndroidTv: true,
        manufacturer: manufacturer,
        model: model,
        board: board,
        hardware: hardware,
        deviceName: deviceName,
      );
      expect(shield(manufacturer: 'NVIDIA'), TvMotionProfile.smooth);
      expect(shield(manufacturer: 'nvidia'), TvMotionProfile.smooth);
      expect(shield(model: 'SHIELD Android TV'), TvMotionProfile.smooth);
      expect(shield(board: 'mdarcy'), TvMotionProfile.smooth);
      expect(shield(hardware: 'darcy'), TvMotionProfile.smooth);
      expect(shield(board: 'foster'), TvMotionProfile.smooth);
      expect(shield(board: 'sif'), TvMotionProfile.smooth);
      // The factory device name — what the TV listener already advertises.
      expect(shield(deviceName: 'SHIELD'), TvMotionProfile.smooth);
      expect(shield(deviceName: 'Living room shield'), TvMotionProfile.smooth);
    });

    test('a generic Android TV box is snappy', () {
      expect(
        TvMotionProfile.defaultFor(
          isTvOs: false,
          isAndroidTv: true,
          manufacturer: 'Xiaomi',
          model: 'MIBOX4',
          board: 'oneday',
          hardware: 'amlogic',
          deviceName: 'Mi Box',
        ),
        TvMotionProfile.snappy,
      );
      expect(
        TvMotionProfile.defaultFor(
          isTvOs: false,
          isAndroidTv: true,
          manufacturer: 'Google',
          model: 'Chromecast',
          deviceName: 'Chromecast with Google TV',
        ),
        TvMotionProfile.snappy,
      );
      // Nothing reported at all — the plugin failed — is still snappy: the
      // short beat is the safe answer on a box that cannot say what it is.
      expect(
        TvMotionProfile.defaultFor(isTvOs: false, isAndroidTv: true),
        TvMotionProfile.snappy,
      );
    });

    test('off a television the profile is snappy and unread', () {
      expect(
        TvMotionProfile.defaultFor(
          isTvOs: false,
          isAndroidTv: false,
          manufacturer: 'NVIDIA',
        ),
        TvMotionProfile.snappy,
      );
    });
  });

  group('the pref', () {
    test('unset reads as null — the device default decides, not a string', () async {
      expect(await AppStylePrefs.getTvMotionProfile(), isNull);
      expect(AppStylePrefs.tvMotionProfileCached, isNull);
      expect(TvMotionProfile.fromPref(null), isNull);
    });

    test('round-trips both spellings and mirrors before the write', () async {
      final future = AppStylePrefs.setTvMotionProfile('smooth');
      expect(AppStylePrefs.tvMotionProfileCached, 'smooth');
      await future;
      expect(await AppStylePrefs.getTvMotionProfile(), 'smooth');
      await AppStylePrefs.setTvMotionProfile('snappy');
      expect(await AppStylePrefs.getTvMotionProfile(), 'snappy');
      expect(TvMotionProfile.fromPref('smooth'), TvMotionProfile.smooth);
      expect(TvMotionProfile.fromPref('snappy'), TvMotionProfile.snappy);
    });

    test('an unknown value is refused on write and unset on read', () async {
      await AppStylePrefs.setTvMotionProfile('smooth');
      await AppStylePrefs.setTvMotionProfile('some-future-profile');
      expect(await AppStylePrefs.getTvMotionProfile(), 'smooth');
      SharedPreferences.setMockInitialValues({
        'tv_motion_profile': 'some-future-profile',
      });
      expect(await AppStylePrefs.getTvMotionProfile(), isNull);
      expect(TvMotionProfile.fromPref('some-future-profile'), isNull);
    });

    test('is owned, sanitised and copied like the other style prefs', () {
      expect(AppStylePrefs.ownedKeys, contains('tv_motion_profile'));
      expect(
        ProfileCreationService.copyablePreferenceKeys,
        contains('tv_motion_profile'),
      );
      expect(
        SanitizedProfilePreferences.allowsEntry('tv_motion_profile', 'smooth'),
        isTrue,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry('tv_motion_profile', 'snappy'),
        isTrue,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry('tv_motion_profile', 'fast'),
        isFalse,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry('tv_motion_profile', true),
        isFalse,
      );
    });

    test('resetCaches clears the mirror', () async {
      await AppStylePrefs.setTvMotionProfile('smooth');
      AppStylePrefs.resetCaches();
      expect(AppStylePrefs.tvMotionProfileCached, isNull);
    });
  });

  group('the controller', () {
    test('starts snappy — the shipped TV figures — before any warm', () {
      expect(TvMotionController.current, TvMotionProfile.snappy);
      expect(TvMotionController.isExplicit, isFalse);
    });

    test('warm restores an explicit choice over the device default', () async {
      SharedPreferences.setMockInitialValues({'tv_motion_profile': 'snappy'});
      TvMotionController.debugReset(deviceDefault: TvMotionProfile.smooth);
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.snappy);
      expect(TvMotionController.isExplicit, isTrue);
    });

    test('warm falls back to the device default when nothing is stored', () async {
      TvMotionController.debugReset(deviceDefault: TvMotionProfile.smooth);
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.smooth);
      expect(TvMotionController.isExplicit, isFalse);
    });

    test('warm in a test host (no plugin, no TV) resolves snappy', () async {
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.snappy);
      expect(await TvMotionController.deviceDefault(), TvMotionProfile.snappy);
    });

    test('select publishes synchronously, then persists exactly one key', () async {
      final before = (await SharedPreferences.getInstance()).getKeys();
      final future = TvMotionController.select(TvMotionProfile.smooth);
      expect(TvMotionController.current, TvMotionProfile.smooth);
      expect(TvMotionController.isExplicit, isTrue);
      await future;
      final after = (await SharedPreferences.getInstance()).getKeys();
      final added = after.difference(before);
      expect(added, hasLength(1));
      expect(added.single, endsWith('tv_motion_profile'));
      expect(await AppStylePrefs.getTvMotionProfile(), 'smooth');
    });
  });

  group('AppMotion under each profile', () {
    const snappy = AppMotion(MotionTokens.legacy, reduced: false);
    const smooth = AppMotion(
      MotionTokens.legacy,
      reduced: false,
      profile: TvMotionProfile.smooth,
    );

    test('a hand-built AppMotion is snappy, so the old pins still hold', () {
      expect(snappy.profile, TvMotionProfile.snappy);
    });

    test('snappy vends the shipped TV figures', () {
      expect(snappy.tvFocus, MotionTokens.legacy.fast);
      expect(snappy.tvFocus, const Duration(milliseconds: 120));
      expect(snappy.tvFocusCurve, MotionTokens.legacy.standard);
      expect(snappy.focusCurve(true, Curves.linear), Curves.linear);
      expect(snappy.tvScroll, Duration.zero);
      expect(
        snappy.scrollTempo(true, const Duration(milliseconds: 280)),
        Duration.zero,
      );
      expect(
        snappy.scrollTempo(
          true,
          const Duration(milliseconds: 280),
          tvSnappy: const Duration(milliseconds: 140),
        ),
        const Duration(milliseconds: 140),
        reason: 'the Apple TV board glide keeps its own figure',
      );
      expect(snappy.tvEntrance(EntranceStyle.fadeUp), EntranceStyle.none);
      expect(snappy.tvEntrance(EntranceStyle.stagger), EntranceStyle.none);
      expect(AppMotion.tvRoutesSharedAxis(TvMotionProfile.snappy), isFalse);
    });

    test('smooth vends base / emphasized / 260ms / shared axis', () {
      expect(smooth.tvFocus, MotionTokens.legacy.base);
      expect(smooth.tvFocus, const Duration(milliseconds: 220));
      expect(smooth.tvFocusCurve, MotionTokens.legacy.emphasized);
      expect(smooth.focusCurve(true, Curves.linear), Curves.easeOutBack);
      expect(smooth.tvScroll, const Duration(milliseconds: 260));
      expect(smooth.tvScrollCurve, MotionTokens.legacy.standard);
      expect(
        smooth.scrollTempo(
          true,
          const Duration(milliseconds: 280),
          tvSnappy: const Duration(milliseconds: 140),
        ),
        const Duration(milliseconds: 260),
      );
      expect(smooth.tvEntrance(EntranceStyle.fadeUp), EntranceStyle.fadeUp);
      expect(smooth.tvEntrance(EntranceStyle.stagger), EntranceStyle.stagger);
      expect(AppMotion.tvRoutesSharedAxis(TvMotionProfile.smooth), isTrue);
    });

    test('off TV both profiles vend the pointer figures', () {
      for (final m in [snappy, smooth]) {
        expect(m.focusTempo(false, const Duration(milliseconds: 170)),
            const Duration(milliseconds: 170));
        expect(m.focusCurve(false, Curves.linear), Curves.linear);
        expect(m.scrollTempo(false, const Duration(milliseconds: 280)),
            const Duration(milliseconds: 280));
        expect(m.entrance(false), MotionTokens.legacy.entrance);
      }
    });

    test('the entrance read: profile on TV, token off it', () {
      final fadeUp = MotionTokens.legacy.copyWith(entrance: EntranceStyle.fadeUp);
      const s = AppMotion(MotionTokens.legacy, reduced: false);
      expect(
        AppMotion(fadeUp, reduced: false).entrance(true),
        EntranceStyle.none,
        reason: 'snappy: no full-screen reveal on the weak box',
      );
      expect(
        AppMotion(fadeUp, reduced: false, profile: TvMotionProfile.smooth)
            .entrance(true),
        EntranceStyle.fadeUp,
      );
      expect(AppMotion(fadeUp, reduced: false).entrance(false),
          EntranceStyle.fadeUp);
      expect(s.entrance(false), EntranceStyle.none, reason: 'legacy token');
    });

    test('the theme tempo reaches the smooth beat', () {
      final sepia = AppTheme.fromDetail(DetailThemes.byId('sepia')).motion;
      expect(sepia.scale, 1.15);
      expect(
        AppMotion(sepia, reduced: false, profile: TvMotionProfile.smooth)
            .tvFocus,
        const Duration(milliseconds: 253),
      );
    });

    test('reduced motion is zero and none in both profiles', () {
      for (final profile in TvMotionProfile.values) {
        final fadeUp =
            MotionTokens.legacy.copyWith(entrance: EntranceStyle.fadeUp);
        final m = AppMotion(fadeUp, reduced: true, profile: profile);
        expect(m.tvFocus, Duration.zero, reason: profile.name);
        expect(m.tvScroll, Duration.zero, reason: profile.name);
        expect(
          m.scrollTempo(
            true,
            const Duration(milliseconds: 280),
            tvSnappy: const Duration(milliseconds: 140),
          ),
          Duration.zero,
          reason: profile.name,
        );
        expect(m.focusTempo(true, const Duration(milliseconds: 170)),
            Duration.zero);
        expect(m.entrance(true), EntranceStyle.none, reason: profile.name);
        expect(m.entrance(false), EntranceStyle.none,
            reason: '${profile.name}: everywhere');
      }
    });
  });

  group('AppMotion.of', () {
    Widget host(Widget child, {TvMotionProfile? scoped}) {
      Widget body = AppThemeScope(theme: AppThemes.legacy, child: child);
      if (scoped != null) body = TvMotionScope(profile: scoped, child: body);
      return MaterialApp(home: body);
    }

    testWidgets('reads the scope', (tester) async {
      late AppMotion seen;
      await tester.pumpWidget(
        host(
          Builder(builder: (context) {
            seen = AppMotion.of(context);
            return const SizedBox();
          }),
          scoped: TvMotionProfile.smooth,
        ),
      );
      expect(seen.profile, TvMotionProfile.smooth);
      expect(seen.tvFocus, const Duration(milliseconds: 220));
    });

    testWidgets('falls back to the controller outside the scope', (
      tester,
    ) async {
      late AppMotion seen;
      TvMotionController.notifier.value = TvMotionProfile.smooth;
      await tester.pumpWidget(
        host(
          Builder(builder: (context) {
            seen = AppMotion.of(context);
            return const SizedBox();
          }),
        ),
      );
      expect(seen.profile, TvMotionProfile.smooth);
    });

    testWidgets('a scope change rebuilds the dependents', (tester) async {
      final builds = <TvMotionProfile>[];
      final profile = ValueNotifier(TvMotionProfile.snappy);
      addTearDown(profile.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<TvMotionProfile>(
            valueListenable: profile,
            child: AppThemeScope(
              theme: AppThemes.legacy,
              child: Builder(builder: (context) {
                builds.add(AppMotion.of(context).profile);
                return const SizedBox();
              }),
            ),
            builder: (_, p, child) => TvMotionScope(profile: p, child: child!),
          ),
        ),
      );
      expect(builds, [TvMotionProfile.snappy]);
      profile.value = TvMotionProfile.smooth;
      await tester.pump();
      expect(builds, [TvMotionProfile.snappy, TvMotionProfile.smooth]);
    });
  });
}
