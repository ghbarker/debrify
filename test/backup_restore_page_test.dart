import 'dart:io';

import 'package:debrify/screens/settings/backup_restore_page.dart';
import 'package:debrify/services/backup_restore_service.dart';
import 'package:flutter_test/flutter_test.dart';

BackupSummary summary({
  bool hasRealDebrid = false,
  bool hasTorbox = false,
  bool hasPremiumize = false,
  bool hasAllDebrid = false,
  bool hasPikpak = false,
  bool hasTrakt = false,
  bool hasSimkl = false,
  bool hasMdblist = false,
  int searchEngineCount = 0,
  int addonCount = 0,
  int webDavServerCount = 0,
  int indexerManagerCount = 0,
  int iptvPlaylistCount = 0,
  int iptvFavoriteCount = 0,
  int iptvListCount = 0,
  int iptvListChannelCount = 0,
  int homeCollectionCount = 0,
  int streamBadgeSourceCount = 0,
}) {
  return BackupSummary(
    version: 1,
    createdAt: '2026-09-04T00:00:00.000Z',
    hasRealDebrid: hasRealDebrid,
    hasTorbox: hasTorbox,
    hasPremiumize: hasPremiumize,
    hasAllDebrid: hasAllDebrid,
    hasPikpak: hasPikpak,
    hasTrakt: hasTrakt,
    hasSimkl: hasSimkl,
    hasMdblist: hasMdblist,
    searchEngineCount: searchEngineCount,
    addonCount: addonCount,
    webDavServerCount: webDavServerCount,
    indexerManagerCount: indexerManagerCount,
    iptvPlaylistCount: iptvPlaylistCount,
    iptvFavoriteCount: iptvFavoriteCount,
    iptvListCount: iptvListCount,
    iptvListChannelCount: iptvListChannelCount,
    homeCollectionCount: homeCollectionCount,
    streamBadgeSourceCount: streamBadgeSourceCount,
  );
}

