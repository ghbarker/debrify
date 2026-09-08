import 'dart:io';

import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins today's settings information architecture after the settings-menu
/// reorg. Order is a user-visible quirk: a page that jumps a section, or a
/// rail that reorders categories, is a behaviour change.
///
/// The three layouts and search all read [kSettingsCategories] /
/// [buildSettingsPages]; this file asserts the same lists the pre-move
/// source pin covered.
void main() {
  late SettingsPageRegistry registry;

  setUpAll(() {
    registry = SettingsPageRegistry(
      pages: buildSettingsPages(
        SettingsPageBindings.noop(
          showSwitchProfile: true,
          downloadLocationSupported: true,
          diagnosticExportVisible: true,
        ),
      ),
    );
  });

  test('the rail categories stay in todays order', () {
    expect(
      [for (final c in kSettingsCategories) c.label],
      kSettingsCategoryOrder,
    );
  });

  // Search, Playback and Live TV & DVR dissolved into Connections — Storage
  // Providers, then Search & Playback, then IPTV, then Tracking.
  const kConnectionsOrder = [
    'realDebrid',
    'torbox',
    'premiumize',
    'allDebrid',
    'pikpak',
    'webDav',
    'indexerManagers',
    'searchSettings',
    'filterSettings',
    'providerSettings',
    'quickPlay',
    'player',
    'iptvPlaylists',
    'iptvLists',
    'startupChannel',
    'iptvContinueWatching',
    'debrifyTv',
    'recordings',
    'tracking',
    'trakt',
    'simkl',
    // mdblist omitted — hidden behind mdblistEnabled, off by default here.
  ];

  test(
    'Connections rows are Storage Providers, Search & Playback, IPTV, '
    'Tracking',
    () {
      expect(
        _ids(registry, SettingsLayoutSurface.tv, 'Connections'),
        kConnectionsOrder,
      );
      expect(
        _ids(registry, SettingsLayoutSurface.phone, 'Connections'),
        kConnectionsOrder,
      );
      expect(
        _ids(registry, SettingsLayoutSurface.desktop, 'Connections'),
        kConnectionsOrder,
      );
    },
  );

  test('Data & Backup rows keep download / clear / backup / logs order', () {
    const wanted = [
      'downloadLocation',
      'clearDownloads',
      'clearPlayback',
      'createBackup',
      'restoreBackup',
      'exportDiagnosticLogs',
    ];
    expect(_ids(registry, SettingsLayoutSurface.tv, 'Data & Backup'), wanted);
    expect(
      _ids(registry, SettingsLayoutSurface.phone, 'Data & Backup'),
      wanted,
    );
  });

  test('Danger Zone is last and uses resetDebrify', () {
    expect(kSettingsCategories.last.label, 'Danger Zone');
    expect(kSettingsCategories.last.id, 'danger');
    expect(
      _ids(registry, SettingsLayoutSurface.phone, 'Danger Zone'),
      ['resetDebrify'],
    );
    final widgets = File(
      'lib/screens/settings/widgets/settings_widgets.dart',
    ).readAsStringSync();
    expect(widgets, contains('static const resetDebrify'));
  });

  test('SettingsRows still owns the shared icon+copy for nav rows', () {
    final widgets = File(
      'lib/screens/settings/widgets/settings_widgets.dart',
    ).readAsStringSync();
    for (final id in [
      'homePage',
      'player',
      'searchSettings',
      'filterSettings',
      'providerSettings',
      'quickPlay',
      'discoverDefault',
      'debrifyTv',
      'recordings',
      'iptvPlaylists',
      'remote',
      'resetDebrify',
    ]) {
      expect(widgets, contains('static const $id'), reason: id);
    }
  });
}

/// Canonical rail order. Phone uses the same names as section titles
/// (Profiles is conditional). Connections absorbed the old Trackers,
/// Search, Playback and Live TV & DVR categories. Layout and Theme
/// replaced Home & Display, Appearance and Discover.
const kSettingsCategoryOrder = [
  'Connections',
  'Layout',
  'Theme',
  'Devices',
  'Profiles',
  'Data & Backup',
  'About',
  'Danger Zone',
];

List<String> _ids(
  SettingsPageRegistry registry,
  SettingsLayoutSurface surface,
  String category,
) => [
  for (final page in registry.visibleOn(surface, category: category)) page.id,
];
