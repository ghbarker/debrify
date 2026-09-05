import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins provider-credential *settings* encodings on [StorageService] before
/// the S2-2 extract. Key names and values are a frozen compatibility surface.
/// This file must not import the new store — that lands in the move commit.
///
/// CloudSecretPrefs already owns RD/TB/PM/AD/PikPak secret keys; those
/// forwards are not this slice. MDBList / player / IPTV are out of lane.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecretVault.debugReset(deviceIdOverride: 's22-pin-device');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  tearDown(ProfileRuntime.debugReset);

  group('defaults when no keys are stored', () {
    test('integration toggles, hidden-from-nav, cache, skip-blocked', () async {
      expect(await ProviderCredentialPrefs.getRealDebridIntegrationEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getTorboxIntegrationEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getPremiumizeIntegrationEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getAllDebridIntegrationEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getPikPakEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getWebDavEnabled(), isFalse);

      expect(await ProviderCredentialPrefs.getRealDebridHiddenFromNav(), isFalse);
      expect(await ProviderCredentialPrefs.getTorboxHiddenFromNav(), isFalse);
      expect(await ProviderCredentialPrefs.getPremiumizeHiddenFromNav(), isFalse);
      expect(await ProviderCredentialPrefs.getAllDebridHiddenFromNav(), isFalse);
      expect(await ProviderCredentialPrefs.getPikPakHiddenFromNav(), isFalse);
      expect(await ProviderCredentialPrefs.getWebDavHiddenFromNav(), isFalse);

      expect(await ProviderCredentialPrefs.getTorboxCacheCheckEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getPremiumizeCacheCheckEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getRdSkipBlockedTorrents(), isTrue);
    });

    test('endpoint, file selection, post-torrent, default provider', () async {
      expect(
        await ProviderCredentialPrefs.getRdEndpoint(),
        'https://api.real-debrid.com/rest/1.0',
      );
      expect(await ProviderCredentialPrefs.getFileSelection(), 'smart');
      expect(await ProviderCredentialPrefs.getPostTorrentAction(), 'choose');
      expect(await ProviderCredentialPrefs.getTorboxPostTorrentAction(), 'choose');
      expect(await ProviderCredentialPrefs.getPikPakPostTorrentAction(), 'choose');
      expect(await ProviderCredentialPrefs.getPremiumizePostTorrentAction(), 'choose');
      expect(await ProviderCredentialPrefs.getAllDebridPostTorrentAction(), 'choose');
      expect(await ProviderCredentialPrefs.getDefaultTorrentProvider(), 'none');
    });

    test('PikPak session and folder prefs', () async {
      expect(await ProviderCredentialPrefs.getPikPakAccessToken(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakRefreshToken(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakDeviceId(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakCaptchaToken(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakUserId(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakShowVideosOnly(), isTrue);
      expect(await ProviderCredentialPrefs.getPikPakIgnoreSmallVideos(), isTrue);
      expect(await ProviderCredentialPrefs.getPikPakRestrictedFolderId(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakRestrictedFolderName(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakTorrentsFolderId(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakTvFolderId(), isNull);
    });

    test('WebDAV prefs', () async {
      expect(await ProviderCredentialPrefs.getWebDavBaseUrl(), isNull);
      expect(await ProviderCredentialPrefs.getWebDavUsername(), isNull);
      expect(await ProviderCredentialPrefs.getWebDavPassword(), isNull);
      expect(await ProviderCredentialPrefs.getWebDavShowVideosOnly(), isTrue);
      expect(await ProviderCredentialPrefs.getWebDavServers(), isEmpty);
      expect(await ProviderCredentialPrefs.getSelectedWebDavServerId(), isNull);
      expect(await ProviderCredentialPrefs.getSelectedWebDavServer(), isNull);
    });
  });

  test('StorageService writes the historical settings key bytes', () async {
    await ProviderCredentialPrefs.saveRdEndpoint('https://app.real-debrid.com/rest/1.0');
    await ProviderCredentialPrefs.saveFileSelection('all');
    await ProviderCredentialPrefs.setTorboxCacheCheckEnabled(true);
    await ProviderCredentialPrefs.setRealDebridIntegrationEnabled(false);
    await ProviderCredentialPrefs.setRealDebridHiddenFromNav(true);
    await ProviderCredentialPrefs.setRdSkipBlockedTorrents(false);
    await ProviderCredentialPrefs.setTorboxIntegrationEnabled(false);
    await ProviderCredentialPrefs.setTorboxHiddenFromNav(true);
    await ProviderCredentialPrefs.setPremiumizeIntegrationEnabled(false);
    await ProviderCredentialPrefs.setPremiumizeHiddenFromNav(true);
    await ProviderCredentialPrefs.setPremiumizeCacheCheckEnabled(true);
    await ProviderCredentialPrefs.savePremiumizePostTorrentAction('delete');
    await ProviderCredentialPrefs.setAllDebridIntegrationEnabled(false);
    await ProviderCredentialPrefs.setAllDebridHiddenFromNav(true);
    await ProviderCredentialPrefs.saveAllDebridPostTorrentAction('keep');
    await ProviderCredentialPrefs.savePostTorrentAction('delete');
    await ProviderCredentialPrefs.saveTorboxPostTorrentAction('keep');
    await ProviderCredentialPrefs.savePikPakPostTorrentAction('delete');
    await ProviderCredentialPrefs.setPikPakEnabled(true);
    await ProviderCredentialPrefs.setPikPakHiddenFromNav(true);
    await ProviderCredentialPrefs.setPikPakShowVideosOnly(false);
    await ProviderCredentialPrefs.setPikPakIgnoreSmallVideos(false);
    await ProviderCredentialPrefs.setPikPakRestrictedFolder('fid', 'Restricted');
    await ProviderCredentialPrefs.setPikPakTorrentsFolderId('torrents-id');
    await ProviderCredentialPrefs.setPikPakTvFolderId('tv-id');
    await ProviderCredentialPrefs.setWebDavEnabled(true);
    await ProviderCredentialPrefs.setWebDavHiddenFromNav(true);
    await ProviderCredentialPrefs.setWebDavShowVideosOnly(false);
    await ProviderCredentialPrefs.setDefaultTorrentProvider('torbox');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('real_debrid_endpoint'),
      'https://app.real-debrid.com/rest/1.0',
    );
    expect(prefs.getString('real_debrid_file_selection'), 'all');
    expect(prefs.getBool('torbox_check_cache_before_search'), isTrue);
    expect(prefs.getBool('real_debrid_integration_enabled'), isFalse);
    expect(prefs.getBool('real_debrid_hidden_from_nav'), isTrue);
    expect(prefs.getBool('rd_skip_blocked_torrents'), isFalse);
    expect(prefs.getBool('torbox_integration_enabled'), isFalse);
    expect(prefs.getBool('torbox_hidden_from_nav'), isTrue);
    expect(prefs.getBool('premiumize_integration_enabled'), isFalse);
    expect(prefs.getBool('premiumize_hidden_from_nav'), isTrue);
    expect(prefs.getBool('premiumize_check_cache_before_search'), isTrue);
    expect(prefs.getString('premiumize_post_torrent_action'), 'delete');
    expect(prefs.getBool('alldebrid_integration_enabled'), isFalse);
    expect(prefs.getBool('alldebrid_hidden_from_nav'), isTrue);
    expect(prefs.getString('alldebrid_post_torrent_action'), 'keep');
    expect(prefs.getString('post_torrent_action'), 'delete');
    expect(prefs.getString('torbox_post_torrent_action'), 'keep');
    expect(prefs.getString('pikpak_post_torrent_action'), 'delete');
    expect(prefs.getBool('pikpak_enabled'), isTrue);
    expect(prefs.getBool('pikpak_hidden_from_nav'), isTrue);
    expect(prefs.getBool('pikpak_show_videos_only'), isFalse);
    expect(prefs.getBool('pikpak_ignore_small_videos'), isFalse);
    expect(prefs.getString('pikpak_restricted_folder_id'), 'fid');
    expect(prefs.getString('pikpak_restricted_folder_name'), 'Restricted');
    expect(prefs.getString('pikpak_torrents_folder_id'), 'torrents-id');
    expect(prefs.getString('pikpak_tv_folder_id'), 'tv-id');
    expect(prefs.getBool('webdav_enabled'), isTrue);
    expect(prefs.getBool('webdav_hidden_from_nav'), isTrue);
    expect(prefs.getBool('webdav_show_videos_only'), isFalse);
    expect(prefs.getString('default_torrent_provider_v1'), 'torbox');
  });

  test(
    'raw settings bytes round-trip through StorageService getters',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'real_debrid_endpoint': 'https://backup.example/rd',
        'real_debrid_file_selection': 'largest',
        'torbox_check_cache_before_search': true,
        'real_debrid_integration_enabled': false,
        'real_debrid_hidden_from_nav': true,
        'rd_skip_blocked_torrents': false,
        'torbox_integration_enabled': false,
        'torbox_hidden_from_nav': true,
        'premiumize_integration_enabled': false,
        'premiumize_hidden_from_nav': true,
        'premiumize_check_cache_before_search': true,
        'premiumize_post_torrent_action': 'delete',
        'alldebrid_integration_enabled': false,
        'alldebrid_hidden_from_nav': true,
        'alldebrid_post_torrent_action': 'keep',
        'post_torrent_action': 'delete',
        'torbox_post_torrent_action': 'keep',
        'pikpak_post_torrent_action': 'delete',
        'pikpak_enabled': true,
        'pikpak_hidden_from_nav': true,
        'pikpak_show_videos_only': false,
        'pikpak_ignore_small_videos': false,
        'pikpak_restricted_folder_id': 'r1',
        'pikpak_restricted_folder_name': 'R',
        'pikpak_torrents_folder_id': 't1',
        'pikpak_tv_folder_id': 'v1',
        'webdav_enabled': true,
        'webdav_hidden_from_nav': true,
        'webdav_show_videos_only': false,
        'default_torrent_provider_v1': 'debrid',
      });

      expect(await ProviderCredentialPrefs.getRdEndpoint(), 'https://backup.example/rd');
      expect(await ProviderCredentialPrefs.getFileSelection(), 'largest');
      expect(await ProviderCredentialPrefs.getTorboxCacheCheckEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getRealDebridIntegrationEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getRealDebridHiddenFromNav(), isTrue);
      expect(await ProviderCredentialPrefs.getRdSkipBlockedTorrents(), isFalse);
      expect(await ProviderCredentialPrefs.getTorboxIntegrationEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getTorboxHiddenFromNav(), isTrue);
      expect(await ProviderCredentialPrefs.getPremiumizeIntegrationEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getPremiumizeHiddenFromNav(), isTrue);
      expect(await ProviderCredentialPrefs.getPremiumizeCacheCheckEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getPremiumizePostTorrentAction(), 'delete');
      expect(await ProviderCredentialPrefs.getAllDebridIntegrationEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getAllDebridHiddenFromNav(), isTrue);
      expect(await ProviderCredentialPrefs.getAllDebridPostTorrentAction(), 'keep');
      expect(await ProviderCredentialPrefs.getPostTorrentAction(), 'delete');
      expect(await ProviderCredentialPrefs.getTorboxPostTorrentAction(), 'keep');
      expect(await ProviderCredentialPrefs.getPikPakPostTorrentAction(), 'delete');
      expect(await ProviderCredentialPrefs.getPikPakEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getPikPakHiddenFromNav(), isTrue);
      expect(await ProviderCredentialPrefs.getPikPakShowVideosOnly(), isFalse);
      expect(await ProviderCredentialPrefs.getPikPakIgnoreSmallVideos(), isFalse);
      expect(await ProviderCredentialPrefs.getPikPakRestrictedFolderId(), 'r1');
      expect(await ProviderCredentialPrefs.getPikPakRestrictedFolderName(), 'R');
      expect(await ProviderCredentialPrefs.getPikPakTorrentsFolderId(), 't1');
      expect(await ProviderCredentialPrefs.getPikPakTvFolderId(), 'v1');
      expect(await ProviderCredentialPrefs.getWebDavEnabled(), isTrue);
      expect(await ProviderCredentialPrefs.getWebDavHiddenFromNav(), isTrue);
      expect(await ProviderCredentialPrefs.getWebDavShowVideosOnly(), isFalse);
      expect(await ProviderCredentialPrefs.getDefaultTorrentProvider(), 'debrid');
    },
  );

  test('PikPak session tokens write through SecretVault', () async {
    await ProviderCredentialPrefs.setPikPakAccessToken('access-token');
    await ProviderCredentialPrefs.setPikPakRefreshToken('refresh-token');
    await ProviderCredentialPrefs.setPikPakDeviceId('device-1');
    await ProviderCredentialPrefs.setPikPakCaptchaToken('captcha-1');
    await ProviderCredentialPrefs.setPikPakUserId('user-1');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('pikpak_access_token'),
      startsWith(SecretVault.prefix),
    );
    expect(
      prefs.getString('pikpak_refresh_token'),
      startsWith(SecretVault.prefix),
    );
    expect(prefs.getString('pikpak_device_id'), startsWith(SecretVault.prefix));
    expect(
      prefs.getString('pikpak_captcha_token'),
      startsWith(SecretVault.prefix),
    );
    expect(prefs.getString('pikpak_user_id'), startsWith(SecretVault.prefix));

    expect(await ProviderCredentialPrefs.getPikPakAccessToken(), 'access-token');
    expect(await ProviderCredentialPrefs.getPikPakRefreshToken(), 'refresh-token');
    expect(await ProviderCredentialPrefs.getPikPakDeviceId(), 'device-1');
    expect(await ProviderCredentialPrefs.getPikPakCaptchaToken(), 'captcha-1');
    expect(await ProviderCredentialPrefs.getPikPakUserId(), 'user-1');
  });

  test(
    'clear helpers remove historical keys and keep PikPak out of integration clear',
    () async {
      await ProviderCredentialPrefs.setRealDebridIntegrationEnabled(false);
      await ProviderCredentialPrefs.setRealDebridHiddenFromNav(true);
      await ProviderCredentialPrefs.setTorboxIntegrationEnabled(false);
      await ProviderCredentialPrefs.setTorboxHiddenFromNav(true);
      await ProviderCredentialPrefs.setPremiumizeIntegrationEnabled(false);
      await ProviderCredentialPrefs.setPremiumizeHiddenFromNav(true);
      await ProviderCredentialPrefs.setAllDebridIntegrationEnabled(false);
      await ProviderCredentialPrefs.setAllDebridHiddenFromNav(true);
      await ProviderCredentialPrefs.setWebDavEnabled(true);
      await ProviderCredentialPrefs.setWebDavHiddenFromNav(true);
      await ProviderCredentialPrefs.setPikPakEnabled(true);
      await ProviderCredentialPrefs.setPikPakHiddenFromNav(true);
      await ProviderCredentialPrefs.savePostTorrentAction('delete');
      await ProviderCredentialPrefs.saveTorboxPostTorrentAction('keep');
      await ProviderCredentialPrefs.savePikPakPostTorrentAction('delete');
      await ProviderCredentialPrefs.savePremiumizePostTorrentAction('delete');
      await ProviderCredentialPrefs.saveAllDebridPostTorrentAction('keep');

      await ProviderCredentialPrefs.clearAllIntegrationStates();
      await ProviderCredentialPrefs.clearAllPostTorrentActions();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('real_debrid_integration_enabled'), isFalse);
      expect(prefs.containsKey('real_debrid_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('torbox_integration_enabled'), isFalse);
      expect(prefs.containsKey('torbox_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('premiumize_integration_enabled'), isFalse);
      expect(prefs.containsKey('premiumize_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('alldebrid_integration_enabled'), isFalse);
      expect(prefs.containsKey('alldebrid_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('webdav_enabled'), isFalse);
      expect(prefs.containsKey('webdav_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('post_torrent_action'), isFalse);
      expect(prefs.containsKey('torbox_post_torrent_action'), isFalse);
      expect(prefs.containsKey('pikpak_post_torrent_action'), isFalse);
      expect(prefs.containsKey('premiumize_post_torrent_action'), isFalse);
      expect(prefs.containsKey('alldebrid_post_torrent_action'), isFalse);
      // Quirk: integration clear does not touch PikPak enabled / hidden.
      expect(prefs.getBool('pikpak_enabled'), isTrue);
      expect(prefs.getBool('pikpak_hidden_from_nav'), isTrue);
    },
  );

  test(
    'hidden-from-nav clear removes the key; getters then default false',
    () async {
      await ProviderCredentialPrefs.setRealDebridHiddenFromNav(true);
      await ProviderCredentialPrefs.setTorboxHiddenFromNav(true);
      await ProviderCredentialPrefs.setPremiumizeHiddenFromNav(true);
      await ProviderCredentialPrefs.setAllDebridHiddenFromNav(true);
      await ProviderCredentialPrefs.setPikPakHiddenFromNav(true);
      await ProviderCredentialPrefs.setWebDavHiddenFromNav(true);

      await ProviderCredentialPrefs.clearRealDebridHiddenFromNav();
      await ProviderCredentialPrefs.clearTorboxHiddenFromNav();
      await ProviderCredentialPrefs.clearPremiumizeHiddenFromNav();
      await ProviderCredentialPrefs.clearAllDebridHiddenFromNav();
      await ProviderCredentialPrefs.clearPikPakHiddenFromNav();
      await ProviderCredentialPrefs.clearWebDavHiddenFromNav();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('real_debrid_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('torbox_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('premiumize_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('alldebrid_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('pikpak_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('webdav_hidden_from_nav'), isFalse);
      expect(await ProviderCredentialPrefs.getRealDebridHiddenFromNav(), isFalse);
    },
  );

  test('RD endpoint delete restores the primary default', () async {
    await ProviderCredentialPrefs.saveRdEndpoint('https://app.real-debrid.com/rest/1.0');
    await ProviderCredentialPrefs.deleteRdEndpoint();
    expect(
      await ProviderCredentialPrefs.getRdEndpoint(),
      'https://api.real-debrid.com/rest/1.0',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('real_debrid_endpoint'), isFalse);
  });

  test(
    'PikPak restricted folder null removes both keys; caches stay until clear',
    () async {
      await ProviderCredentialPrefs.setPikPakRestrictedFolder('fid', 'Name');
      await ProviderCredentialPrefs.setPikPakTorrentsFolderId('t');
      await ProviderCredentialPrefs.setPikPakTvFolderId('v');
      // Quirk: set(null) drops restriction keys only. Subfolder caches
      // leave until clearPikPakRestrictedFolder (which also clears caches).
      await ProviderCredentialPrefs.setPikPakRestrictedFolder(null, null);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('pikpak_restricted_folder_id'), isFalse);
      expect(prefs.containsKey('pikpak_restricted_folder_name'), isFalse);
      expect(prefs.getString('pikpak_torrents_folder_id'), 't');
      expect(prefs.getString('pikpak_tv_folder_id'), 'v');

      await ProviderCredentialPrefs.clearPikPakRestrictedFolder();
      expect(prefs.containsKey('pikpak_torrents_folder_id'), isFalse);
      expect(prefs.containsKey('pikpak_tv_folder_id'), isFalse);
    },
  );

  test(
    'clearPikPakAuth disables PikPak and drops session + folder keys',
    () async {
      await ProviderCredentialPrefs.setPikPakEnabled(true);
      await ProviderCredentialPrefs.setPikPakAccessToken('access-token');
      await ProviderCredentialPrefs.setPikPakRefreshToken('refresh-token');
      await ProviderCredentialPrefs.setPikPakDeviceId('device-1');
      await ProviderCredentialPrefs.setPikPakCaptchaToken('captcha-1');
      await ProviderCredentialPrefs.setPikPakUserId('user-1');
      await ProviderCredentialPrefs.setPikPakRestrictedFolder('fid', 'Name');
      await ProviderCredentialPrefs.setPikPakHiddenFromNav(true);

      await ProviderCredentialPrefs.clearPikPakAuth();

      expect(await ProviderCredentialPrefs.getPikPakEnabled(), isFalse);
      expect(await ProviderCredentialPrefs.getPikPakAccessToken(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakRefreshToken(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakDeviceId(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakCaptchaToken(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakUserId(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakRestrictedFolderId(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakHiddenFromNav(), isFalse);
    },
  );

  test('WebDAV legacy single-server keys promote into servers_v1', () async {
    await ProviderCredentialPrefs.setWebDavBaseUrl('https://dav.example/');
    await ProviderCredentialPrefs.setWebDavUsername('alice');
    await ProviderCredentialPrefs.setWebDavPassword('s3cret');

    final servers = await ProviderCredentialPrefs.getWebDavServers();
    expect(servers, hasLength(1));
    expect(servers.first.baseUrl, 'https://dav.example/');
    expect(servers.first.username, 'alice');
    expect(servers.first.password, 's3cret');
    expect(servers.first.name, 'dav.example');
    expect(await ProviderCredentialPrefs.getSelectedWebDavServerId(), servers.first.id);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webdav_base_url'), startsWith(SecretVault.prefix));
    expect(prefs.getString('webdav_username'), startsWith(SecretVault.prefix));
    expect(prefs.getString('webdav_password'), startsWith(SecretVault.prefix));
    expect(
      prefs.getString('webdav_servers_v1'),
      startsWith(SecretVault.prefix),
    );
    expect(prefs.getString('webdav_selected_server_id_v1'), servers.first.id);
  });

  test('saveWebDavServers writes enabled from list emptiness', () async {
    final saved = await ProviderCredentialPrefs.saveWebDavServers(const [
      WebDavConfig(
        id: 's1',
        name: 'Home',
        baseUrl: 'https://a.example/',
        username: 'u',
        password: 'p',
      ),
    ]);
    expect(saved, hasLength(1));
    expect(await ProviderCredentialPrefs.getWebDavEnabled(), isTrue);

    await ProviderCredentialPrefs.saveWebDavServers(const []);
    expect(await ProviderCredentialPrefs.getWebDavEnabled(), isFalse);
  });

  test(
    'deleteWebDavServer of the last server clears hidden-from-nav',
    () async {
      final created = await ProviderCredentialPrefs.upsertWebDavServer(
        const WebDavConfig(
          id: 'gone',
          name: 'Temp',
          baseUrl: 'https://tmp.example/',
          username: 'u',
          password: 'p',
        ),
      );
      await ProviderCredentialPrefs.setWebDavHiddenFromNav(true);
      await ProviderCredentialPrefs.deleteWebDavServer(created.id);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('webdav_selected_server_id_v1'), isFalse);
      expect(prefs.getBool('webdav_hidden_from_nav'), isFalse);
      expect(await ProviderCredentialPrefs.getWebDavServers(), isEmpty);
    },
  );

  test('setSelectedWebDavServerId null or empty removes the key', () async {
    await ProviderCredentialPrefs.setSelectedWebDavServerId('abc');
    await ProviderCredentialPrefs.setSelectedWebDavServerId(null);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('webdav_selected_server_id_v1'), isFalse);

    await ProviderCredentialPrefs.setSelectedWebDavServerId('abc');
    await ProviderCredentialPrefs.setSelectedWebDavServerId('');
    prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('webdav_selected_server_id_v1'), isFalse);
  });

  test('clearWebDav drops connection keys and disables the provider', () async {
    await ProviderCredentialPrefs.setWebDavBaseUrl('https://dav.example/');
    await ProviderCredentialPrefs.setWebDavEnabled(true);
    await ProviderCredentialPrefs.setWebDavHiddenFromNav(true);
    await ProviderCredentialPrefs.clearWebDav();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('webdav_base_url'), isFalse);
    expect(prefs.containsKey('webdav_username'), isFalse);
    expect(prefs.containsKey('webdav_password'), isFalse);
    expect(prefs.containsKey('webdav_hidden_from_nav'), isFalse);
    expect(prefs.containsKey('webdav_servers_v1'), isFalse);
    expect(prefs.containsKey('webdav_selected_server_id_v1'), isFalse);
    expect(prefs.getBool('webdav_enabled'), isFalse);
  });

  test(
    'clearDefaultTorrentProvider removes the key; getter reads none',
    () async {
      await ProviderCredentialPrefs.setDefaultTorrentProvider('pikpak');
      await ProviderCredentialPrefs.clearDefaultTorrentProvider();
      expect(await ProviderCredentialPrefs.getDefaultTorrentProvider(), 'none');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('default_torrent_provider_v1'), isFalse);
    },
  );

  test(
    'clearPikPakCaptchaToken and deletePikPakDeviceId remove those keys',
    () async {
      await ProviderCredentialPrefs.setPikPakCaptchaToken('c');
      await ProviderCredentialPrefs.setPikPakDeviceId('d');
      await ProviderCredentialPrefs.clearPikPakCaptchaToken();
      await ProviderCredentialPrefs.deletePikPakDeviceId();
      expect(await ProviderCredentialPrefs.getPikPakCaptchaToken(), isNull);
      expect(await ProviderCredentialPrefs.getPikPakDeviceId(), isNull);
    },
  );
}
