import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_active_profile_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String preset([int padding = 0]) => jsonEncode({
  'notes': 'x' * padding,
  'filters': [
    {'name': 'HDR', 'pattern': 'HDR'},
  ],
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = StreamBadgesService.instance;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    ProfilePreferenceBudget.debugReset();
    svc.resetProfileScope();
  });
  tearDown(() {
    ProfilePreferenceBudget.debugReset();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    svc.resetProfileScope();
  });
  test(
    'concurrent imports preserve both inventories across service instances',
    () async {
      final other = StreamBadgesService();
      await Future.wait([
        svc.importJson(preset(), name: 'one'),
        other.importJson(preset(), name: 'two'),
      ]);
      expect(await svc.getSources(), hasLength(2));
    },
  );
  test(
    'aggregate size rejection preserves the previously saved preset',
    () async {
      await svc.importJson(preset(70 * 1024), name: 'one');
      await expectLater(
        svc.importJson(preset(70 * 1024), name: 'two'),
        throwsFormatException,
      );
      expect((await svc.getSources()).single.name, 'one');
      await expectLater(
        svc.importJson(preset(1100 * 1024), name: 'huge'),
        throwsFormatException,
      );
      expect((await svc.getSources()).single.name, 'one');
    },
  );
  test(
    'refused TV persistence never publishes or reports a successful import',
    () async {
      ProfilePreferenceBudget.debugEnforcedOverride = true;
      SharedPreferences.setMockInitialValues({'full': 'x' * (512 * 1024)});
      await svc.warmUp();
      await expectLater(
        svc.importJson(preset(), name: 'one'),
        throwsStateError,
      );
      expect(await svc.getSources(), isEmpty);
      expect(svc.matcher.value.isEmpty, true);
    },
  );
  test('refused master setting does not change its live value', () async {
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    SharedPreferences.setMockInitialValues({'full': 'x' * (512 * 1024)});
    await svc.warmUp();
    await expectLater(svc.setEnabled(false), throwsStateError);
    expect(svc.enabled, true);
  });
  test('pending URL import cannot cross a profile switch', () async {
    final a = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final b = ProfileScope(
      profileId: 'two',
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.initializeCommitted(a);
    final started = Completer<void>(), reply = Completer<http.Response>();
    final service = StreamBadgesService(
      httpClientFactory: () => MockClient((_) {
        started.complete();
        return reply.future;
      }),
    );
    final pending = service.importFromUrl(
      'https://example.invalid/badges.json',
    );
    final rejected = expectLater(pending, throwsStateError);
    await started.future;
    ProfileRuntime.publish(b);
    service.resetProfileScope();
    await service.warmUp();
    reply.complete(http.Response(preset(), 200));
    await rejected;
    expect(await service.getSources(), isEmpty);
    expect(service.matcher.value.isEmpty, true);
  });
  test('refresh cannot recreate a deleted preset', () async {
    final reply = Completer<http.Response>(), started = Completer<void>();
    final service = StreamBadgesService(
      httpClientFactory: () => MockClient((_) {
        started.complete();
        return reply.future;
      }),
    );
    final item = await service.importJson(
      preset(),
      name: 'one',
      url: 'https://example.invalid/badges.json',
    );
    final pending = service.refresh(item.source.id);
    final rejected = expectLater(pending, throwsStateError);
    await started.future;
    await service.remove(item.source.id);
    reply.complete(http.Response(preset(), 200));
    await rejected;
    expect(await service.getSources(), isEmpty);
  });
  test(
    'inactive restore cannot publish its matcher into active profile',
    () async {
      final a = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final b = ProfileScope(
        profileId: 'two',
        dataGeneration: 1,
        sessionEpoch: 0,
      );
      ProfileRuntime.initializeCommitted(a);
      await svc.warmUp();
      await ProfileRuntime.withCapturedScope(
        b,
        () => svc.importJson(preset(), name: 'inactive'),
      );
      expect(svc.matcher.value.isEmpty, true);
      expect(await svc.getSources(), isEmpty);
    },
  );
  test(
    'WebDAV refresh applies both source and master changes to live matcher',
    () async {
      await svc.warmUp();
      await svc.importJson(preset(), name: 'one');
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(StreamBadgesService.enabledKey, false);
      await const DefaultWebDavSyncActiveProfileRefresher().refresh({
        StreamBadgesService.enabledKey,
      }, authorizationBarrier: () {});
      expect(svc.matcher.value.isEmpty, true);
      expect(svc.enabled, false);
      await prefs.setBool(StreamBadgesService.enabledKey, true);
      await prefs.setString(StreamBadgesService.sourcesKey, '[]');
      await const DefaultWebDavSyncActiveProfileRefresher().refresh({
        StreamBadgesService.sourcesKey,
        StreamBadgesService.enabledKey,
      }, authorizationBarrier: () {});
      expect(svc.enabled, true);
      expect(svc.matcher.value.isEmpty, true);
    },
  );
  test(
    'sync refresh never deadlocks behind a writer waiting for its barrier',
    () async {
      await svc.warmUp();
      final entered = Completer<void>(), writing = Completer<void>();
      final guarded = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await writing.future;
        await const DefaultWebDavSyncActiveProfileRefresher().refresh({
          StreamBadgesService.sourcesKey,
        }, authorizationBarrier: () {});
      });
      await entered.future;
      final pending = svc.importJson(preset(), name: 'one');
      await Future<void>.delayed(Duration.zero);
      writing.complete();
      await Future.wait([guarded, pending]).timeout(const Duration(seconds: 2));
      expect(await svc.getSources(), hasLength(1));
    },
  );
  test('atomic import reads the value after a queued sync apply', () async {
    final entered = Completer<void>(), resume = Completer<void>();
    final existing = StreamBadgeSource(
      id: 'remote',
      name: 'remote',
      json: preset(),
    ).toJson();
    final guarded = ProfilePreferences.captureMutationSnapshot((_) async {
      entered.complete();
      await resume.future;
      final raw = await SharedPreferences.getInstance();
      await raw.setString(
        StreamBadgesService.sourcesKey,
        jsonEncode([existing]),
      );
    });
    await entered.future;
    final pending = svc.importJson(preset(), name: 'local');
    await Future<void>.delayed(Duration.zero);
    resume.complete();
    await Future.wait([guarded, pending]);
    expect(await svc.getSources(), hasLength(2));
  });
  test('selective transfer preserves a disabled master switch', () async {
    await svc.importJson(preset(), name: 'one');
    await svc.setEnabled(false);
    final payload = await svc.exportTransferJson();
    SharedPreferences.setMockInitialValues({});
    svc.resetProfileScope();
    await svc.warmUp();
    final result = await svc.applyBackup(payload);
    expect(result.imported, 1);
    expect(svc.enabled, false);
    expect(svc.matcher.value.isEmpty, true);
  });
  test(
    'legacy source arrays preserve the destination master setting',
    () async {
      await svc.setEnabled(false);
      await svc.applyBackup([
        StreamBadgeSource(id: 'one', name: 'one', json: preset()).toJson(),
      ]);
      expect(svc.enabled, false);
      expect(await svc.getSources(), hasLength(1));
    },
  );
  test('oversized restore is rejected without changing sources', () async {
    await svc.importJson(preset(), name: 'one');
    await expectLater(
      svc.applyBackup([
        StreamBadgeSource(
          id: 'two',
          name: 'two',
          json: preset(200 * 1024),
        ).toJson(),
      ]),
      throwsFormatException,
    );
    expect((await svc.getSources()).single.name, 'one');
  });
  test(
    'corrupt inventory is an error rather than an empty overwrite',
    () async {
      SharedPreferences.setMockInitialValues({
        StreamBadgesService.sourcesKey: 'broken',
      });
      await expectLater(
        svc.importJson(preset(), name: 'one'),
        throwsFormatException,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          StreamBadgesService.sourcesKey,
        ),
        'broken',
      );
    },
  );
  test(
    'corrupt optional presets do not block startup and can be reset',
    () async {
      SharedPreferences.setMockInitialValues({
        StreamBadgesService.sourcesKey: 'broken',
      });
      await svc.warmUp();
      expect(svc.matcher.value.isEmpty, true);
      await svc.clear();
      expect(await svc.getSources(), isEmpty);
      await svc.importJson(preset(), name: 'recovered');
      expect(svc.matcher.value.isEmpty, false);
    },
  );
}
