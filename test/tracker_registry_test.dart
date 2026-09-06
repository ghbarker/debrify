import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/simkl/simkl_list_source.dart';
import 'package:debrify/services/storage/tracking_prefs.dart';
import 'package:debrify/services/tracking/tracker_registry.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_item_transformer.dart';
import 'package:debrify/services/trakt/trakt_list_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(TrackerRegistry.debugReset);

  test('production order is local, trakt, simkl, mdblist', () {
    expect(
      TrackerRegistry.instance.all.map((s) => s.source).toList(),
      TrackingSource.values,
    );
  });

  test('local is not a dedicated progress source', () {
    expect(
      TrackerRegistry.instance.dedicatedProgress(WatchProgressSource.smart),
      isNull,
    );
    expect(
      TrackerRegistry.instance.dedicatedProgress(WatchProgressSource.local),
      isNull,
    );
    expect(
      TrackerRegistry.instance
          .dedicatedProgress(WatchProgressSource.trakt)
          ?.source,
      TrackingSource.trakt,
    );
    expect(
      TrackerRegistry.instance
          .dedicatedProgress(WatchProgressSource.simkl)
          ?.source,
      TrackingSource.simkl,
    );
    expect(
      TrackerRegistry.instance
          .dedicatedProgress(WatchProgressSource.mdblist)
          ?.source,
      TrackingSource.mdblist,
    );
  });

  test('remote hasCredential tear-offs are the StorageService methods', () {
    expect(
      TrackerRegistry.instance.of(TrackingSource.trakt)!.hasCredential,
      TrackingPrefs.hasTraktCredential,
    );
    expect(
      TrackerRegistry.instance.of(TrackingSource.simkl)!.hasCredential,
      TrackingPrefs.hasSimklCredential,
    );
    expect(
      TrackerRegistry.instance.of(TrackingSource.mdblist)!.hasCredential,
      TrackingPrefs.hasMdblistCredential,
    );
  });

  test('each remote registers list, calendar, CW, transformer', () {
    for (final source in const [
      TrackingSource.trakt,
      TrackingSource.simkl,
      TrackingSource.mdblist,
    ]) {
      final spec = TrackerRegistry.instance.of(source)!;
      expect(spec.listSource, isNotNull, reason: '$source listSource');
      expect(spec.calendar, isNotNull, reason: '$source calendar');
      expect(spec.continueWatching, isNotNull, reason: '$source CW');
      expect(spec.transformer, isNotNull, reason: '$source transformer');
    }
    final local = TrackerRegistry.instance.of(TrackingSource.local)!;
    expect(local.listSource, isNull);
    expect(local.calendar, isNull);
    expect(local.hasCredential, isNotNull);
  });

  test('registering a fake spec is enough for lookup', () {
    final fake = TrackerSpec(
      source: TrackingSource.trakt,
      progressSource: WatchProgressSource.trakt,
      label: 'FakeTrakt',
      hasCredential: () async => true,
    );
    final registry = TrackerRegistry([fake]);
    expect(registry.of(TrackingSource.trakt)?.label, 'FakeTrakt');
    expect(registry.all, [fake]);
    expect(registry.remotes.single.label, 'FakeTrakt');
  });

  test('transformer adapters match family statics', () {
    final raw = {
      'type': 'show',
      'show': {
        'title': 'Severance',
        'ids': {'imdb': 'tt11280740'},
      },
    };
    final viaAdapter = TrackerRegistry.instance
        .of(TrackingSource.trakt)!
        .transformer!
        .transformItem(raw);
    final viaStatic = TraktItemTransformer.transformItem(raw);
    expect(viaAdapter!.id, viaStatic!.id);
    expect(viaAdapter.type, viaStatic.type);
    expect(viaAdapter.name, viaStatic.name);
  });

  test(
    'listSource.loadPage Continue Watching matches family loadList',
    () async {
      final cw = [StremioMeta(id: 'tt1', type: 'movie', name: 'Cached')];
      final viaRegistry = await TrackerRegistry.instance
          .of(TrackingSource.trakt)!
          .listSource!
          .loadPage(
            const TraktListChoice.builtin(TraktSeeAllList.continueWatching),
            cwItems: cw,
          );
      expect(viaRegistry.failed, isFalse);
      expect(viaRegistry.items, cw);

      final viaSimkl = await TrackerRegistry.instance
          .of(TrackingSource.simkl)!
          .listSource!
          .loadPage(SimklSeeAllList.continueWatching);
      expect(viaSimkl.failed, isFalse);
      expect(viaSimkl.items, isEmpty);
    },
  );

  test('policy progressFrom still iterates the registry table', () {
    const policy = TrackingSourcePolicy(
      scrobbleTargets: {},
      progressSource: WatchProgressSource.mdblist,
      homeTickSources: {},
    );
    expect(policy.progressFrom(TrackingSource.mdblist), isTrue);
    expect(policy.progressFrom(TrackingSource.trakt), isFalse);
    expect(policy.progressFrom(TrackingSource.local), isFalse);
  });
}
