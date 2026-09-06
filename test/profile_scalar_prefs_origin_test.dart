import 'package:debrify/services/storage/quick_play_policy_prefs.dart';
import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Actual public origin 033fea6961a8a8249bc6a450700b956b3cb4347b.
// Transport controls only; no copied policy, new production hooks or native proof.
const _limit = Duration(seconds: 5);

class _Entry {
  const _Entry(this.key, this.initial, this.next, this.read, this.write);
  final String key;
  final Object initial;
  final Object next;
  final Future<Object> Function() read;
  final Future<void> Function(Object) write;
}

final _entries = <_Entry>[
  _Entry(
    'series_browser_dense_view',
    false,
    true,
    StorageService.getSeriesBrowserDenseView,
    (v) => StorageService.setSeriesBrowserDenseView(v as bool),
  ),
  _Entry(
    'merged_series_page_enabled',
    true,
    false,
    StorageService.getMergedSeriesPageEnabled,
    (v) => StorageService.setMergedSeriesPageEnabled(v as bool),
  ),
  _Entry(
    'stremio_addon_hub_enabled',
    true,
    false,
    StorageService.getStremioAddonHubEnabled,
    (v) => StorageService.setStremioAddonHubEnabled(v as bool),
  ),
  _Entry(
    'detail_trailer_autoplay_enabled',
    true,
    false,
    StorageService.getDetailTrailerAutoplayEnabled,
    (v) => StorageService.setDetailTrailerAutoplayEnabled(v as bool),
  ),
  _Entry(
    'series_auto_pin_on_play',
    true,
    false,
    QuickPlayPolicyPrefs.getSeriesAutoPinOnPlay,
    (v) => QuickPlayPolicyPrefs.setSeriesAutoPinOnPlay(v as bool),
  ),
  _Entry(
    'quick_play_search_timeout',
    5,
    -7,
    QuickPlayPolicyPrefs.getQuickPlaySearchTimeout,
    (v) => QuickPlayPolicyPrefs.setQuickPlaySearchTimeout(v as int),
  ),
  _Entry(
    'stremio_sources_timeout',
    15,
    -9,
    QuickPlayPolicyPrefs.getStremioSourcesTimeout,
    (v) => QuickPlayPolicyPrefs.setStremioSourcesTimeout(v as int),
  ),
];

class _Backend extends InMemorySharedPreferencesStore {
  _Backend(super.data) : super.withData();
  final writes = <(String, Object)>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic scalar write failure');
  String? heldKey;
  bool holdRead = false;
  String outcome = 'ok';
  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    if (holdRead) {
      entered.complete();
      await release.future.timeout(_limit);
    }
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add((key, value));
    if (key == heldKey) {
      entered.complete();
      await release.future.timeout(_limit);
      if (outcome == 'false') return false;
      if (outcome == 'throw') throw failure;
    }
    return super.setValue(type, key, value);
  }

  Future<Map<String, Object>> durable() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Backend backend;
  final a = ProfileScope(
    profileId: 'scalar-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'scalar-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  final generation = ProfileScope(
    profileId: 'scalar-a',
    dataGeneration: 7,
    sessionEpoch: 3,
  );
  void install(Map<String, Object> data) {
    SharedPreferences.resetStatic();
    backend = _Backend({
      for (final e in data.entries) 'flutter.${e.key}': e.value,
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  void profiles(_Entry entry) {
    install({
      entry.key: 'legacy sentinel',
      a.preferenceKey(entry.key): entry.initial,
      b.preferenceKey(entry.key): entry.next,
      generation.preferenceKey(entry.key): entry.initial,
      'scalar_unrelated': 'untouched',
    });
    ProfileRuntime.initializeCommitted(a);
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install({});
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });
  for (final entry in _entries) {
    test('${entry.key}: absent default does not write', () async {
      expect(await entry.read(), entry.initial);
      expect(backend.writes, isEmpty);
      expect(await backend.durable(), isEmpty);
    });
    test('${entry.key}: wrong physical type escapes without rewrite', () async {
      install({entry.key: 'wrong type'});
      await expectLater(entry.read(), throwsA(isA<TypeError>()));
      expect(backend.writes, isEmpty);
      expect((await backend.durable())['flutter.${entry.key}'], 'wrong type');
    });
    for (final outcome in ['ok', 'false', 'throw']) {
      test(
        '${entry.key}: held $outcome retains captured destination after switch',
        () async {
          profiles(entry);
          final physical = a.preferenceKey(entry.key);
          backend.heldKey = 'flutter.$physical';
          backend.outcome = outcome;
          final pending = entry.write(entry.next);
          final observed = outcome == 'throw'
              ? expectLater(pending, throwsA(same(backend.failure)))
              : expectLater(pending, completes);
          await backend.entered.future.timeout(_limit);
          final sdk = await SharedPreferences.getInstance();
          expect(sdk.get(physical), entry.next);
          expect((await backend.durable())['flutter.$physical'], entry.initial);
          ProfileRuntime.publish(b);
          backend.release.complete();
          await observed;
          expect(backend.writes, [('flutter.$physical', entry.next)]);
          final data = await backend.durable();
          expect(
            data['flutter.$physical'],
            outcome == 'ok' ? entry.next : entry.initial,
          );
          expect(sdk.get(physical), entry.next);
          expect(await entry.read(), entry.next);
          expect(data['flutter.${b.preferenceKey(entry.key)}'], entry.next);
          expect(
            data['flutter.${generation.preferenceKey(entry.key)}'],
            entry.initial,
          );
          expect(data['flutter.${entry.key}'], 'legacy sentinel');
          expect(data['flutter.scalar_unrelated'], 'untouched');
        },
      );
    }
    for (final writing in [false, true]) {
      test(
        '${entry.key}: capture follows held SDK acquisition writing=$writing',
        () async {
          profiles(entry);
          backend.holdRead = true;
          final Future<Object?> pending = writing
              ? entry.write(entry.initial).then<Object?>((_) => null)
              : entry.read();
          await backend.entered.future.timeout(_limit);
          ProfileRuntime.publish(b);
          backend.release.complete();
          expect(await pending, writing ? null : entry.next);
          expect(
            backend.writes,
            writing
                ? [('flutter.${b.preferenceKey(entry.key)}', entry.initial)]
                : isEmpty,
          );
          final data = await backend.durable();
          expect(data['flutter.${a.preferenceKey(entry.key)}'], entry.initial);
          expect(
            data['flutter.${b.preferenceKey(entry.key)}'],
            writing ? entry.initial : entry.next,
          );
          expect(
            data['flutter.${generation.preferenceKey(entry.key)}'],
            entry.initial,
          );
          expect(data['flutter.${entry.key}'], 'legacy sentinel');
        },
      );
    }
    if (entry.initial is int) {
      for (final raw in [0, -2147483648, 2147483647]) {
        test(
          '${entry.key}: raw integer $raw is neither clamped nor rewritten',
          () async {
            install({entry.key: raw});
            expect(await entry.read(), raw);
            expect(backend.writes, isEmpty);
            await entry.write(raw);
            expect(await entry.read(), raw);
            expect(backend.writes, [('flutter.${entry.key}', raw)]);
            expect((await backend.durable())['flutter.${entry.key}'], raw);
          },
        );
      }
    }
  }
}
