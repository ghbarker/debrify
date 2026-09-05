import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Real public repair origin: 15668da253d802b89489e40b4aceb36cfd0fbd5b.
// This is not export/restore fixture proof or a copied repair implementation.
const _playback = 'playback_state_v1';
const _finished = 'finished_movies_v1';
const _cw = 'continue_watching_v1';
const _migration = 'playback_completion_migration_generation';
const _purge = 'resume_ghost_purge_generation';

class _ObservedPreferences extends InMemorySharedPreferencesStore {
  _ObservedPreferences(super.data, this.events) : super.withData();
  final List<String> events;
  String? holdKey;
  String? failKey;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    events.add('write:$key');
    if (key == failKey) throw StateError('synthetic preference write failure');
    final result = await super.setValue(valueType, key, value);
    if (key == holdKey) {
      entered.complete();
      await release.future;
    }
    return result;
  }
}

Map<String, Object> _movieValues() => {
  'movie_completion_threshold': 90,
  'episode_completion_threshold': 75,
  _playback: jsonEncode({
    'video_done': {
      'type': 'video',
      'imdbId': 'tt-done',
      'title': 'Done',
      'positionMs': 900,
      'durationMs': 1000,
      'updatedAt': 4,
    },
  }),
  _finished: <String>['tt-existing'],
  _cw: jsonEncode([
    {'imdbId': 'tt-done', 'title': 'Done'},
    {'imdbId': 'tt-keep', 'title': 'Keep'},
  ]),
  'repair_sentinel': 'untouched',
};

