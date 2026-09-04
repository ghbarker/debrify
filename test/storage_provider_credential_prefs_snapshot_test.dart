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
      expect(await StorageService.getRealDebridIntegrationEnabled(), isTrue);
      expect(await StorageService.getTorboxIntegrationEnabled(), isTrue);
      expect(await StorageService.getPremiumizeIntegrationEnabled(), isTrue);
      expect(await StorageService.getAllDebridIntegrationEnabled(), isTrue);
      expect(await StorageService.getPikPakEnabled(), isFalse);
      expect(await StorageService.getWebDavEnabled(), isFalse);

      expect(await StorageService.getRealDebridHiddenFromNav(), isFalse);
      expect(await StorageService.getTorboxHiddenFromNav(), isFalse);
      expect(await StorageService.getPremiumizeHiddenFromNav(), isFalse);
      expect(await StorageService.getAllDebridHiddenFromNav(), isFalse);
      expect(await StorageService.getPikPakHiddenFromNav(), isFalse);
      expect(await StorageService.getWebDavHiddenFromNav(), isFalse);

      expect(await StorageService.getTorboxCacheCheckEnabled(), isFalse);
      expect(await StorageService.getPremiumizeCacheCheckEnabled(), isFalse);
      expect(await StorageService.getRdSkipBlockedTorrents(), isTrue);
    });

    test('endpoint, file selection, post-torrent, default provider', () async {
      expect(
        await StorageService.getRdEndpoint(),
        'https://api.real-debrid.com/rest/1.0',
      );
      expect(await StorageService.getFileSelection(), 'smart');
      expect(await StorageService.getPostTorrentAction(), 'choose');
      expect(await StorageService.getTorboxPostTorrentAction(), 'choose');
      expect(await StorageService.getPikPakPostTorrentAction(), 'choose');
      expect(await StorageService.getPremiumizePostTorrentAction(), 'choose');
      expect(await StorageService.getAllDebridPostTorrentAction(), 'choose');
      expect(await StorageService.getDefaultTorrentProvider(), 'none');
    });

    test('PikPak session and folder prefs', () async {
      expect(await StorageService.getPikPakAccessToken(), isNull);
      expect(await StorageService.getPikPakRefreshToken(), isNull);
      expect(await StorageService.getPikPakDeviceId(), isNull);
      expect(await StorageService.getPikPakCaptchaToken(), isNull);
      expect(await StorageService.getPikPakUserId(), isNull);
      expect(await StorageService.getPikPakShowVideosOnly(), isTrue);
      expect(await StorageService.getPikPakIgnoreSmallVideos(), isTrue);
      expect(await StorageService.getPikPakRestrictedFolderId(), isNull);
      expect(await StorageService.getPikPakRestrictedFolderName(), isNull);
      expect(await StorageService.getPikPakTorrentsFolderId(), isNull);
      expect(await StorageService.getPikPakTvFolderId(), isNull);
    });

    test('WebDAV prefs', () async {
      expect(await StorageService.getWebDavBaseUrl(), isNull);
      expect(await StorageService.getWebDavUsername(), isNull);
      expect(await StorageService.getWebDavPassword(), isNull);
      expect(await StorageService.getWebDavShowVideosOnly(), isTrue);
      expect(await StorageService.getWebDavServers(), isEmpty);
      expect(await StorageService.getSelectedWebDavServerId(), isNull);
      expect(await StorageService.getSelectedWebDavServer(), isNull);
    });
  });

  test('StorageService writes the historical settings key bytes', () async {
    await StorageService.saveRdEndpoint('https://app.real-debrid.com/rest/1.0');
    await StorageService.saveFileSelection('all');
    await StorageService.setTorboxCacheCheckEnabled(true);
    await StorageService.setRealDebridIntegrationEnabled(false);
    await StorageService.setRealDebridHiddenFromNav(true);
    await StorageService.setRdSkipBlockedTorrents(false);
    await StorageService.setTorboxIntegrationEnabled(false);
    await StorageService.setTorboxHiddenFromNav(true);
    await StorageService.setPremiumizeIntegrationEnabled(false);
    await StorageService.setPremiumizeHiddenFromNav(true);
    await StorageService.setPremiumizeCacheCheckEnabled(true);
    await StorageService.savePremiumizePostTorrentAction('delete');
    await StorageService.setAllDebridIntegrationEnabled(false);
    await StorageService.setAllDebridHiddenFromNav(true);
    await StorageService.saveAllDebridPostTorrentAction('keep');
    await StorageService.savePostTorrentAction('delete');
    await StorageService.saveTorboxPostTorrentAction('keep');
    await StorageService.savePikPakPostTorrentAction('delete');
    await StorageService.setPikPakEnabled(true);
    await StorageService.setPikPakHiddenFromNav(true);
    await StorageService.setPikPakShowVideosOnly(false);
    await StorageService.setPikPakIgnoreSmallVideos(false);
    await StorageService.setPikPakRestrictedFolder('fid', 'Restricted');
    await StorageService.setPikPakTorrentsFolderId('torrents-id');
    await StorageService.setPikPakTvFolderId('tv-id');
    await StorageService.setWebDavEnabled(true);
    await StorageService.setWebDavHiddenFromNav(true);
    await StorageService.setWebDavShowVideosOnly(false);
    await StorageService.setDefaultTorrentProvider('torbox');

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

      expect(await StorageService.getRdEndpoint(), 'https://backup.example/rd');
      expect(await StorageService.getFileSelection(), 'largest');
      expect(await StorageService.getTorboxCacheCheckEnabled(), isTrue);
      expect(await StorageService.getRealDebridIntegrationEnabled(), isFalse);
      expect(await StorageService.getRealDebridHiddenFromNav(), isTrue);
      expect(await StorageService.getRdSkipBlockedTorrents(), isFalse);
      expect(await StorageService.getTorboxIntegrationEnabled(), isFalse);
      expect(await StorageService.getTorboxHiddenFromNav(), isTrue);
      expect(await StorageService.getPremiumizeIntegrationEnabled(), isFalse);
      expect(await StorageService.getPremiumizeHiddenFromNav(), isTrue);
      expect(await StorageService.getPremiumizeCacheCheckEnabled(), isTrue);
      expect(await StorageService.getPremiumizePostTorrentAction(), 'delete');
      expect(await StorageService.getAllDebridIntegrationEnabled(), isFalse);
      expect(await StorageService.getAllDebridHiddenFromNav(), isTrue);
      expect(await StorageService.getAllDebridPostTorrentAction(), 'keep');
      expect(await StorageService.getPostTorrentAction(), 'delete');
      expect(await StorageService.getTorboxPostTorrentAction(), 'keep');
      expect(await StorageService.getPikPakPostTorrentAction(), 'delete');
      expect(await StorageService.getPikPakEnabled(), isTrue);
      expect(await StorageService.getPikPakHiddenFromNav(), isTrue);
      expect(await StorageService.getPikPakShowVideosOnly(), isFalse);
      expect(await StorageService.getPikPakIgnoreSmallVideos(), isFalse);
      expect(await StorageService.getPikPakRestrictedFolderId(), 'r1');
      expect(await StorageService.getPikPakRestrictedFolderName(), 'R');
      expect(await StorageService.getPikPakTorrentsFolderId(), 't1');
      expect(await StorageService.getPikPakTvFolderId(), 'v1');
      expect(await StorageService.getWebDavEnabled(), isTrue);
      expect(await StorageService.getWebDavHiddenFromNav(), isTrue);
      expect(await StorageService.getWebDavShowVideosOnly(), isFalse);
      expect(await StorageService.getDefaultTorrentProvider(), 'debrid');
    },
  );

  test('PikPak session tokens write through SecretVault', () async {
    await StorageService.setPikPakAccessToken('access-token');
    await StorageService.setPikPakRefreshToken('refresh-token');
    await StorageService.setPikPakDeviceId('device-1');
    await StorageService.setPikPakCaptchaToken('captcha-1');
    await StorageService.setPikPakUserId('user-1');

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

    expect(await StorageService.getPikPakAccessToken(), 'access-token');
    expect(await StorageService.getPikPakRefreshToken(), 'refresh-token');
    expect(await StorageService.getPikPakDeviceId(), 'device-1');
    expect(await StorageService.getPikPakCaptchaToken(), 'captcha-1');
    expect(await StorageService.getPikPakUserId(), 'user-1');
  });

  test(
    'clear helpers remove historical keys and keep PikPak out of integration clear',
    () async {
      await StorageService.setRealDebridIntegrationEnabled(false);
      await StorageService.setRealDebridHiddenFromNav(true);
      await StorageService.setTorboxIntegrationEnabled(false);
      await StorageService.setTorboxHiddenFromNav(true);
      await StorageService.setPremiumizeIntegrationEnabled(false);
      await StorageService.setPremiumizeHiddenFromNav(true);
      await StorageService.setAllDebridIntegrationEnabled(false);
      await StorageService.setAllDebridHiddenFromNav(true);
      await StorageService.setWebDavEnabled(true);
      await StorageService.setWebDavHiddenFromNav(true);
      await StorageService.setPikPakEnabled(true);
      await StorageService.setPikPakHiddenFromNav(true);
      await StorageService.savePostTorrentAction('delete');
      await StorageService.saveTorboxPostTorrentAction('keep');
      await StorageService.savePikPakPostTorrentAction('delete');
      await StorageService.savePremiumizePostTorrentAction('delete');
      await StorageService.saveAllDebridPostTorrentAction('keep');

      await StorageService.clearAllIntegrationStates();
      await StorageService.clearAllPostTorrentActions();

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
      await StorageService.setRealDebridHiddenFromNav(true);
      await StorageService.setTorboxHiddenFromNav(true);
      await StorageService.setPremiumizeHiddenFromNav(true);
      await StorageService.setAllDebridHiddenFromNav(true);
      await StorageService.setPikPakHiddenFromNav(true);
      await StorageService.setWebDavHiddenFromNav(true);

      await StorageService.clearRealDebridHiddenFromNav();
      await StorageService.clearTorboxHiddenFromNav();
      await StorageService.clearPremiumizeHiddenFromNav();
      await StorageService.clearAllDebridHiddenFromNav();
      await StorageService.clearPikPakHiddenFromNav();
      await StorageService.clearWebDavHiddenFromNav();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('real_debrid_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('torbox_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('premiumize_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('alldebrid_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('pikpak_hidden_from_nav'), isFalse);
      expect(prefs.containsKey('webdav_hidden_from_nav'), isFalse);
      expect(await StorageService.getRealDebridHiddenFromNav(), isFalse);
    },
  );

  test('RD endpoint delete restores the primary default', () async {
    await StorageService.saveRdEndpoint('https://app.real-debrid.com/rest/1.0');
    await StorageService.deleteRdEndpoint();
    expect(
      await StorageService.getRdEndpoint(),
      'https://api.real-debrid.com/rest/1.0',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('real_debrid_endpoint'), isFalse);
  });

  test(
    'PikPak restricted folder null removes both keys; caches stay until clear',
    () async {
      await StorageService.setPikPakRestrictedFolder('fid', 'Name');
      await StorageService.setPikPakTorrentsFolderId('t');
      await StorageService.setPikPakTvFolderId('v');
      // Quirk: set(null) drops restriction keys only. Subfolder caches
      // leave until clearPikPakRestrictedFolder (which also clears caches).
      await StorageService.setPikPakRestrictedFolder(null, null);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('pikpak_restricted_folder_id'), isFalse);
      expect(prefs.containsKey('pikpak_restricted_folder_name'), isFalse);
      expect(prefs.getString('pikpak_torrents_folder_id'), 't');
      expect(prefs.getString('pikpak_tv_folder_id'), 'v');

      await StorageService.clearPikPakRestrictedFolder();
      expect(prefs.containsKey('pikpak_torrents_folder_id'), isFalse);
      expect(prefs.containsKey('pikpak_tv_folder_id'), isFalse);
    },
  );

  test(
    'clearPikPakAuth disables PikPak and drops session + folder keys',
    () async {
      await StorageService.setPikPakEnabled(true);
      await StorageService.setPikPakAccessToken('access-token');
      await StorageService.setPikPakRefreshToken('refresh-token');
      await StorageService.setPikPakDeviceId('device-1');
      await StorageService.setPikPakCaptchaToken('captcha-1');
      await StorageService.setPikPakUserId('user-1');
      await StorageService.setPikPakRestrictedFolder('fid', 'Name');
      await StorageService.setPikPakHiddenFromNav(true);

      await StorageService.clearPikPakAuth();

      expect(await StorageService.getPikPakEnabled(), isFalse);
      expect(await StorageService.getPikPakAccessToken(), isNull);
      expect(await StorageService.getPikPakRefreshToken(), isNull);
      expect(await StorageService.getPikPakDeviceId(), isNull);
      expect(await StorageService.getPikPakCaptchaToken(), isNull);
      expect(await StorageService.getPikPakUserId(), isNull);
      expect(await StorageService.getPikPakRestrictedFolderId(), isNull);
      expect(await StorageService.getPikPakHiddenFromNav(), isFalse);
    },
  );

  test('WebDAV legacy single-server keys promote into servers_v1', () async {
    await StorageService.setWebDavBaseUrl('https://dav.example/');
    await StorageService.setWebDavUsername('alice');
    await StorageService.setWebDavPassword('s3cret');

    final servers = await StorageService.getWebDavServers();
    expect(servers, hasLength(1));
    expect(servers.first.baseUrl, 'https://dav.example/');
    expect(servers.first.username, 'alice');
    expect(servers.first.password, 's3cret');
    expect(servers.first.name, 'dav.example');
    expect(await StorageService.getSelectedWebDavServerId(), servers.first.id);

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
    final saved = await StorageService.saveWebDavServers(const [
      WebDavConfig(
        id: 's1',
        name: 'Home',
        baseUrl: 'https://a.example/',
        username: 'u',
        password: 'p',
      ),
    ]);
    expect(saved, hasLength(1));
    expect(await StorageService.getWebDavEnabled(), isTrue);

    await StorageService.saveWebDavServers(const []);
    expect(await StorageService.getWebDavEnabled(), isFalse);
  });

  test(
    'deleteWebDavServer of the last server clears hidden-from-nav',
    () async {
      final created = await StorageService.upsertWebDavServer(
        const WebDavConfig(
          id: 'gone',
          name: 'Temp',
          baseUrl: 'https://tmp.example/',
          username: 'u',
          password: 'p',
        ),
      );
      await StorageService.setWebDavHiddenFromNav(true);
      await StorageService.deleteWebDavServer(created.id);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('webdav_selected_server_id_v1'), isFalse);
      expect(prefs.getBool('webdav_hidden_from_nav'), isFalse);
      expect(await StorageService.getWebDavServers(), isEmpty);
    },
  );

  test('setSelectedWebDavServerId null or empty removes the key', () async {
    await StorageService.setSelectedWebDavServerId('abc');
    await StorageService.setSelectedWebDavServerId(null);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('webdav_selected_server_id_v1'), isFalse);

    await StorageService.setSelectedWebDavServerId('abc');
    await StorageService.setSelectedWebDavServerId('');
    prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('webdav_selected_server_id_v1'), isFalse);
  });

  test('clearWebDav drops connection keys and disables the provider', () async {
    await StorageService.setWebDavBaseUrl('https://dav.example/');
    await StorageService.setWebDavEnabled(true);
    await StorageService.setWebDavHiddenFromNav(true);
    await StorageService.clearWebDav();

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
      await StorageService.setDefaultTorrentProvider('pikpak');
      await StorageService.clearDefaultTorrentProvider();
      expect(await StorageService.getDefaultTorrentProvider(), 'none');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('default_torrent_provider_v1'), isFalse);
    },
  );

  test(
    'clearPikPakCaptchaToken and deletePikPakDeviceId remove those keys',
    () async {
      await StorageService.setPikPakCaptchaToken('c');
      await StorageService.setPikPakDeviceId('d');
      await StorageService.clearPikPakCaptchaToken();
      await StorageService.deletePikPakDeviceId();
      expect(await StorageService.getPikPakCaptchaToken(), isNull);
      expect(await StorageService.getPikPakDeviceId(), isNull);
    },
  );
}
