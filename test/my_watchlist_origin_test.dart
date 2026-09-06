import 'package:debrify/services/storage/my_watchlist_store.dart';
import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Actual public API origin b1d075dd3e28107438075402500b6c6468c73fd0.
// Current-origin proof only: no assumption that pre-S2 cap/identity code matches.
const _key = 'my_watchlist_v1';

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences(super.data) : super.withData();
  final entered = Completer<void>();
  final release = Completer<void>();
  final writes = <String>[];
  bool holdRead = false;
  bool failRead = false;
  bool failWrite = false;
  bool failRemove = false;

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    if (holdRead) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    if (failRead) throw StateError('synthetic read failure');
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add('set:$key');
    if (failWrite) throw StateError('synthetic write failure');
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    writes.add('remove:$key');
    if (failRemove) throw StateError('synthetic remove failure');
    return super.remove(key);
  }

  Future<void> replaceWhileHeld(String value) async {
    await super.setValue('String', 'flutter.$_key', value);
  }

  Future<Map<String, Object>> snapshot() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );

  Future<Object?> durable() async => (await snapshot())['flutter.$_key'];
}

StremioMeta _item(
  String id, {
  String? imdb,
  String name = 'Same',
  String? addon,
}) => StremioMeta(
  id: id,
  imdbId: imdb,
  type: 'movie',
  name: name,
  sourceAddon: addon == null
      ? null
      : StremioAddon(
          id: addon,
          name: addon,
          manifestUrl: 'https://example.invalid/manifest.json',
          baseUrl: 'https://example.invalid',
        ),
);

