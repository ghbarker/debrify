import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Write through [StorageService], read through [ProviderCredentialPrefs],
/// byte-equal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's22-roundtrip-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(ProfileRuntime.debugReset);

  test(
    'StorageService writes are readable through ProviderCredentialPrefs',
    () async {
      await ProviderCredentialPrefs.saveRdEndpoint('https://backup.example/rd');
      await ProviderCredentialPrefs.saveFileSelection('all');
      await ProviderCredentialPrefs.setTorboxCacheCheckEnabled(true);
      await ProviderCredentialPrefs.setRealDebridIntegrationEnabled(false);
      await ProviderCredentialPrefs.setRealDebridHiddenFromNav(true);
      await ProviderCredentialPrefs.setRdSkipBlockedTorrents(false);
      await ProviderCredentialPrefs.setTorboxIntegrationEnabled(false);
      await ProviderCredentialPrefs.setPremiumizeIntegrationEnabled(false);
      await ProviderCredentialPrefs.savePremiumizePostTorrentAction('delete');
      await ProviderCredentialPrefs.setAllDebridIntegrationEnabled(false);
      await ProviderCredentialPrefs.saveAllDebridPostTorrentAction('keep');
      await ProviderCredentialPrefs.savePostTorrentAction('delete');
      await ProviderCredentialPrefs.setPikPakEnabled(true);
      await ProviderCredentialPrefs.setPikPakAccessToken('access-token');
      await ProviderCredentialPrefs.setPikPakShowVideosOnly(false);
      await ProviderCredentialPrefs.setPikPakRestrictedFolder('fid', 'Restricted');
      await ProviderCredentialPrefs.setWebDavShowVideosOnly(false);
      await ProviderCredentialPrefs.setDefaultTorrentProvider('torbox');
      await ProviderCredentialPrefs.saveWebDavServers(const [
        WebDavConfig(
          id: 's1',
          name: 'Home',
          baseUrl: 'https://a.example/',
          username: 'u',
          password: 'p',
        ),
      ]);

      expect(
        await ProviderCredentialPrefs.getRdEndpoint(),
        'https://backup.example/rd',
      );
      expect(await ProviderCredentialPrefs.getFileSelection(), 'all');
      expect(
        await ProviderCredentialPrefs.getTorboxCacheCheckEnabled(),
        isTrue,
      );
      expect(
        await ProviderCredentialPrefs.getRealDebridIntegrationEnabled(),
        isFalse,
      );
      expect(
        await ProviderCredentialPrefs.getRealDebridHiddenFromNav(),
        isTrue,
      );
      expect(await ProviderCredentialPrefs.getRdSkipBlockedTorrents(), isFalse);
      expect(
        await ProviderCredentialPrefs.getTorboxIntegrationEnabled(),
        isFalse,
      );
      expect(
        await ProviderCredentialPrefs.getPremiumizeIntegrationEnabled(),
        isFalse,
      );
      expect(
        await ProviderCredentialPrefs.getPremiumizePostTorrentAction(),
        'delete',
      );
      expect(
        await ProviderCredentialPrefs.getAllDebridIntegrationEnabled(),
        isFalse,
      );
      expect(
        await ProviderCredentialPrefs.getAllDebridPostTorrentAction(),
        'keep',
      );
      expect(await ProviderCredentialPrefs.getPostTorrentAction(), 'delete');
      expect(await ProviderCredentialPrefs.getPikPakEnabled(), isTrue);
      expect(
        await ProviderCredentialPrefs.getPikPakAccessToken(),
        'access-token',
      );
      expect(await ProviderCredentialPrefs.getPikPakShowVideosOnly(), isFalse);
      expect(
        await ProviderCredentialPrefs.getPikPakRestrictedFolderId(),
        'fid',
      );
      expect(await ProviderCredentialPrefs.getWebDavShowVideosOnly(), isFalse);
      expect(
        await ProviderCredentialPrefs.getDefaultTorrentProvider(),
        'torbox',
      );
      expect(await ProviderCredentialPrefs.getWebDavEnabled(), isTrue);
      final servers = await ProviderCredentialPrefs.getWebDavServers();
      expect(servers, hasLength(1));
      expect(servers.first.baseUrl, 'https://a.example/');
      expect(servers.first.username, 'u');
      expect(servers.first.password, 'p');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('real_debrid_endpoint'),
        'https://backup.example/rd',
      );
      expect(prefs.getString('real_debrid_file_selection'), 'all');
      expect(prefs.getBool('real_debrid_integration_enabled'), isFalse);
      expect(prefs.getString('default_torrent_provider_v1'), 'torbox');
      expect(
        prefs.getString('pikpak_access_token'),
        startsWith(SecretVault.prefix),
      );
    },
  );
}
