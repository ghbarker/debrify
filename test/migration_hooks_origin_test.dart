import 'package:debrify/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Real origin207163b4b9d2e86412c381e9834305ab2cb51bdd. Observe the platform
// persistence boundary; no migration algorithm or production bodies are copied.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final persisted = <String, Object>{};
  final writes = <(String, String, Object)>[];
  String? failKey;
  late SharedPreferences prefs;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') {
            return Map<String, Object>.from(persisted);
          }
          final args = call.arguments as Map;
          final key = args['key'] as String;
          if (call.method.startsWith('set')) {
            if (key == failKey) {
              throw PlatformException(code: 'synthetic-write-failure');
            }
            final value = args['value'] as Object;
            persisted[key] = value;
            writes.add((call.method, key.substring('flutter.'.length), value));
            return true;
          }
          throw StateError('Unexpected preferences operation: ${call.method}');
        });
    prefs = await SharedPreferences.getInstance();
  });
  setUp(() async {
    persisted.clear();
    writes.clear();
    failKey = null;
    await prefs.reload();
  });
  tearDownAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> seed(Map<String, Object> values) async {
    persisted.addAll({
      for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
    });
    await prefs.reload();
  }

  test(
    'fresh migration persists exact cross-store order and scalar types once',
    () async {
      await StorageService.migrateDefaultsGeneration();
      expect(writes, <(String, String, Object)>[
        ('setString', 'detail_theme', 'spotlight'),
        ('setString', 'app_theme', 'spotlight'),
        ('setString', 'detail_page_style', 'showcase'),
        ('setString', 'tv_home_style', 'spotlight'),
        ('setString', 'tv_sidebar_style', 'pill'),
        ('setString', 'desktop_sidebar_style', 'pill'),
        ('setBool', 'home_hero_trailer_enabled', true),
        ('setBool', 'detail_trailer_autoplay_enabled', true),
        ('setString', 'debrify_tv_style', 'spotlight'),
        ('setInt', 'defaults_generation', 3),
      ]);
      expect(persisted.length, 10);
      final snapshot = Map<String, Object>.from(persisted);
      writes.clear();
      await StorageService.migrateDefaultsGeneration();
      expect(writes, isEmpty);
      expect(persisted, snapshot);
    },
  );

  for (final generation in [1, 2, 3, 4]) {
    test('generation $generation adopts only remaining phases', () async {
      await seed({'defaults_generation': generation});
      await StorageService.migrateDefaultsGeneration();
      expect(writes, <(String, String, Object)>[
        if (generation < 2) ...[
          ('setBool', 'home_hero_trailer_enabled', true),
          ('setBool', 'detail_trailer_autoplay_enabled', true),
        ],
        if (generation < 3) ...[
          ('setString', 'debrify_tv_style', 'grid'),
          ('setInt', 'defaults_generation', 3),
        ],
      ]);
    });
  }

  test(
    'explicit choices, false toggles and synthetic credential bytes survive',
    () async {
      final original = <String, Object>{
        'app_theme': 'classic',
        'detail_page_style': 'legacy',
        'tv_home_style': 'legacy',
        'tv_sidebar_style': 'classic',
        'desktop_sidebar_style': 'classic',
        'home_hero_trailer_enabled': false,
        'detail_trailer_autoplay_enabled': false,
        'real_debrid_api_key': 'synthetic-only-not-a-real-token',
        'pikpak_default_folder_id': '',
        'unrelated_int': 7,
      };
      await seed(original);
      await StorageService.migrateDefaultsGeneration();
      expect(writes, [
        ('setString', 'debrify_tv_style', 'grid'),
        ('setInt', 'defaults_generation', 3),
      ]);
      for (final entry in original.entries) {
        expect(persisted['flutter.${entry.key}'], entry.value);
        expect(
          persisted['flutter.${entry.key}'].runtimeType,
          entry.value.runtimeType,
        );
      }
      expect(persisted.containsKey('flutter.detail_theme'), isFalse);
    },
  );

  test(
    'existing detail mirror survives adoption and feeds later theme phase',
    () async {
      await seed({'detail_theme': 'custom'});
      await StorageService.migrateDefaultsGeneration();
      expect(writes.first, ('setString', 'app_theme', 'spotlight'));
      expect(persisted['flutter.detail_theme'], 'custom');
      expect(persisted['flutter.debrify_tv_style'], 'spotlight');
    },
  );

  test(
    'failed write does not commit generation; retry skips persisted prefix',
    () async {
      failKey = 'flutter.tv_home_style';
      await expectLater(
        StorageService.migrateDefaultsGeneration(),
        throwsA(isA<PlatformException>()),
      );
      expect(writes.map((row) => row.$2), [
        'detail_theme',
        'app_theme',
        'detail_page_style',
      ]);
      expect(persisted.containsKey('flutter.defaults_generation'), isFalse);
      failKey = null;
      await prefs.reload();
      writes.clear();
      await StorageService.migrateDefaultsGeneration();
      expect(writes.first, ('setString', 'tv_home_style', 'spotlight'));
      expect(writes.last, ('setInt', 'defaults_generation', 3));
    },
  );
}