void main() {
  group('backupSummaryLines', () {
    test('empty summary yields no bullets', () {
      expect(backupSummaryLines(summary()), isEmpty);
    });

    test('provider labels keep today\'s names and order', () {
      expect(
        backupSummaryLines(
          summary(
            hasRealDebrid: true,
            hasTorbox: true,
            hasPremiumize: true,
            hasAllDebrid: true,
            hasPikpak: true,
            hasTrakt: true,
            hasSimkl: true,
            hasMdblist: true,
            searchEngineCount: 2,
            addonCount: 3,
            webDavServerCount: 1,
            indexerManagerCount: 4,
            iptvPlaylistCount: 5,
            iptvFavoriteCount: 6,
            iptvListCount: 7,
            iptvListChannelCount: 8,
            homeCollectionCount: 9,
            streamBadgeSourceCount: 10,
          ),
        ),
        [
          'Real-Debrid',
          'Torbox',
          'Premiumize',
          'AllDebrid',
          'PikPak',
          'Trakt',
          'Simkl',
          'MDBList',
          'Search engines (2)',
          'Stremio addons (3)',
          'WebDAV servers (1)',
          'Jackett/Prowlarr (4)',
          'IPTV providers (5)',
          'IPTV favorites (6 channels)',
          'IPTV lists (7, 8 channels)',
          'Collections (9)',
          'Stream badge rulesets (10)',
        ],
      );
    });

    test(
      'zero counts omit their lines even when other categories are present',
      () {
        expect(backupSummaryLines(summary(hasTrakt: true, addonCount: 1)), [
          'Trakt',
          'Stremio addons (1)',
        ]);
      },
    );
  });

  group('formatRestoreReport', () {
    test('empty success is the already-present copy, not Restore finished', () {
      expect(
        formatRestoreReport(RestoreReport()),
        'Nothing new to restore — everything was already present',
      );
    });

    test('success parts keep today\'s names, order, and Restored: prefix', () {
      final r = RestoreReport()
        ..realDebrid = true
        ..torbox = true
        ..premiumize = true
        ..allDebrid = true
        ..pikpak = true
        ..trakt = true
        ..simkl = true
        ..mdblist = true
        ..searchEnginesImported = 2
        ..addonsImported = 3
        ..webDavServersImported = 1
        ..indexerManagersImported = 4
        ..iptvPlaylistsImported = 5
        ..iptvFavoritesImported = 6
        ..iptvListsCreated = 7
        ..iptvListChannelsImported = 8
        ..homeCollectionsImported = 9
        ..streamBadgeSourcesImported = 10;
      expect(
        formatRestoreReport(r),
        'Restored: Real-Debrid, Torbox, Premiumize, AllDebrid, PikPak, '
        'Trakt, Simkl, MDBList, 2 new engine(s), 3 new addon(s), '
        '1 WebDAV server(s), 4 indexer manager(s), 5 IPTV provider(s), '
        '6 favorite channel(s), 7 IPTV list(s), 8 list channel(s), '
        '9 collection(s), 10 badge ruleset(s)',
      );
    });

    test('already-present notes wrap the base in parentheses', () {
      final r = RestoreReport()
        ..trakt = true
        ..searchEnginesAlreadyPresent = 2
        ..addonsAlreadyPresent = 3
        ..webDavServersAlreadyPresent = 1
        ..indexerManagersAlreadyPresent = 4
        ..iptvPlaylistsAlreadyPresent = 5
        ..iptvFavoritesAlreadyPresent = 6
        ..iptvListsMerged = 7;
      expect(
        formatRestoreReport(r),
        'Restored: Trakt (2 engine(s) already present, '
        '3 addon(s) already present, '
        '1 WebDAV server(s) already present, '
        '4 indexer manager(s) already present, '
        '5 IPTV provider(s) already present, '
        '6 favorite(s) already present, '
        '7 existing list(s) topped up)',
      );
    });

    test('PikPak login-failed copy keeps credentials-saved wording', () {
      final r = RestoreReport()
        ..pikpak = true
        ..pikpakLoginFailed = true;
      expect(
        formatRestoreReport(r),
        'Restored: PikPak — failed: PikPak login (credentials saved — '
        'retry from PikPak settings)',
      );
    });

    test('IPTV list failures keep the entr(ies) spelling', () {
      final r = RestoreReport()..iptvListsFailed = 2;
      expect(
        formatRestoreReport(r),
        'Restore finished — failed: 2 IPTV list entr(ies)',
      );
    });

    test('homeCollectionsFailed and streamBadgeSourcesFailed are omitted', () {
      // Quirk: those two counters exist on RestoreReport and feed hasAnyFailure
      // via totalFailed, but the snackbar failed-list never names them. Keep it.
      final r = RestoreReport()
        ..homeCollectionsFailed = 3
        ..streamBadgeSourcesFailed = 4;
      expect(r.hasAnyFailure, isTrue);
      expect(formatRestoreReport(r), 'Restore finished — failed: ');
    });

    test('inline errors append after category failures', () {
      final r = RestoreReport()
        ..addonsFailed = 1
        ..errors.add('boom');
      expect(
        formatRestoreReport(r),
        'Restore finished — failed: 1 addon(s), boom',
      );
    });
  });

  group('backupExportFileName', () {
    test('uses local wall-clock fields, not UTC, with no seconds', () {
      final ts = DateTime(2026, 9, 4, 16, 7, 59);
      expect(backupExportFileName(ts), 'debrify-backup-20260904-1607.json');
    });

    test('pads single-digit month day hour minute', () {
      final ts = DateTime(2026, 1, 2, 3, 4);
      expect(backupExportFileName(ts), 'debrify-backup-20260102-0304.json');
    });
  });

  group('create/restore UI quirks still in the moved body', () {
    late String src;

    setUpAll(() {
      src = File(
        'lib/screens/settings/backup_restore_page.dart',
      ).readAsStringSync();
    });

    test('restore picks FileType.any and caps at 40 MiB', () {
      expect(src.contains('FileType.any'), isTrue);
      expect(src.contains('file.size > 40 * 1024 * 1024'), isTrue);
      expect(src.contains('maxBytes: 40 * 1024 * 1024'), isTrue);
    });

    test('profile-package detect accepts both JSON spacings', () {
      expect(src.contains(r'"format":"debrify-profile-package"'), isTrue);
      expect(src.contains(r'"format": "debrify-profile-package"'), isTrue);
    });

    test(
      'profile-committed create/restore still delegate to ProfileBackupFlows',
      () {
        expect(
          src.contains(
            'ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted',
          ),
          isTrue,
        );
        expect(
          src.contains('ProfileBackupFlows(context).createProfileBackup()'),
          isTrue,
        );
        expect(src.contains('.restoreProfileBackup()'), isTrue);
      },
    );

    test('encrypt captures the root navigator before the KDF await', () {
      expect(
        src.contains(
          'final rootNavigator = Navigator.of(context, rootNavigator: true);',
        ),
        isTrue,
      );
      expect(src.contains('Encrypting backup…'), isTrue);
      expect(src.contains("Wrong passphrase — try again"), isTrue);
    });

    test('stripping credentials can still leave an empty backup', () {
      expect(
        src.contains(
          'Nothing left to back up without credentials — everything on ',
        ),
        isTrue,
      );
    });
  });
}
