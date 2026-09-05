import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Real host API origin ac022536f168aaedda5d432489a793cf58c3b585.
// This complete builder body also matches pre-S2 exporter origin 6d26d7a1.
// Raw synthetic JSON seeds legacy states; no production formula is copied.
const playlistProgressKey = 'playback_state_v1';
Map<String, dynamic> playlistProgressRecipe() => Map<String, dynamic>.from(
  (jsonDecode(
            File(
              'test/fixtures/storage_origin_restore/recipe.json',
            ).readAsStringSync(),
          )
          as Map)['residualDomains']['playlist-progress']
      as Map,
);

Future<void> seedPlaylistProgress() async {
  final prefs = await ProfilePreferences.instance();
  await prefs.setString(
    playlistProgressKey,
    playlistProgressRecipe()['inputValues'][playlistProgressKey] as String,
  );
}

Future<void> expectPlaylistProgressBuilder() async {
  final recipe = playlistProgressRecipe();
  final items = (recipe['playlistItems'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  expect(
    await StorageService.buildPlaylistProgressMap(items),
    recipe['expectedProgress'],
  );
}

Map<String, dynamic> _episode(
  int position,
  int updated, [
  int duration = 100,
]) => {'positionMs': position, 'durationMs': duration, 'updatedAt': updated};
Map<String, dynamic> _series(
  String title, {
  Map<String, dynamic>? episodes,
  Map<String, dynamic>? finished,
}) => {
  'type': 'series',
  'title': title,
  if (episodes != null) 'seasons': {'1': episodes},
  if (finished != null) 'finishedEpisodes': {'1': finished},
};
Map<String, dynamic> _item(String title, {int? count, int? fileCount}) => {
  'title': title,
  'torrent_hash': 'fixed',
  if (count != null) 'count': count,
  if (fileCount != null) 'fileCount': fileCount,
};
Future<Map<String, Map<String, dynamic>>> _build(
  Map<String, dynamic> states,
  List<Map<String, dynamic>> items,
) async {
  final prefs = await ProfilePreferences.instance();
  await prefs.setString(playlistProgressKey, jsonEncode(states));
  return StorageService.buildPlaylistProgressMap(items);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StorageService.resetProfileCaches();
  });
  tearDown(() {
    StorageService.resetProfileCaches();
    ProfileRuntime.debugReset();
  });

  test(
    'real builder matches independently declared synthetic fixture outputs',
    () async {
      await seedPlaylistProgress();
      await expectPlaylistProgressBuilder();
    },
  );

  test('video wins over series and missing video fields remain zero', () async {
    expect(
      await _build(
        {
          'video_show': {'type': 'video', 'durationMs': 100},
          'series_show': _series('Show', episodes: {'1': _episode(90, 2)}),
        },
        [_item('Show')],
      ),
      {
        'realdebrid|hash:fixed': {
          'positionMs': 0,
          'durationMs': 100,
          'updatedAt': 0,
        },
      },
    );
  });

  for (final reverse in [false, true]) {
    test(
      'first partial title match follows state insertion order $reverse',
      () async {
        final entries = [
          MapEntry(
            'series_one',
            _series('partial', episodes: {'1': _episode(10, 2)}),
          ),
          MapEntry(
            'series_two',
            _series('partial show', episodes: {'1': _episode(80, 3)}),
          ),
        ];
        expect(
          await _build(Map.fromEntries(reverse ? entries.reversed : entries), [
            _item('Partial Show Extended'),
          ]),
          {
            'realdebrid|hash:fixed': {
              'positionMs': reverse ? 800000 : 100000,
              'durationMs': 1000000,
              'updatedAt': reverse ? 3 : 2,
            },
          },
        );
      },
    );
    test(
      'equal latest timestamps keep first traversed episode $reverse',
      () async {
        final entries = [
          MapEntry('1', _episode(20, 10)),
          MapEntry('2', _episode(80, 10)),
        ];
        expect(
          await _build(
            {
              'series_show': _series(
                'Show',
                episodes: Map.fromEntries(reverse ? entries.reversed : entries),
              ),
            },
            [_item('Show', count: 2)],
          ),
          {
            'realdebrid|hash:fixed': {
              'positionMs': reverse ? 800000 : 200000,
              'durationMs': 2000000,
              'updatedAt': 10,
            },
          },
        );
      },
    );
  }

  for (final position in [94, 95, 96]) {
    test(
      'hardcoded95 cutoff combines finished markers without double count $position',
      () async {
        expect(
          await _build(
            {
              'series_show': _series(
                'Show',
                episodes: {'1': _episode(99, 1), '2': _episode(position, 2)},
                finished: {'1': false},
              ),
            },
            [_item('Show', fileCount: 3)],
          ),
          {
            'realdebrid|hash:fixed': {
              'positionMs': position == 94 ? 1940000 : 2000000,
              'durationMs': 3000000,
              'updatedAt': 2,
            },
          },
        );
      },
    );
  }

  test('marker values ignored and over100percent remains unclamped', () async {
    expect(
      await _build(
        {
          'series_show': _series(
            'Show',
            episodes: {'1': _episode(10, 1)},
            finished: {'1': false, '2': null},
          ),
        },
        [_item('Show', fileCount: 1)],
      ),
      {
        'realdebrid|hash:fixed': {
          'positionMs': 2000000,
          'durationMs': 1000000,
          'updatedAt': 1,
        },
      },
    );
  });
  for (final updated in [0, -1]) {
    test(
      'finished markers without positive timestamp emit no series progress $updated',
      () async {
        expect(
          await _build(
            {
              'series_show': _series(
                'Show',
                episodes: {'1': _episode(100, updated)},
                finished: {'1': true},
              ),
            },
            [_item('Show')],
          ),
          isEmpty,
        );
      },
    );
  }
  for (final count in [null, 0, -1, 2]) {
    test('fileCount precedence and zero fallback retained $count', () async {
      final result = await _build(
        {
          'series_show': _series('Show', episodes: {'1': _episode(50, 1)}),
        },
        [_item('Show', fileCount: count, count: 3)],
      );
      if (count == -1) {
        expect(result, isEmpty);
      } else {
        expect(result, {
          'realdebrid|hash:fixed': {
            'positionMs': 500000,
            'durationMs': count == null
                ? 3000000
                : count == 0
                ? 1000000
                : 2000000,
            'updatedAt': 1,
          },
        });
      }
    });
  }
  test(
    'empty partial title matches; IMDb alone does not select state',
    () async {
      expect(
        await _build(
          {
            'series_other': {
              ..._series('Unrelated', episodes: {'1': _episode(10, 2)}),
              'imdbId': 'tt123',
            },
          },
          [
            {..._item('Wanted'), 'imdbId': 'tt123'},
          ],
        ),
        isEmpty,
      );
      expect(
        await _build(
          {
            'series_empty': _series('', episodes: {'1': _episode(10, 2)}),
          },
          [_item('Wanted')],
        ),
        {
          'realdebrid|hash:fixed': {
            'positionMs': 100000,
            'durationMs': 1000000,
            'updatedAt': 2,
          },
        },
      );
    },
  );
  test(
    'later duplicate output key overwrites value without reordering keys',
    () async {
      final result = await _build(
        {
          'video_a': {'type': 'video', ..._episode(10, 1)},
          'video_b': {'type': 'video', ..._episode(20, 2)},
        },
        [
          _item('A'),
          {..._item('A'), 'torrent_hash': 'other'},
          _item('B'),
        ],
      );
      expect(result.keys, ['realdebrid|hash:fixed', 'realdebrid|hash:other']);
      expect(result['realdebrid|hash:fixed'], _episode(20, 2));
    },
  );
  for (final raw in ['[', '[]', 'null']) {
    test('top-level malformed or nonmap JSON yields empty map $raw', () async {
      final prefs = await ProfilePreferences.instance();
      await prefs.setString(playlistProgressKey, raw);
      expect(
        await StorageService.buildPlaylistProgressMap([_item('Show')]),
        isEmpty,
      );
    });
  }
  test('nested incorrect integer type remains a thrown error', () async {
    await expectLater(
      _build(
        {
          'series_show': _series(
            'Show',
            episodes: {
              '1': {'positionMs': 1.0, 'durationMs': 100, 'updatedAt': 1},
            },
          ),
        },
        [_item('Show')],
      ),
      throwsA(isA<TypeError>()),
    );
  });
  test('physical StringList remains a thrown error', () async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(playlistProgressKey, ['wrong physical type']);
    await expectLater(
      StorageService.buildPlaylistProgressMap([_item('Show')]),
      throwsA(isA<TypeError>()),
    );
  });
}