Map<String, Object> _ghostValues() => {
  _playback: jsonEncode({
    'series': {
      'type': 'series',
      'finishedEpisodes': {
        '1': {'2': false},
      },
      'seasons': {
        '1': {
          '1': {'positionMs': 0, 'durationMs': 100, 'updatedAt': 9},
          '2': {'positionMs': 0, 'durationMs': 100, 'updatedAt': 8},
          '3': {'positionMs': 0, 'durationMs': 1, 'updatedAt': 7},
        },
      },
    },
  }),
  'repair_sentinel': 'untouched',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  final events = <String>[];
  late SharedPreferencesStorePlatform previous;
  late _ObservedPreferences backend;
  late Database db;
  final a = ProfileScope(
    profileId: 'repair-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'repair-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );

  Future<void> install(
    Map<String, Object> values, {
    bool committed = false,
  }) async {
    SharedPreferences.resetStatic();
    backend = _ObservedPreferences({
      if (!committed)
        for (final e in values.entries) 'flutter.${e.key}': e.value,
      if (committed)
        for (final scope in [a, b])
          for (final e in values.entries)
            'flutter.${scope.preferenceKey(e.key)}': e.value,
    }, events);
    SharedPreferencesStorePlatform.instance = backend;
    if (committed) ProfileRuntime.initializeCommitted(a);
    events.clear();
  }

  void onRevision() => events.add('revision');
  setUp(() async {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await install({});
    IptvMediaStore.debugResetMigration();
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
      ),
    );
    DebrifyTvDatabase.debugDatabaseOverride = db;
    StorageService.localCompletionRevision.addListener(onRevision);
  });
  tearDown(() async {
    if (!backend.release.isCompleted) backend.release.complete();
    StorageService.localCompletionRevision.removeListener(onRevision);
    DebrifyTvDatabase.debugDatabaseOverride = null;
    await db.close();
    IptvMediaStore.debugResetMigration();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });

  test(
    'SQLite delete failure preserves retry metadata after finished/CW effects',
    () async {
      await install(_movieValues());
      await StorageService.upsertVideoResume('Done', {
        'positionMs': 900,
        'durationMs': 1000,
      });
      await db.execute(
        "CREATE TRIGGER fail_resume_delete BEFORE DELETE ON video_resume BEGIN SELECT RAISE(ABORT, 'synthetic repair delete failure'); END",
      );
      events.clear();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_playback);
      await expectLater(
        StorageService.migrateExistingPlaybackCompletionThresholds(),
        throwsA(isA<DatabaseException>()),
      );
      expect(events, [
        'write:flutter.$_finished',
        'revision',
        'write:flutter.$_cw',
      ]);
      expect(prefs.getStringList(_finished), ['tt-done', 'tt-existing']);
      expect(jsonDecode(prefs.getString(_cw)!), [
        {'imdbId': 'tt-keep', 'title': 'Keep'},
      ]);
      expect(prefs.getString(_playback), raw);
      expect(prefs.containsKey(_migration), isFalse);
      expect(await StorageService.getVideoResume('Done'), isNotNull);
      await db.execute('DROP TRIGGER fail_resume_delete');
      events.clear();
      await StorageService.migrateExistingPlaybackCompletionThresholds();
      expect(events, [
        'write:flutter.$_finished',
        'revision',
        'write:flutter.$_cw',
        'write:flutter.$_playback',
        'write:flutter.$_migration',
      ]);
      expect(prefs.getString(_playback), '{}');
      expect(prefs.getInt(_migration), 1);
      expect(await StorageService.getVideoResume('Done'), isNull);
      events.clear();
      await StorageService.migrateExistingPlaybackCompletionThresholds();
      expect(events, isEmpty);
      expect(prefs.getString('repair_sentinel'), 'untouched');
    },
  );

  test(
    'failed finished write escapes before revision, CW, playback and marker',
    () async {
      await install(_movieValues());
      backend.failKey = 'flutter.$_finished';
      final persisted = await backend.getAll();
      await expectLater(
        StorageService.migrateExistingPlaybackCompletionThresholds(),
        throwsA(isA<StateError>()),
      );
      expect(events, ['write:flutter.$_finished']);
      expect(await backend.getAll(), persisted);
      // SharedPreferences updates its local cache before platform failure;
      // durable platform state above, not the optimistic cache, is the oracle.
    },
  );

  test(
    'purge writes playback then notifies then marks; false marks/dummy survive',
    () async {
      await install(_ghostValues());
      await StorageService.purgeUnwatchedResumeGhosts();
      expect(events, [
        'write:flutter.$_playback',
        'revision',
        'write:flutter.$_purge',
      ]);
      final prefs = await SharedPreferences.getInstance();
      final seasons =
          (jsonDecode(prefs.getString(_playback)!) as Map)['series']['seasons'];
      expect((seasons['1'] as Map).keys, ['2', '3']);
      expect(prefs.getInt(_purge), 1);
      events.clear();
      await StorageService.purgeUnwatchedResumeGhosts();
      expect(events, isEmpty);
    },
  );

  test(
    'failed purge write prevents notification and generation commit',
    () async {
      await install(_ghostValues());
      backend.failKey = 'flutter.$_playback';
      final persisted = await backend.getAll();
      await expectLater(
        StorageService.purgeUnwatchedResumeGhosts(),
        throwsA(isA<StateError>()),
      );
      expect(events, ['write:flutter.$_playback']);
      expect(await backend.getAll(), persisted);
    },
  );

  test(
    'held purge write keeps captured marker prefs; switch causes stale error',
    () async {
      await install(_ghostValues(), committed: true);
      backend.holdKey = 'flutter.${a.preferenceKey(_playback)}';
      final run = StorageService.purgeUnwatchedResumeGhosts();
      final observed = expectLater(run, throwsA(isA<StateError>()));
      try {
        await backend.entered.future.timeout(const Duration(seconds: 5));
        ProfileRuntime.publish(b);
      } finally {
        backend.release.complete();
      }
      await observed;
      expect(events, [
        'write:flutter.${a.preferenceKey(_playback)}',
        'revision',
      ]);
      final durable = await backend.getAll();
      expect(
        durable['flutter.${b.preferenceKey(_playback)}'],
        _ghostValues()[_playback],
      );
      for (final scope in [a, b]) {
        expect(
          durable.containsKey('flutter.${scope.preferenceKey(_purge)}'),
          isFalse,
        );
        expect(
          durable['flutter.${scope.preferenceKey('repair_sentinel')}'],
          'untouched',
        );
      }
    },
  );

  test(
    'migration reacquires playback writer after held CW, but marker stays captured',
    () async {
      final values = _movieValues();
      final playback = jsonDecode(values[_playback]! as String) as Map;
      // Empty title has no legacy SQLite resume key; this case isolates prefs.
      playback['video_done']['title'] = '';
      values[_playback] = jsonEncode(playback);
      await install(values, committed: true);
      backend.holdKey = 'flutter.${a.preferenceKey(_cw)}';
      final run = StorageService.migrateExistingPlaybackCompletionThresholds();
      final observed = expectLater(run, throwsA(isA<StateError>()));
      try {
        await backend.entered.future.timeout(const Duration(seconds: 5));
        ProfileRuntime.publish(b);
      } finally {
        backend.release.complete();
      }
      await observed;
      expect(events, [
        'write:flutter.${a.preferenceKey(_finished)}',
        'revision',
        'write:flutter.${a.preferenceKey(_cw)}',
        'write:flutter.${b.preferenceKey(_playback)}',
      ]);
      final durable = await backend.getAll();
      expect(
        durable['flutter.${a.preferenceKey(_playback)}'],
        values[_playback],
      );
      expect(durable['flutter.${b.preferenceKey(_playback)}'], '{}');
      expect(
        durable['flutter.${b.preferenceKey(_finished)}'],
        values[_finished],
      );
      expect(durable['flutter.${b.preferenceKey(_cw)}'], values[_cw]);
      for (final scope in [a, b]) {
        expect(
          durable.containsKey('flutter.${scope.preferenceKey(_migration)}'),
          isFalse,
        );
        expect(
          durable['flutter.${scope.preferenceKey('repair_sentinel')}'],
          'untouched',
        );
      }
    },
  );

  for (final marker in [null, 0, 1, 'wrong-type']) {
    test('synchronous rearm honors key presence including marker $marker', () {
      final overlay = <String, Object?>{_playback: '{}', _purge: marker};
      StorageService.rearmGhostPurgeForImportedPlayback(overlay);
      expect(overlay, {_playback: '{}', _purge: marker});
      final missing = <String, Object?>{_playback: null};
      StorageService.rearmGhostPurgeForImportedPlayback(missing);
      expect(missing, {_playback: null, _purge: 0});
      final unrelated = <String, Object?>{'sentinel': 1};
      StorageService.rearmGhostPurgeForImportedPlayback(unrelated);
      expect(unrelated, {'sentinel': 1});
    });
  }

  for (final key in [_migration, _purge]) {
    test('$key wrong physical type throws before mutation', () async {
      await install({..._ghostValues(), key: '1'});
      await expectLater(
        key == _migration
            ? StorageService.migrateExistingPlaybackCompletionThresholds()
            : StorageService.purgeUnwatchedResumeGhosts(),
        throwsA(isA<TypeError>()),
      );
      expect(events, isEmpty);
    });
  }

  test('empty repair writes only its own marker without notifying', () async {
    await StorageService.migrateExistingPlaybackCompletionThresholds();
    await StorageService.purgeUnwatchedResumeGhosts();
    expect(events, ['write:flutter.$_migration', 'write:flutter.$_purge']);
  });
}
