import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/screens/settings/quick_play_settings_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: const QuickPlaySettingsPage(),
        ),
      ),
    );
    // _load awaits several independent preference/service reads. Pump their
    // microtask turns even when no frame has been scheduled yet.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows tabs, the torrent switch, and the priority section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Prefer torrents'), findsOneWidget);
    expect(find.text('Addon priority'), findsOneWidget);
    // Movies tab never shows the packs switch.
    expect(find.text('Prefer season packs'), findsNothing);
    // The old preset cards are gone.
    expect(find.text('Debrify default'), findsNothing);
    expect(find.text('Follow addon order'), findsNothing);
  });

  testWidgets('series tab adds the season packs switch, default on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('Prefer season packs'), findsOneWidget);

    final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    expect(rules.preferSeriesPacks, isTrue);
  });

  testWidgets('prefer torrents off persists the addon-first source mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    await tester.tap(find.text('Prefer torrents'));
    await tester.pumpAndSettle();

    final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
    expect(movie.sourceMode, QuickPlaySourceMode.addonsThenTorrents);
    // Series tab untouched.
    final show = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    expect(show.sourceMode, QuickPlaySourceMode.torrentsThenAddons);

    // Toggling back restores the exact shipped default (not a custom copy).
    await tester.tap(find.text('Prefer torrents'));
    await tester.pumpAndSettle();
    final restored = await QuickPlayPolicyPrefs.getQuickPlayRules(
      isMovie: true,
    );
    expect(restored.matchesDebrifyDefault(isMovie: true), isTrue);
  });

  testWidgets('series pack switch off persists and clears exact-only trap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // A legacy profile stuck on exactEpisodeOnly must not defeat the switch.
    await QuickPlayPolicyPrefs.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: false).copyWith(
        preset: QuickPlayPreset.custom,
        preferSeriesPacks: false,
        packPreference: QuickPlayPackPreference.exactEpisodeOnly,
      ),
      isMovie: false,
    );
    await pumpPage(tester);

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prefer season packs'));
    await tester.pumpAndSettle();

    final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    expect(rules.preferSeriesPacks, isTrue);
    expect(
      rules.packPreference,
      isNot(QuickPlayPackPreference.exactEpisodeOnly),
    );
  });

  testWidgets('legacy advanced knobs are gone from the UI but still load', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await QuickPlayPolicyPrefs.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        preset: QuickPlayPreset.custom,
        maxAttempts: 2,
        ranking: QuickPlayRanking.smallest,
      ),
      isMovie: true,
    );
    await pumpPage(tester);

    // No advanced section, no ranking control anywhere. ("Streams to try" is
    // editable again, but it is a plain rule row, not the old advanced card.)
    expect(find.text('Advanced control'), findsNothing);
    expect(find.textContaining('Try up to'), findsNothing);

    // The stored customization survives an unrelated edit untouched.
    await tester.tap(find.text('Prefer torrents'));
    await tester.pumpAndSettle();
    final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
    expect(rules.maxAttempts, 2);
    expect(rules.ranking, QuickPlayRanking.smallest);
    expect(rules.sourceMode, QuickPlaySourceMode.addonsThenTorrents);
  });

  testWidgets('streams to try shows the stored count and persists a change', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // A device carrying the OLD slider's pref: the page must show 10, not the
    // 5 default — this is the desktop-vs-Apple-TV mismatch users reported.
    await QuickPlayPolicyPrefs.setQuickPlayMaxRetries(10);
    await pumpPage(tester);

    expect(find.text('Streams to try'), findsOneWidget);
    expect(find.text('10 streams'), findsWidgets);

    await tester.ensureVisible(find.text('10 streams').first);
    await tester.tap(find.text('10 streams').first);
    await tester.pumpAndSettle();
    // The closed field echoes the selection too, so take the menu entry.
    await tester.tap(find.text('3 streams').last);
    await tester.pumpAndSettle();

    final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
    expect(movie.maxAttempts, 3);
    expect(movie.tryNextOnFailure, isTrue);
    // Per-content: the Series tab keeps its own count.
    final show = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
    expect(show.maxAttempts, 10);
  });

  testWidgets('picking 1 stream disarms failover', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    await tester.ensureVisible(find.text('5 streams (default)').first);
    await tester.tap(find.text('5 streams (default)').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 stream').last);
    await tester.pumpAndSettle();

    final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
    expect(movie.maxAttempts, 1);
    // The players compute `tryNext ? maxAttempts : 1` — both fields must agree
    // or a later "back to 5" would silently stay at one attempt.
    expect(movie.tryNextOnFailure, isFalse);
  });

  testWidgets('restore defaults resets both tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await QuickPlayPolicyPrefs.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
        preset: QuickPlayPreset.custom,
        sourceMode: QuickPlaySourceMode.addonsThenTorrents,
        sourcePriority: const ['engine:a', 'stremio:b'],
      ),
      isMovie: true,
    );
    await pumpPage(tester);

    // The global "Play button opens" selector sits above the tabs, so the reset
    // row no longer fits the default 800x600 test surface.
    await tester.ensureVisible(find.text('Restore defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore defaults'));
    await tester.pumpAndSettle();

    final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
    expect(movie.matchesDebrifyDefault(isMovie: true), isTrue);
    expect(movie.sourcePriority, isEmpty);
  });

  group('failover chain section', () {
    testWidgets('collapsed by default: switch visible, knobs hidden', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await pumpPage(tester);

      expect(find.text('Failover chain'), findsOneWidget);
      expect(find.text('Use failover chain'), findsOneWidget);
      expect(find.text('Provider order'), findsNothing);
      expect(find.text('Probe before playing'), findsNothing);
      expect(find.text('Demote recently served links'), findsNothing);
    });

    testWidgets('switching it on persists and reveals every knob', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await pumpPage(tester);

      await tester.ensureVisible(find.text('Use failover chain'));
      await tester.tap(find.text('Use failover chain'));
      await tester.pumpAndSettle();

      final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(movie.failoverChain.enabled, isTrue);
      expect(movie.preset, QuickPlayPreset.custom);
      // Per tab: series stays on the shipped default.
      final show = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
      expect(show.failoverChain, FailoverChainPolicy.defaults);

      for (final label in [
        'Provider order',
        'Same-service streams',
        'Streams per later service',
        'Resolution match',
        'Liveness probe',
        'Probe before playing',
        'Never probe Premiumize',
        'Never probe PikPak',
        'Demote recently served links',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Provider order rows in shipped precedence, tagged as debrid services.
      expect(find.text('Real-Debrid'), findsOneWidget);
      expect(find.text('TorBox'), findsOneWidget);
      expect(find.text('Debrid service'), findsNWidgets(5));
      // Defaults echoed by the selects.
      expect(find.text('3 streams (default)'), findsNWidgets(2));
      expect(find.text('Nearest resolution (default)'), findsOneWidget);
      expect(find.text('Probe timeout: 5 seconds (default)'), findsOneWidget);
      expect(find.text('10 minutes (default)'), findsOneWidget);
    });

    testWidgets('caps, match, probe and demotion knobs persist', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await QuickPlayPolicyPrefs.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
          preset: QuickPlayPreset.custom,
          failoverChain: FailoverChainPolicy.defaults.copyWith(enabled: true),
        ),
        isMovie: true,
      );
      await pumpPage(tester);

      // The eleven-row count menus open partly off the 800x600 test surface,
      // so drive the selects through their onChanged (the same path a menu
      // pick takes) and keep real taps for the switches.
      SettingsSelectDropdown select(String label) =>
          tester.widget<SettingsSelectDropdown>(
            find.byWidgetPredicate(
              (w) =>
                  w is SettingsSelectDropdown &&
                  w.focusNode?.debugLabel == label,
            ),
          );

      select('quick-play-chain-siblings').onChanged('1');
      await tester.pumpAndSettle();
      var rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(rules.failoverChain.maxSiblings, 1);
      expect(rules.failoverChain.maxPerLaterProvider, 3);
      expect(find.text('1 stream'), findsOneWidget);

      select('quick-play-chain-later').onChanged('0');
      await tester.pumpAndSettle();
      rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(rules.failoverChain.maxPerLaterProvider, 0);
      expect(find.text('None'), findsOneWidget);

      select('quick-play-chain-match').onChanged('exactOnly');
      await tester.pumpAndSettle();
      rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(
        rules.failoverChain.resolutionMatch,
        FailoverResolutionMatch.exactOnly,
      );
      expect(find.text('Same resolution only'), findsOneWidget);

      select('quick-play-chain-probe-timeout').onChanged('15');
      await tester.pumpAndSettle();
      rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(rules.failoverChain.probeTimeoutSeconds, 15);

      select('quick-play-chain-demotion').onChanged('0');
      await tester.pumpAndSettle();
      rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(rules.failoverChain.demotionWindowMinutes, 0);
      expect(find.text('Off'), findsOneWidget);

      // Never-probe: Premiumize off, TorBox on (real taps).
      await tester.ensureVisible(find.text('Never probe Premiumize'));
      await tester.tap(find.text('Never probe Premiumize'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Never probe TorBox'));
      await tester.tap(find.text('Never probe TorBox'));
      await tester.pumpAndSettle();
      rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(rules.failoverChain.neverProbeProviders, {'pikpak', 'torbox'});

      // Probe off hides the timeout and never-probe rows.
      await tester.ensureVisible(find.text('Probe before playing'));
      await tester.tap(find.text('Probe before playing'));
      await tester.pumpAndSettle();
      rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(rules.failoverChain.probeEnabled, isFalse);
      expect(find.text('Never probe PikPak'), findsNothing);
      expect(find.textContaining('Probe timeout'), findsNothing);

      // Everything above stayed on the Movies tab.
      final show = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
      expect(show.failoverChain, FailoverChainPolicy.defaults);
    });

    testWidgets('arrows reorder the provider list and persist it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await QuickPlayPolicyPrefs.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
          preset: QuickPlayPreset.custom,
          failoverChain: FailoverChainPolicy.defaults.copyWith(enabled: true),
        ),
        isMovie: true,
      );
      await pumpPage(tester);

      final pikpakRow = find.byKey(
        const ValueKey('quick-play-chain-provider-pikpak'),
      );
      await tester.ensureVisible(pikpakRow);
      await tester.tap(
        find.descendant(of: pikpakRow, matching: find.byTooltip('Move up')),
      );
      await tester.pumpAndSettle();

      final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(rules.failoverChain.providerOrder, [
        'debrid',
        'torbox',
        'premiumize',
        'pikpak',
        'alldebrid',
      ]);
    });

    testWidgets('restore defaults switches the chain back off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await QuickPlayPolicyPrefs.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(isMovie: true).copyWith(
          preset: QuickPlayPreset.custom,
          failoverChain: FailoverChainPolicy.defaults.copyWith(
            enabled: true,
            maxSiblings: 7,
          ),
        ),
        isMovie: true,
      );
      await pumpPage(tester);
      expect(find.text('Provider order'), findsOneWidget);

      await tester.ensureVisible(find.text('Restore defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore defaults'));
      await tester.pumpAndSettle();

      final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(movie.failoverChain, FailoverChainPolicy.defaults);
      expect(find.text('Provider order'), findsNothing);
    });
  });
}
