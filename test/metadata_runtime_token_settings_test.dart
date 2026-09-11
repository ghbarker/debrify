import 'package:debrify/screens/settings/metadata_settings_page.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/tmdb_credential_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'tmdb_runtime_credentials_test.dart' show FailingTokenStore;

void main() {
  late SharedPreferencesStorePlatform previous;
  late FailingTokenStore store;
  setUp(() {
    TmdbCredentialService.resetForTesting();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'runtime-token-widget');
    PlatformUtil.debugSetAndroidTvCached(true);
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    store = FailingTokenStore();
    SharedPreferencesStorePlatform.instance = store;
    StremioService.instance.invalidateCache();
  });
  tearDown(() {
    TmdbCredentialService.resetForTesting();
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
    PlatformUtil.debugSetAndroidTvCached(null);
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
  });

  Future<void> open(WidgetTester tester) async {
    final repository = TmdbMetadataRepository(
      token: '',
      clientFactory: () => MockClient((_) async => http.Response('[]', 200)),
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(home: MetadataSettingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'TV arrows reach token row and Enter opens a masked empty editor',
    (tester) async {
      await tester.runAsync(
        () => TmdbCredentialService.save(
          'saved-secret',
        ).timeout(const Duration(seconds: 5)),
      );
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final focusedTile = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ListTile>();
      expect((focusedTile?.title as Text?)?.data, 'TMDB API Read Access Token');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('tmdb-token-input')),
      );
      expect(field.obscureText, isTrue);
      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.controller!.text, isEmpty);
      expect(find.textContaining('saved-secret'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(TmdbCredentialService.effectiveToken, 'saved-secret');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed token save keeps editor and previous effective credential',
    (tester) async {
      await tester.runAsync(
        () => TmdbCredentialService.save(
          'old-secret',
        ).timeout(const Duration(seconds: 5)),
      );
      await open(tester);
      await tester.tap(find.text('TMDB API Read Access Token'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new-secret');
      store.failure = 'false';
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Could not save the token. Try again.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      expect(TmdbCredentialService.effectiveToken, 'old-secret');
      store.failure = '';
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(TmdbCredentialService.effectiveToken, 'new-secret');
      await tester.tap(find.text('TMDB API Read Access Token'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(TmdbCredentialService.hasOverride, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
