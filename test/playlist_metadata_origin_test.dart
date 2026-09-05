import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Real public API origin: df1568c4321a82eb9334be305b6d98505a8b5885.
// No copied implementation, export fixture, tvOS recovery or profile-safety proof.
const _mapping = 'tvmaze_series_mappings';
const _poster = 'playlist_poster_overrides_v1';
const _item = <String, dynamic>{'rdTorrentId': 7};

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences(super.data) : super.withData();
  final events = <String>[];
  bool failWrite = false;
  bool failRemove = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    events.add('set:$valueType:$key');
    if (failWrite) throw StateError('synthetic write failure');
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    events.add('remove:$key');
    if (failRemove) throw StateError('synthetic remove failure');
    return super.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Preferences backend;

  void install(Map<String, Object> values) {
    SharedPreferences.resetStatic();
    backend = _Preferences({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
      'flutter.metadata_sentinel': 'keep',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  Future<Object?> durable(String key) async =>
      (await backend.getAll())['flutter.$key'];

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install({});
  });
  tearDown(() async {
    expect(await durable('metadata_sentinel'), 'keep');
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });

  test('identity precedence, case, empty IDs and title collisions', () {
    final cases = <(Map<String, dynamic>, String)>[
      (
        {
          'rdTorrentId': 7,
          'torrent_hash': 'ABC',
          'torboxTorrentId': 8,
          'pikpakFileId': 'P',
          'title': 'Title',
        },
        'rd_7',
      ),
      (
        {'torrent_hash': 'ABC', 'torboxTorrentId': 8, 'pikpakFileId': 'P'},
        'hash_ABC',
      ),
      ({'torboxTorrentId': 8, 'pikpakFileId': 'P'}, 'torbox_8'),
      ({'pikpakFileId': 'P'}, 'pikpak_P'),
      ({'provider': 'torbox', 'rdTorrentId': 7}, 'rd_7'),
      ({'rdTorrentId': ''}, 'rd_'),
      ({'rdTorrentId': false}, 'rd_false'),
      ({'title': 'A-B'}, 'title_a_b'),
      ({'title': 'a b'}, 'title_a_b'),
      ({'title': ''}, 'title_'),
      ({}, 'title_unknown'),
      (
        {
          'provider': 'WeBdAv',
          'rdTorrentId': 7,
          'webdavServerId': 'SERVER',
          'webdavPath': '/Case/A',
        },
        'webdav|server:server|path:/Case/A',
      ),
    ];
    for (final (input, expected) in cases) {
      expect(
        StorageService.getPlaylistItemUniqueKey(input),
        expected,
        reason: '$input',
      );
    }
    for (final item in <Map<String, dynamic>>[
      {'provider': 7},
      {'title': 7},
    ]) {
      expect(
        () => StorageService.getPlaylistItemUniqueKey(item),
        throwsA(isA<TypeError>()),
      );
    }
  });

  test(
    'TVMaze save/read/collision/clear preserve JSON shape and unrelated entries',
    () async {
      install({_mapping: '{"first":{"untouched":true}}'});
      final before = DateTime.now().millisecondsSinceEpoch;
      await StorageService.saveTVMazeSeriesMapping(
        playlistItem: {'title': 'A-B'},
        tvmazeShowId: 42,
        showName: 'Show',
      );
      final after = DateTime.now().millisecondsSinceEpoch;
      final raw = await durable(_mapping);
      expect(raw, isA<String>());
      final map = jsonDecode(raw! as String) as Map<String, dynamic>;
      expect(map.keys.toList(), ['first', 'title_a_b']);
      final entry = map['title_a_b'] as Map<String, dynamic>;
      expect(entry.keys.toList(), ['tvmazeShowId', 'showName', 'savedAt']);
      expect(entry['tvmazeShowId'], 42);
      expect(entry['showName'], 'Show');
      expect(
        entry['savedAt'],
        allOf(isA<int>(), inInclusiveRange(before, after)),
      );
      expect(
        await StorageService.getTVMazeSeriesMapping({'title': 'a b'}),
        entry,
      );
      await StorageService.saveTVMazeSeriesMapping(
        playlistItem: {'title': 'a b'},
        tvmazeShowId: -1,
        showName: '',
      );
      expect(
        (await StorageService.getTVMazeSeriesMapping({
          'title': 'A-B',
        }))!['tvmazeShowId'],
        -1,
      );
      await StorageService.clearTVMazeSeriesMapping({'title': 'A-B'});
      expect(await durable(_mapping), '{"first":{"untouched":true}}');
      await StorageService.clearAllTVMazeSeriesMappings();
      expect(await durable(_mapping), isNull);
      expect(backend.events.every((e) => e.contains(_mapping)), isTrue);
    },
  );

  test(
    'poster save/read/collision and empty URL remain stored but not returned',
    () async {
      install({_poster: '{"first":{"posterUrl":"keep"}}'});
      final before = DateTime.now().millisecondsSinceEpoch;
      await StorageService.savePlaylistPosterOverride(
        playlistItem: _item,
        posterUrl: 'https://example.invalid/poster',
      );
      final after = DateTime.now().millisecondsSinceEpoch;
      final raw = await durable(_poster);
      expect(raw, isA<String>());
      final map = jsonDecode(raw! as String) as Map<String, dynamic>;
      expect(map.keys.toList(), ['first', 'rd_7']);
      final entry = map['rd_7'] as Map<String, dynamic>;
      expect(entry.keys.toList(), ['posterUrl', 'savedAt']);
      expect(
        entry['savedAt'],
        allOf(isA<int>(), inInclusiveRange(before, after)),
      );
      expect(
        await StorageService.getPlaylistPosterOverride(_item),
        'https://example.invalid/poster',
      );
      await StorageService.savePlaylistPosterOverride(
        playlistItem: _item,
        posterUrl: '',
      );
      expect(await StorageService.getPlaylistPosterOverride(_item), isNull);
      expect(
        (jsonDecode((await durable(_poster))! as String)
            as Map)['rd_7']['posterUrl'],
        '',
      );
      await StorageService.clearPlaylistPosterOverride(_item);
      expect(await durable(_poster), '{"first":{"posterUrl":"keep"}}');
      await StorageService.clearAllPlaylistPosterOverrides();
      expect(await durable(_poster), isNull);
      expect(backend.events.every((e) => e.contains(_poster)), isTrue);
    },
  );

  final domains =
      <
        ({
          String key,
          Future<void> Function(Map<String, dynamic>) save,
          Future<Object?> Function(Map<String, dynamic>) read,
          Future<void> Function(Map<String, dynamic>) clear,
          Future<void> Function() clearAll,
        })
      >[
        (
          key: _mapping,
          save: (item) => StorageService.saveTVMazeSeriesMapping(
            playlistItem: item,
            tvmazeShowId: 1,
            showName: 'S',
          ),
          read: StorageService.getTVMazeSeriesMapping,
          clear: StorageService.clearTVMazeSeriesMapping,
          clearAll: StorageService.clearAllTVMazeSeriesMappings,
        ),
        (
          key: _poster,
          save: (item) => StorageService.savePlaylistPosterOverride(
            playlistItem: item,
            posterUrl: 'P',
          ),
          read: StorageService.getPlaylistPosterOverride,
          clear: StorageService.clearPlaylistPosterOverride,
          clearAll: StorageService.clearAllPlaylistPosterOverrides,
        ),
      ];

  for (final d in domains) {
    test(
      '${d.key}: absent/no-match short circuit and malformed identifier catch boundary',
      () async {
        final bad = <String, dynamic>{'provider': 7};
        expect(await d.read(bad), isNull);
        await d.clear(bad);
        expect(backend.events, isEmpty);
        install({d.key: '{}'});
        expect(await d.read(bad), isNull);
        await d.clear(bad);
        await d.clear(_item);
        expect(backend.events, isEmpty);
        await expectLater(d.save(bad), throwsA(isA<TypeError>()));
        expect(backend.events, isEmpty);
        expect(await durable(d.key), '{}');
      },
    );

    test(
      '${d.key}: malformed JSON and non-object JSON read/clear swallow; save replaces',
      () async {
        for (final raw in ['{', '[]', 'null', '7']) {
          install({d.key: raw});
          expect(await d.read(_item), isNull);
          await d.clear(_item);
          expect(backend.events, isEmpty);
          expect(await durable(d.key), raw);
          await d.save(_item);
          expect((jsonDecode((await durable(d.key))! as String) as Map).keys, [
            'rd_7',
          ]);
          expect(backend.events, ['set:String:flutter.${d.key}']);
        }
      },
    );

    test(
      '${d.key}: physical type failure is outside read/save/clear catches',
      () async {
        for (final raw in <Object>[
          7,
          true,
          <String>['bad'],
        ]) {
          install({d.key: raw});
          await expectLater(d.read(_item), throwsA(isA<TypeError>()));
          await expectLater(d.save(_item), throwsA(isA<TypeError>()));
          await expectLater(d.clear(_item), throwsA(isA<TypeError>()));
          expect(backend.events, isEmpty);
          expect(await durable(d.key), raw);
          await d.clearAll();
          expect(await durable(d.key), isNull);
        }
      },
    );

    test(
      '${d.key}: save write failure escapes without durable mutation',
      () async {
        install({d.key: '{}'});
        backend.failWrite = true;
        await expectLater(d.save(_item), throwsStateError);
        expect(await durable(d.key), '{}');
        expect(backend.events, ['set:String:flutter.${d.key}']);
      },
    );

    test(
      '${d.key}: matching clear swallows write failure; clear-all propagates remove failure',
      () async {
        const raw = '{"rd_7":{"posterUrl":"P","tvmazeShowId":1},"keep":{}}';
        install({d.key: raw});
        backend.failWrite = true;
        await d.clear(_item);
        expect(await durable(d.key), raw);
        expect(backend.events, ['set:String:flutter.${d.key}']);
        backend.failRemove = true;
        await expectLater(d.clearAll(), throwsStateError);
        expect(await durable(d.key), raw);
        expect(backend.events.last, 'remove:flutter.${d.key}');
      },
    );
  }

  test(
    'TVMaze getter returns arbitrary nested map without field validation',
    () async {
      install({
        _mapping:
            '{"rd_7":{"tvmazeShowId":"legacy","showName":false,"savedAt":null,"extra":[1]}}',
      });
      expect(await StorageService.getTVMazeSeriesMapping(_item), {
        'tvmazeShowId': 'legacy',
        'showName': false,
        'savedAt': null,
        'extra': [1],
      });
      for (final value in [null, false, 'bad', <Object>[]]) {
        install({
          _mapping: jsonEncode({'rd_7': value}),
        });
        expect(await StorageService.getTVMazeSeriesMapping(_item), isNull);
      }
    },
  );

  test(
    'batch skips nonmaps/empty/null URLs, preserves order and accepts whitespace',
    () async {
      install({
        _poster:
            '{"z":{"posterUrl":"Z"},"skip":7,"empty":{"posterUrl":""},"null":{"posterUrl":null},"a":{"posterUrl":" "}}',
      });
      final result = await StorageService.getAllPlaylistPosterOverrides();
      expect(result, {'z': 'Z', 'a': ' '});
      expect(result.keys.toList(), ['z', 'a']);
      expect(backend.events, isEmpty);
    },
  );

  test(
    'one malformed poster type discards entire batch, but not a good individual lookup',
    () async {
      install({
        _poster:
            '{"rd_7":{"posterUrl":"good"},"bad":{"posterUrl":7},"last":{"posterUrl":"last"}}',
      });
      expect(await StorageService.getAllPlaylistPosterOverrides(), isEmpty);
      expect(await StorageService.getPlaylistPosterOverride(_item), 'good');
      expect(
        await StorageService.getPlaylistPosterOverride({'title': 'missing'}),
        isNull,
      );
      install({_poster: '{"rd_7":{"posterUrl":7}}'});
      expect(await StorageService.getPlaylistPosterOverride(_item), isNull);
      expect(backend.events, isEmpty);
    },
  );

  test(
    'batch absent/malformed JSON returns empty; wrong physical type escapes',
    () async {
      expect(await StorageService.getAllPlaylistPosterOverrides(), isEmpty);
      for (final raw in ['{', '[]', 'null']) {
        install({_poster: raw});
        expect(await StorageService.getAllPlaylistPosterOverrides(), isEmpty);
        expect(await durable(_poster), raw);
      }
      install({_poster: 7});
      await expectLater(
        StorageService.getAllPlaylistPosterOverrides(),
        throwsA(isA<TypeError>()),
      );
      expect(backend.events, isEmpty);
    },
  );
}
