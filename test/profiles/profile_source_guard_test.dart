import 'dart:io';

import 'package:debrify/services/profiles/privacy_log.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/source_text.dart';

void main() {
  test(
    'direct SharedPreferences opens stay inside reviewed adapters/stores',
    () {
      const reviewedCallCounts = <String, int>{
        'lib/services/profiles/profile_bootstrap.dart': 1,
        'lib/services/profiles/profile_preferences.dart': 3,
        'lib/services/profiles/profile_migration_service.dart': 1,
        'lib/services/profiles/profile_package_service.dart': 1,
        'lib/services/profiles/profile_data_generation.dart': 5,
        'lib/services/profiles/native_profile_projection.dart': 3,
        'lib/services/profiles/device_key_provider.dart': 5,
        // These two perform reviewed whole-store durability/reset operations;
        // neither exposes a generic preference API to feature code.
        'lib/services/profiles/profile_registry.dart': 2,
        'lib/services/profiles/profile_device_reset_service.dart': 1,
        'lib/services/secret_vault.dart': 1,
        'lib/services/remote_control/remote_pairing_store.dart': 7,
        'lib/services/android_download_history.dart': 1,
        'lib/services/desktop_schedule_service.dart': 2,
      };
      final violations = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        final source = readSource(entity.path);
        final count = 'SharedPreferences.getInstance()'
            .allMatches(source)
            .length;
        final reviewedCount = reviewedCallCounts[path];
        if (reviewedCount != null) {
          if (count != reviewedCount) violations.add('$path:$count');
        } else if (count != 0) {
          violations.add(path);
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Use ProfilePreferences or register a reviewed device/job store.',
      );
    },
  );

  test('profile-owned fixed database names stay in scoped path adapters', () {
    const allowed = <String>{
      // These two legacy services are migrated by ProfileDatabasePaths. The
      // allowlist is intentionally exact so another bypass cannot appear.
      'lib/services/debrify_tv_database.dart',
      'lib/services/iptv_catalog_db.dart',
      'lib/services/profiles/profile_registry.dart',
      'lib/services/profiles/profile_bootstrap.dart',
      'lib/services/profiles/profile_migration_service.dart',
      'lib/services/profiles/profile_database_snapshot.dart',
    };
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (allowed.contains(path)) continue;
      final source = readSource(entity.path);
      if (source.contains("'debrify_tv.db'") ||
          source.contains("'iptv_catalog.db'")) {
        violations.add(path);
      }
    }
    expect(violations, isEmpty);
  });

  test('sqflite-facing SQL never uses ON CONFLICT upserts', () {
    // `INSERT … ON CONFLICT DO UPDATE` needs SQLite 3.24 (2018). sqflite
    // links the OS library, and Android ships 3.24+ only from Android 10 —
    // minSdk 24 means Android 7/8/9 TV boxes (SQLite 3.9/3.18/3.22) fail to
    // COMPILE the statement: caught live on a Mi Box as "Failed to remove"
    // any Stremio addon. Use ProfileRegistry._compatUpsert instead. Files
    // that import package:sqlite3 bundle their own modern library and are
    // exempt (the IPTV catalog DB).
    // VACUUM INTO (SQLite 3.27) is allowed ONLY where a pre-3.27 fallback is
    // implemented and reviewed.
    const vacuumIntoAllowed = <String>{
      'lib/services/profiles/profile_database_snapshot.dart',
    };
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final source = readSource(entity.path);
      if (!source.contains("import 'package:sqflite")) continue;
      if (source.contains('ON CONFLICT')) {
        violations.add(path);
      }
      if (source.contains('VACUUM INTO') && !vacuumIntoAllowed.contains(path)) {
        violations.add('$path (VACUUM INTO without a fallback)');
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'these statements break on the OS SQLite of Android < 10',
    );
  });

  test('profile editor keeps feature controls hidden behind one switch', () {
    final source = readSource('lib/screens/profiles/edit_profile_screen.dart');
    // The switch moved onto the widget (public, @visibleForTesting) when the
    // save rule was extracted into EditProfileScreen.policyFor.
    expect(
      source,
      contains('static const bool showFeaturePolicyControls = false;'),
    );
    expect(
      'if (EditProfileScreen.showFeaturePolicyControls) ...['
          .allMatches(source)
          .length,
      1,
      reason: 'The existing feature controls must stay present but hidden.',
    );
    // The ceiling must never seed editor state again: grant masks derive
    // from _features, and allAllowedFor handed every newly ticked resource
    // writeRemote regardless of the profile's actual policy (review finding,
    // 2026-08-16). policyFor: stored policy on edit, role DEFAULTS on create.
    expect(
      source,
      contains('return ProfilePolicy.defaultsFor(role);'),
      reason: 'policyFor must fall back to role defaults on create.',
    );
    expect(
      source,
      contains(
        "profile?.policy.enabled ?? ProfilePolicy.defaultsFor(_role).enabled",
      ),
      reason: 'Initialization must seed from the stored policy, not a preset.',
    );
    expect(
      RegExp(r'allAllowedFor\(').allMatches(source).length,
      0,
      reason: 'The role ceiling must not seed editor state.',
    );
  });

  test(
    'search result preservation is owned by the mounted profile session',
    () {
      final host = readSource('lib/screens/search_screen.dart');
      final source = readSource(
        'lib/screens/search/keyword_search_controller.dart',
      );
      expect(
        source,
        contains('ProfileSessionMemory<KwPreservedState> kwPreserved'),
      );
      expect(
        host,
        contains('_profileSessionOwner = ProfileSessionMemory.captureOwner()'),
      );
      expect(source, contains('kwPreserved.take('));
      expect(source, contains('kwPreserved.store('));
      expect(
        source,
        isNot(contains('static KwPreservedState? kwPreserved')),
        reason: 'Raw screen statics can carry content across profile switches.',
      );
    },
  );

  test('Android protects recents before pause and notifications stay generic', () {
    final activity = readSource(
      'android/app/src/main/kotlin/com/debrify/app/MainActivity.kt',
    );
    final onPause = activity.substring(
      activity.indexOf('override fun onPause()'),
      activity.indexOf('override fun onUserLeaveHint()'),
    );
    expect(onPause, contains('shouldProtectWhenBackgrounded(this)'));
    expect(
      onPause.indexOf('window.addFlags'),
      lessThan(onPause.indexOf('super.onPause()')),
      reason: 'FLAG_SECURE must precede Android task-snapshot capture.',
    );

    final download = readSource(
      'android/app/src/main/kotlin/com/debrify/app/download/MediaStoreDownloadService.kt',
    );
    final recording = readSource(
      'android/app/src/main/kotlin/com/debrify/app/recording/LiveRecordingService.kt',
    );
    final alarm = readSource(
      'android/app/src/main/kotlin/com/debrify/app/recording/RecordingAlarmReceiver.kt',
    );
    expect(download, isNot(contains('.setContentTitle(state.fileName)')));
    expect(
      download,
      isNot(contains('.setSubText(if (completed) null else title)')),
    );
    expect(download, isNot(contains('.setSummaryText(title)')));
    expect(recording, isNot(contains('.setContentTitle(state.channelName)')));
    expect(
      recording,
      isNot(contains('.setSubText(if (completed) null else title)')),
    );
    expect(alarm, isNot(contains(r'${schedule.channelName} —')));
  });

  test('Android low-resolution rendering is strictly TV-only', () {
    final activity = readSource(
      'android/app/src/main/kotlin/com/debrify/app/MainActivity.kt',
    );
    final renderScale = activity.substring(
      activity.indexOf('private fun computeRenderScale('),
      activity.indexOf('/** Rewrites the viewport metrics'),
    );
    expect(renderScale, contains('if (!isTelevision()) return'));
    expect(
      renderScale.indexOf('if (!isTelevision()) return'),
      lessThan(renderScale.indexOf('"tv_low_res_render"')),
      reason:
          'A transferred TV preference must not resize a phone Flutter surface.',
    );
  });

  test('native subtitle fonts follow the active profile scope', () {
    final fontManager = readSource(
      'android/app/src/main/kotlin/com/debrify/app/util/SubtitleFontManager.kt',
    );
    final settings = readSource(
      'android/app/src/main/kotlin/com/debrify/app/util/SubtitleSettings.kt',
    );

    expect(
      fontManager,
      contains(
        'ProfilePreferenceProjection.scopedPreferences(context, PREFS_NAME)',
      ),
    );
    expect(
      fontManager,
      contains('active.profileId != MIGRATED_ADMIN_PROFILE_ID'),
    );
    expect(
      settings,
      contains('ProfilePreferenceProjection.scopedPreferences('),
    );
  });

  test('Debrify TV access stays behind the profile-switch scope gate', () {
    final files = <String>[
      'lib/services/debrify_tv_cache_service.dart',
      'lib/services/debrify_tv_repository.dart',
      'lib/services/iptv_media_store.dart',
    ];
    final directWrite = RegExp(
      r'await\s+db\.(?:insert|update|delete|execute|rawInsert|rawUpdate|rawDelete)\s*\(',
    );
    final rawHandle = RegExp(
      r'DebrifyTvDatabase\s*\.\s*instance\s*\.\s*database',
    );
    for (final path in files) {
      final source = readSource(path);
      expect(
        rawHandle.hasMatch(source),
        isFalse,
        reason: '$path reads can race DebrifyTvDatabase.closeScope()',
      );
      if (path.endsWith('iptv_media_store.dart')) {
        expect(
          source.contains('DebrifyTvDatabase.instance.runScoped'),
          isTrue,
          reason: '$path writes must go through runScoped',
        );
      }
      // Writes inside `_runScoped` / `runScoped` callbacks are in-scope.
      // A future unscoped `await db.delete` in the same file must still fail.
      expect(
        directWrite.hasMatch(sourceWithoutRunScopedBodies(source)),
        isFalse,
        reason: '$path has a db write outside runScoped',
      );
    }
  });

  test('unscoped deletes still fail after a runScoped body is present', () {
    const synthetic = '''
Future<void> leak(Database db) async {
  DebrifyTvDatabase.instance.runScoped((db) async {
    await db.delete('scoped');
  });
  await db.delete('leaked');
}
''';
    expect(
      RegExp(
        r'await\s+db\.(?:insert|update|delete|execute|rawInsert|rawUpdate|rawDelete)\s*\(',
      ).hasMatch(sourceWithoutRunScopedBodies(synthetic)),
      isTrue,
    );
  });

  test('profile, download, deep-link, and remote logs stay redacted', () {
    final files = <File>[
      ...Directory('lib/services')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/widgets/remote')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/screens/settings')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    final violations = <String>[];
    for (final file in files) {
      final source = readSource(file.path);
      if (RegExp(r'\bprint\s*\(').hasMatch(source)) {
        violations.add(file.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Service diagnostics must pass through the redacted debug sink.',
    );
    final main = readSource('lib/main.dart');
    expect(main, contains('PrivacyLog.install();'));
    expect(
      main,
      isNot(contains('attachDiagnosticSink')),
      reason: 'General debugPrint output must never enter support exports.',
    );
    final diagnostics = readSource('lib/services/diagnostic_log.dart');
    expect(diagnostics, isNot(contains('recordConsole')));
    expect(diagnostics, isNot(contains('error.toString()')));
    expect(diagnostics, isNot(contains('details.context')));
    expect(
      'debugPrint ='.allMatches(main).length,
      1,
      reason: 'Do not replace the installed process-wide privacy sink.',
    );
  });

  test('device reset stops and deletes Dart and native diagnostics', () {
    final reset = readSource(
      'lib/services/profiles/profile_device_reset_service.dart',
    );
    expect(
      'DiagnosticLog.instance.clearForDeviceReset'.allMatches(reset).length,
      greaterThanOrEqualTo(2),
      reason:
          'The drain and final cleanup must both handle journal resumption.',
    );
    expect(reset, contains("'diagnostics',"));

    final nativeLog = readSource(
      'android/app/src/main/kotlin/com/debrify/app/diagnostics/DiagnosticFileLog.kt',
    );
    final nativeClear = nativeLog.substring(
      nativeLog.indexOf('fun clearForDeviceReset'),
      nativeLog.indexOf('fun recordPreviousProcessExit'),
    );
    expect(nativeClear, contains('accepting = false'));
    expect(nativeClear, contains('directory.deleteRecursively()'));
    expect(nativeClear, contains('.clear()'));
    final nativeAppend = nativeLog.substring(
      nativeLog.indexOf('private fun append('),
      nativeLog.indexOf('private fun trimSegment('),
    );
    expect(
      nativeAppend.indexOf('if (!accepting) return'),
      greaterThan(nativeAppend.indexOf('synchronized(fileLock)')),
      reason: 'Reset must win against the crash-handler write race.',
    );

    final activity = readSource(
      'android/app/src/main/kotlin/com/debrify/app/MainActivity.kt',
    );
    expect(activity, contains('"clearForDeviceReset" ->'));
  });

  test('diagnostic export is hidden on tvOS until Remote transfer owns it', () {
    final settings = readSource('lib/screens/settings_screen.dart');
    final authorizationCheck = settings.substring(
      settings.indexOf('Future<bool> _activeProfileMayExportDiagnostics()'),
      settings.indexOf('Future<void> _loadSummariesForCurrentProfile()'),
    );
    expect(
      authorizationCheck,
      contains('if (PlatformUtil.isTvOS) return false;'),
    );
  });

  test('privacy sink removes sentinel URLs, tokens, IPs, and payloads', () {
    const sentinel = 'PRIVATE_SENTINEL';
    final redacted = PrivacyLog.redact(
      'request failed: https://10.20.30.40:8080/path?token=$sentinel '
      'authorization=Bearer-$sentinel payload: {"key":"$sentinel"}',
    );
    expect(redacted, isNot(contains(sentinel)));
    expect(redacted, isNot(contains('10.20.30.40')));
    expect(redacted, isNot(contains('https://')));
  });
}

/// Drop `_runScoped(...)` / `.runScoped(...)` argument lists, including the
/// callback body, so remaining `await db.delete` is an unscoped write.
/// Paren-depth only: strings/comments with `(` / `)` are not skipped.
String sourceWithoutRunScopedBodies(String source) {
  final pattern = RegExp(r'(?:_runScoped|\.runScoped)\s*\(');
  var out = source;
  while (true) {
    final match = pattern.firstMatch(out);
    if (match == null) return out;
    final open = match.end - 1;
    var depth = 0;
    var closed = -1;
    for (var i = open; i < out.length; i++) {
      final c = out[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) {
          closed = i;
          break;
        }
      }
    }
    if (closed < 0) return out;
    out = '${out.substring(0, match.start)} ${out.substring(closed + 1)}';
  }
}
