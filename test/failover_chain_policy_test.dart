import 'dart:convert';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FailoverChainPolicy defaults', () {
    test('shipped defaults are disabled and match the reference knobs', () {
      const d = FailoverChainPolicy.defaults;
      expect(d.enabled, isFalse);
      expect(d.providerOrder, FailoverChainPolicy.defaultProviderOrder);
      expect(d.maxSiblings, 3);
      expect(d.maxPerLaterProvider, 3);
      expect(d.resolutionMatch, FailoverResolutionMatch.nearestBelowFirst);
      expect(d.probeEnabled, isTrue);
      expect(d.probeTimeoutSeconds, 5);
      expect(d.neverProbeProviders, {'premiumize', 'pikpak'});
      expect(d.demotionWindowMinutes, 10);
      expect(d.isDefault, isTrue);
    });

    test('the const defaults equal the factory defaults', () {
      expect(FailoverChainPolicy(), FailoverChainPolicy.defaults);
      expect(
        FailoverChainPolicy().hashCode,
        FailoverChainPolicy.defaults.hashCode,
      );
    });

    test(
      'default provider order mirrors CloudProviderId.playbackPrecedence',
      () {
        expect(
          FailoverChainPolicy.defaultProviderOrder,
          CloudProviderId.playbackPrecedence.map((p) => p.playbackId).toList(),
        );
        for (final id in FailoverChainPolicy.defaultNeverProbeProviders) {
          expect(CloudProviderId.fromPlaybackId(id), isNotNull, reason: id);
        }
      },
    );
  });

  group('FailoverChainPolicy clamping and normalization', () {
    test('numeric knobs clamp to their documented ranges', () {
      final p = FailoverChainPolicy(
        maxSiblings: 99,
        maxPerLaterProvider: -4,
        probeTimeoutSeconds: 0,
        demotionWindowMinutes: -1,
      );
      expect(p.maxSiblings, 10);
      expect(p.maxPerLaterProvider, 0);
      expect(p.probeTimeoutSeconds, 1);
      expect(p.demotionWindowMinutes, 0);
      expect(
        FailoverChainPolicy(probeTimeoutSeconds: 500).probeTimeoutSeconds,
        30,
      );
      expect(
        FailoverChainPolicy(
          demotionWindowMinutes: 1 << 20,
        ).demotionWindowMinutes,
        24 * 60,
      );
    });

    test(
      'provider order drops unknowns/duplicates and appends missing ids',
      () {
        final p = FailoverChainPolicy(
          providerOrder: const ['pikpak', 'bogus', 'torbox', 'pikpak'],
        );
        expect(p.providerOrder, [
          'pikpak',
          'torbox',
          'debrid',
          'premiumize',
          'alldebrid',
        ]);
      },
    );

    test('never-probe set drops unknown providers', () {
      final p = FailoverChainPolicy(
        neverProbeProviders: const {'torbox', 'nope'},
      );
      expect(p.neverProbeProviders, {'torbox'});
    });

    test('copyWith changes only the named field', () {
      final p = FailoverChainPolicy.defaults.copyWith(enabled: true);
      expect(p.enabled, isTrue);
      expect(p.copyWith(enabled: false), FailoverChainPolicy.defaults);
      expect(p.isDefault, isFalse);
    });
  });

  group('FailoverChainPolicy JSON', () {
    test('round-trips every field', () {
      final p = FailoverChainPolicy(
        enabled: true,
        providerOrder: const [
          'torbox',
          'debrid',
          'alldebrid',
          'premiumize',
          'pikpak',
        ],
        maxSiblings: 5,
        maxPerLaterProvider: 1,
        resolutionMatch: FailoverResolutionMatch.exactOnly,
        probeEnabled: false,
        probeTimeoutSeconds: 12,
        neverProbeProviders: const {'debrid'},
        demotionWindowMinutes: 0,
      );
      final decoded = FailoverChainPolicy.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, p);
      expect(decoded.hashCode, p.hashCode);
    });

    test('null / empty / malformed JSON decodes to defaults per field', () {
      expect(FailoverChainPolicy.fromJson(null), FailoverChainPolicy.defaults);
      expect(FailoverChainPolicy.fromJson({}), FailoverChainPolicy.defaults);
      final p = FailoverChainPolicy.fromJson({
        'enabled': 'yes',
        'maxSiblings': 'many',
        'resolutionMatch': 'fuzzy',
        'providerOrder': 42,
        'neverProbeProviders': [1, 2],
        'probeTimeoutSeconds': 7,
      });
      expect(p.enabled, isFalse);
      expect(p.maxSiblings, 3);
      expect(p.resolutionMatch, FailoverResolutionMatch.nearestBelowFirst);
      expect(p.providerOrder, FailoverChainPolicy.defaultProviderOrder);
      expect(p.neverProbeProviders, isEmpty);
      expect(p.probeTimeoutSeconds, 7);
    });

    test('out-of-range JSON values clamp on decode', () {
      final p = FailoverChainPolicy.fromJson({
        'maxSiblings': 50,
        'probeTimeoutSeconds': 0,
      });
      expect(p.maxSiblings, 10);
      expect(p.probeTimeoutSeconds, 1);
    });
  });

  group('QuickPlayRules integration', () {
    test('default rules carry the default policy and omit it from JSON', () {
      final rules = QuickPlayRules.debrifyDefault(isMovie: true);
      expect(rules.failoverChain, FailoverChainPolicy.defaults);
      expect(rules.toJson().containsKey('failoverChain'), isFalse);
    });

    test('a profile saved before the field existed decodes to defaults', () {
      final json = QuickPlayRules.debrifyDefault(isMovie: false).toJson()
        ..remove('failoverChain');
      final rules = QuickPlayRules.fromJson(json, isMovie: false);
      expect(rules.failoverChain, FailoverChainPolicy.defaults);
      expect(rules.matchesDebrifyDefault(isMovie: false), isTrue);
    });

    test('a customized policy round-trips through the rules JSON', () {
      final policy = FailoverChainPolicy.defaults.copyWith(
        enabled: true,
        maxSiblings: 2,
      );
      final rules = QuickPlayRules.debrifyDefault(
        isMovie: true,
      ).copyWith(preset: QuickPlayPreset.custom, failoverChain: policy);
      final json =
          jsonDecode(jsonEncode(rules.toJson())) as Map<String, dynamic>;
      expect(json['failoverChain'], isA<Map>());
      final decoded = QuickPlayRules.fromJson(json, isMovie: true);
      expect(decoded.failoverChain, policy);
      expect(decoded, rules);
      // The policy participates in equality: same rules, different chain.
      expect(
        decoded == rules.copyWith(failoverChain: FailoverChainPolicy.defaults),
        isFalse,
      );
    });

    test('persists per tab through QuickPlayPolicyPrefs', () async {
      SharedPreferences.setMockInitialValues({});
      final policy = FailoverChainPolicy.defaults.copyWith(
        enabled: true,
        providerOrder: const ['torbox', 'debrid'],
        probeEnabled: false,
      );
      await QuickPlayPolicyPrefs.setQuickPlayRules(
        QuickPlayRules.debrifyDefault(
          isMovie: true,
        ).copyWith(preset: QuickPlayPreset.custom, failoverChain: policy),
        isMovie: true,
      );
      final movie = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: true);
      expect(movie.failoverChain, policy);
      expect(movie.failoverChain.providerOrder.take(2), ['torbox', 'debrid']);
      // Series tab untouched — still the disabled default.
      final show = await QuickPlayPolicyPrefs.getQuickPlayRules(isMovie: false);
      expect(show.failoverChain, FailoverChainPolicy.defaults);

      // Restore defaults clears it.
      await QuickPlayPolicyPrefs.restoreQuickPlayDefaults();
      final restored = await QuickPlayPolicyPrefs.getQuickPlayRules(
        isMovie: true,
      );
      expect(restored.failoverChain, FailoverChainPolicy.defaults);
    });
  });
}
