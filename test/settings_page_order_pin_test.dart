import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins today's settings information architecture before the S1 registry
/// move. Order is a user-visible quirk: a page that jumps a section, or a
/// rail that swaps Connections and Trackers, is a behaviour change.
///
/// Source-level because the failure is structural (the 6-site tables drifting
/// apart), not visual. After the registry lands this file still asserts the
/// same lists; the reader switches from three files to one catalog.
void main() {
  late String screen;
  late String tv;
  late String widgets;

  setUpAll(() {
    screen = File('lib/screens/settings_screen.dart').readAsStringSync();
    tv = File('lib/screens/settings/settings_tv_layout.dart').readAsStringSync();
    widgets = File(
      'lib/screens/settings/widgets/settings_widgets.dart',
    ).readAsStringSync();
  });

  test('the 13 rail categories stay in todays order on TV and desktop', () {
    final tvBlock = tv.substring(
      tv.indexOf('const List<_Category> _kCategories'),
      tv.indexOf('class _SettingsTvLayoutState'),
    );
    final desktopStart = screen.indexOf(
      'const List<SettingsCategoryDefinition> _kAdaptiveSettingsCategories',
    );
    final desktopBlock = screen.substring(
      desktopStart,
      screen.indexOf('class _SettingsLayout', desktopStart),
    );
    expect(
      _quotedOrder(tvBlock, kSettingsCategoryOrder),
      kSettingsCategoryOrder,
      reason: 'TV _kCategories',
    );
    expect(
      _quotedOrder(desktopBlock, kSettingsCategoryOrder),
      kSettingsCategoryOrder,
      reason: 'desktop _kAdaptiveSettingsCategories',
    );
  });

  test('Search rows are Engines, Filters, Default Provider, Quick Play', () {
    expect(_rowOrder(tv, 'searchSettings', 'filterSettings'), [
      'searchSettings',
      'filterSettings',
      'providerSettings',
      'quickPlay',
    ]);
    expect(_rowOrder(screen, 'searchSettings', 'filterSettings'), [
      'searchSettings',
      'filterSettings',
      'providerSettings',
      'quickPlay',
    ]);
  });

  test('Live TV & DVR rows are Debrify TV, Recordings, IPTV Playlists', () {
    expect(_rowOrder(tv, 'debrifyTv', 'recordings'), [
      'debrifyTv',
      'recordings',
      'iptvPlaylists',
    ]);
    expect(_rowOrder(screen, 'debrifyTv', 'recordings'), [
      'debrifyTv',
      'recordings',
      'iptvPlaylists',
    ]);
  });

  test('Data & Backup rows keep download / clear / backup / logs order', () {
    expect(_rowOrder(tv, 'downloadLocation', 'clearDownloads'), [
      'downloadLocation',
      'clearDownloads',
      'clearPlayback',
      'createBackup',
      'restoreBackup',
      'exportDiagnosticLogs',
    ]);
    expect(_rowOrder(screen, 'downloadLocation', 'clearDownloads'), [
      'downloadLocation',
      'clearDownloads',
      'clearPlayback',
      'createBackup',
      'restoreBackup',
      'exportDiagnosticLogs',
    ]);
  });

  test('Danger Zone is last and uses resetDebrify', () {
    expect(screen, contains("title: 'Danger Zone'"));
    expect(tv, contains("'Danger Zone'"));
    expect(widgets, contains('static const resetDebrify'));
    expect(
      screen.lastIndexOf("title: 'Danger Zone'"),
      greaterThan(screen.lastIndexOf("title: 'About'")),
    );
  });

  test('SettingsRows still owns the shared icon+copy for nav rows', () {
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

/// Canonical rail order. Phone uses the same names as section titles (Profiles
/// is conditional; Connections/Trackers live in the connections widget).
const kSettingsCategoryOrder = [
  'Connections',
  'Trackers',
  'Home & Display',
  'Appearance',
  'Playback',
  'Search',
  'Discover',
  'Live TV & DVR',
  'Devices',
  'Profiles',
  'Data & Backup',
  'About',
  'Danger Zone',
];

/// First-appearance order of `SettingsRows.<id>` identifiers starting at
/// [first]. Used to pin a run of rows without swallowing the whole file.
List<String> _rowOrder(String src, String first, String second) {
  final ids = RegExp(
    r'SettingsRows\.([A-Za-z0-9_]+)',
  ).allMatches(src).map((m) => m.group(1)!).toList();
  final start = ids.indexOf(first);
  expect(start, isNonNegative, reason: 'missing SettingsRows.$first');
  expect(
    ids.indexOf(second, start + 1),
    start + 1,
    reason: '$first should be immediately followed by $second',
  );
  final wanted = {
    'searchSettings',
    'filterSettings',
    'providerSettings',
    'quickPlay',
    'debrifyTv',
    'recordings',
    'iptvPlaylists',
    'downloadLocation',
    'clearDownloads',
    'clearPlayback',
    'createBackup',
    'restoreBackup',
    'exportDiagnosticLogs',
  };
  final run = <String>[];
  for (var i = start; i < ids.length; i++) {
    if (!wanted.contains(ids[i])) break;
    run.add(ids[i]);
  }
  return run;
}

List<String> _quotedOrder(String src, List<String> labels) {
  final pairs = [
    for (final label in labels)
      () {
        final a = src.indexOf("'$label'");
        final b = src.indexOf('"$label"');
        final index = a < 0
            ? b
            : b < 0
            ? a
            : (a < b ? a : b);
        return (index, label);
      }(),
  ];
  expect(
    pairs.every((p) => p.$1 >= 0),
    isTrue,
    reason: 'missing label in ${pairs.where((p) => p.$1 < 0).toList()}',
  );
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final p in pairs) p.$2];
}
