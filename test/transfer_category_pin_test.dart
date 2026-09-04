import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins today's backup/transfer category behaviour before the T1 registry
/// move: named-constructor defaults (the default-on quirk), summarize counts,
/// and homeCollections / streamBadges apply.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(ProfileRuntime.debugReset);

  test('named BackupSelection defaults mdblist/IPTV/collections/badges on', () {
    const selection = BackupSelection(
      realDebrid: false,
      torbox: false,
      premiumize: false,
      allDebrid: false,
      pikpak: false,
      trakt: false,
      simkl: false,
      searchEngines: false,
      addons: false,
      webDav: false,
      indexerManagers: false,
    );
    expect(selection.mdblist, isTrue);
    expect(selection.iptvPlaylists, isTrue);
    expect(selection.iptvFavorites, isTrue);
    expect(selection.iptvLists, isTrue);
    expect(selection.homeCollections, isTrue);
    expect(selection.streamBadges, isTrue);
    expect(selection.trackingPreferences, isFalse);
  });

  test('BackupSelection.all includes homeCollections and streamBadges', () {
    final selection = BackupSelection.all();
    expect(selection.homeCollections, isTrue);
    expect(selection.streamBadges, isTrue);
    expect(selection.trackingPreferences, isTrue);
  });

  test('summarize counts homeCollections and streamBadges as today', () {
    final summary = BackupRestoreService.summarize(<String, dynamic>{
      'version': 1,
      'homeCollections': [
        {'id': 'c1', 'title': 'Mine', 'folders': <Object>[]},
        {'id': 'c2', 'title': 'Yours', 'folders': <Object>[]},
      ],
      'streamBadges': [
        {'id': 'b1', 'name': 'One', 'json': '{}'},
      ],
    });
    expect(summary.homeCollectionCount, 2);
    expect(summary.streamBadgeSourceCount, 1);
    expect(summary.isEmpty, isFalse);
  });

  test('applyBackup restores homeCollections and streamBadges', () async {
    final report = await BackupRestoreService.applyBackup(<String, dynamic>{
      'homeCollections': [
        {'id': 'col-1', 'title': 'Pinned', 'folders': <Object>[]},
      ],
      'streamBadges': [
        {
          'id': 'badge-1',
          'name': 'Preset',
          'json': '{"groups":[],"filters":[]}',
        },
      ],
    });
    expect(report.homeCollectionsImported, 1);
    expect(report.streamBadgeSourcesImported, 1);

    final collections = await HomeCollectionsStore.instance.getCollections();
    expect(collections.single.id, 'col-1');
    expect(collections.single.title, 'Pinned');

    final badges = await StreamBadgesService.instance.getSources();
    expect(badges.single.id, 'badge-1');
    expect(badges.single.name, 'Preset');
  });

  test('ConfigCommand strings for transfer categories are frozen', () {
    expect(ConfigCommand.realDebrid, 'real_debrid');
    expect(ConfigCommand.torbox, 'torbox');
    expect(ConfigCommand.premiumize, 'premiumize');
    expect(ConfigCommand.allDebrid, 'alldebrid');
    expect(ConfigCommand.pikpak, 'pikpak');
    expect(ConfigCommand.trakt, 'trakt');
    expect(ConfigCommand.simkl, 'simkl');
    expect(ConfigCommand.mdblist, 'mdblist');
    expect(ConfigCommand.trackingPreferences, 'tracking_preferences');
    expect(ConfigCommand.searchEngines, 'search_engines');
    expect(ConfigCommand.webDav, 'webdav');
    expect(ConfigCommand.indexerManagers, 'indexer_managers');
    expect(ConfigCommand.iptvPlaylists, 'iptv_playlists');
    expect(ConfigCommand.iptvFavorites, 'iptv_favorites');
    expect(ConfigCommand.iptvLists, 'iptv_lists');
    expect(ConfigCommand.streamBadges, 'stream_badges');
  });
}