Map<String, Object?> _row(
  StremioMeta item, {
  Object? addedAt = 1,
  String key = 'legacy',
}) => {'key': key, 'addedAt': addedAt, 'item': item.toJson()};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late bool? priorOverride;
  late _Preferences backend;
  void install(Object? raw) {
    SharedPreferences.resetStatic();
    backend = _Preferences({
      if (raw != null) 'flutter.$_key': raw,
      'flutter.watchlist_sentinel': 'untouched',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    priorOverride = StorageService.debugMyWatchlistTvOsCapOverride;
    StorageService.debugMyWatchlistTvOsCapOverride = false;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install(null);
  });
  tearDown(() async {
    if (!backend.release.isCompleted) backend.release.complete();
    try {
      expect(
        (await backend.snapshot())['flutter.watchlist_sentinel'],
        'untouched',
      );
    } finally {
      StorageService.debugMyWatchlistTvOsCapOverride = priorOverride;
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
      ProfileRuntime.debugReset();
    }
  });

  test(
    'held initial read sees released backend contents, not invocation-time contents',
    () async {
      install(jsonEncode([_row(_item('old'))]));
      backend.holdRead = true;
      var completed = false;
      final pending = MyWatchlistStore.getMyWatchlistItems().then((value) {
        completed = true;
        return value;
      });
      await backend.entered.future;
      try {
        expect(completed, isFalse);
        expect(backend.writes, isEmpty);
        await backend.replaceWhileHeld(jsonEncode([_row(_item('released'))]));
      } finally {
        backend.release.complete();
      }
      expect((await pending).map((e) => e.id), ['released']);
      expect(backend.writes, isEmpty);
    },
  );

  for (final enabledAtRelease in [true, false]) {
    test(
      'cap override is read after held preference read: $enabledAtRelease',
      () async {
        final huge = _item(
          'old',
          name: 'x' * StorageService.myWatchlistTvOsCapBytes,
        );
        install(jsonEncode([_row(huge)]));
        backend.holdRead = true;
        StorageService.debugMyWatchlistTvOsCapOverride = !enabledAtRelease;
        final pending = MyWatchlistStore.setMyWatchlistItem(_item('new'), true);
        await backend.entered.future;
        try {
          expect(backend.writes, isEmpty);
          StorageService.debugMyWatchlistTvOsCapOverride = enabledAtRelease;
        } finally {
          backend.release.complete();
        }
        await pending;
        final raw = await backend.durable();
        expect(raw, isA<String>());
        final rows = jsonDecode(raw! as String) as List;
        expect(
          rows.map((e) => e['item']['id']),
          enabledAtRelease ? ['new'] : ['new', 'old'],
        );
        expect(
          utf8.encode(raw as String).length >
              StorageService.myWatchlistTvOsCapBytes,
          !enabledAtRelease,
        );
        expect(backend.writes, ['set:flutter.$_key']);
      },
    );
  }

  test('held backend read failure escapes without any write', () async {
    backend.holdRead = true;
    backend.failRead = true;
    final observed = expectLater(
      MyWatchlistStore.setMyWatchlistItem(_item('new'), true),
      throwsStateError,
    );
    await backend.entered.future;
    backend.release.complete();
    await observed;
    expect(backend.writes, isEmpty);
    expect(await backend.durable(), isNull);
  });

  test(
    'canonicalization is read-only; re-save collapses duplicates using first stored timestamp',
    () async {
      final item = _item('local', addon: 'A/B');
      final raw = jsonEncode([
        _row(item, addedAt: '7', key: 'obsolete-1'),
        _row(item, addedAt: 99, key: 'obsolete-2'),
      ]);
      install(raw);
      expect((await MyWatchlistStore.getMyWatchlistItems()).map((e) => e.id), [
        'local',
        'local',
      ]);
      expect(await MyWatchlistStore.isInMyWatchlist(item), isTrue);
      expect(await backend.durable(), raw);
      expect(backend.writes, isEmpty);
      await MyWatchlistStore.setMyWatchlistItem(item, true);
      final rows = jsonDecode((await backend.durable())! as String) as List;
      expect(rows, [
        {'key': 'movie:addon:A%2FB:local', 'addedAt': 7, 'item': item.toJson()},
      ]);
    },
  );

  for (final useImdb in [true, false]) {
    test(
      'ambiguous duplicate playback matches are not removed: IMDb=$useImdb',
      () async {
        final item = _item('one', imdb: useImdb ? 'tt-dupe' : null);
        final raw = jsonEncode([_row(item), _row(item, addedAt: 2)]);
        install(raw);
        expect(
          await StorageService.removeMyWatchlistItemForPlayback(
            imdbId: useImdb ? 'TT-DUPE' : null,
            contentType: ' MOVIE ',
            title: 'same',
          ),
          isFalse,
        );
        expect(await backend.durable(), raw);
        expect(backend.writes, isEmpty);
      },
    );
  }

  test(
    'no-match IMDb never falls back to matching title, and title ignores IMDb-bearing rows',
    () async {
      final raw = jsonEncode([_row(_item('known', imdb: 'tt-known'))]);
      install(raw);
      for (final imdb in ['tt-missing', null]) {
        expect(
          await StorageService.removeMyWatchlistItemForPlayback(
            imdbId: imdb,
            contentType: 'movie',
            title: 'Same',
          ),
          isFalse,
        );
      }
      expect(await backend.durable(), raw);
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'addon-qualified fallback removes only unique match and persists canonical survivor',
    () async {
      final a = _item('a', addon: 'A');
      final b = _item('b', addon: 'B');
      install(jsonEncode([_row(a), _row(b)]));
      expect(
        await StorageService.removeMyWatchlistItemForPlayback(
          contentType: 'movie',
          title: 'Same',
        ),
        isFalse,
      );
      expect(
        await StorageService.removeMyWatchlistItemForPlayback(
          contentType: 'movie',
          title: ' same ',
          addonId: ' a ',
        ),
        isTrue,
      );
      expect(jsonDecode((await backend.durable())! as String), [
        {'key': 'movie:addon:B:b', 'addedAt': 1, 'item': b.toJson()},
      ]);
      expect(backend.writes, ['set:flutter.$_key']);
    },
  );

  test(
    'malformed rows do not hide unique match and survive its removal',
    () async {
      final malformed = {'key': 'bad', 'item': 7};
      install(jsonEncode([malformed, _row(_item('one', imdb: 'tt-one'))]));
      expect(
        await StorageService.removeMyWatchlistItemForPlayback(
          imdbId: 'tt-one',
          contentType: 'movie',
          title: '',
        ),
        isTrue,
      );
      expect(await backend.durable(), jsonEncode([malformed]));
      expect(await MyWatchlistStore.getMyWatchlistItems(), isEmpty);
    },
  );

  test(
    'unsupported playback type returns before even opening preferences',
    () async {
      backend.failRead = true;
      expect(
        await StorageService.removeMyWatchlistItemForPlayback(
          contentType: 'channel',
          title: 'Same',
        ),
        isFalse,
      );
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'wrong physical type escapes but malformed JSON is read as empty without repair',
    () async {
      for (final raw in <Object>[
        7,
        true,
        <String>['bad'],
      ]) {
        install(raw);
        await expectLater(
          MyWatchlistStore.getMyWatchlistItems(),
          throwsA(isA<TypeError>()),
        );
        await expectLater(
          MyWatchlistStore.setMyWatchlistItem(_item('x'), true),
          throwsA(isA<TypeError>()),
        );
        await expectLater(
          StorageService.removeMyWatchlistItemForPlayback(
            contentType: 'movie',
            title: 'Same',
          ),
          throwsA(isA<TypeError>()),
        );
        expect(backend.writes, isEmpty);
      }
      for (final raw in ['{', '{}', 'null']) {
        install(raw);
        expect(await MyWatchlistStore.getMyWatchlistItems(), isEmpty);
        expect(
          await StorageService.removeMyWatchlistItemForPlayback(
            contentType: 'movie',
            title: 'Same',
          ),
          isFalse,
        );
        expect(await backend.durable(), raw);
        expect(backend.writes, isEmpty);
      }
    },
  );

  for (final action in [
    'save',
    'playback with survivor',
    'unsave last',
    'playback last',
    'clear',
  ]) {
    test(
      '$action backend failure escapes with durable state unchanged',
      () async {
        final item = _item('one', imdb: 'tt-one');
        final raw = jsonEncode([
          _row(item),
          if (action == 'playback with survivor') _row(_item('keep')),
        ]);
        install(raw);
        backend.failWrite = true;
        backend.failRemove = true;
        Future<void> act() async {
          if (action == 'save' || action == 'unsave last') {
            await MyWatchlistStore.setMyWatchlistItem(item, action == 'save');
          } else if (action == 'clear') {
            await MyWatchlistStore.clearMyWatchlist();
          } else {
            await StorageService.removeMyWatchlistItemForPlayback(
              imdbId: 'tt-one',
              contentType: 'movie',
              title: 'Same',
            );
          }
        }

        await expectLater(act(), throwsStateError);
        expect(await backend.durable(), raw);
        expect(backend.writes, [
          '${action == 'save' || action == 'playback with survivor' ? 'set' : 'remove'}:flutter.$_key',
        ]);
      },
    );
  }
}
