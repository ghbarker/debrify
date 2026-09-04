import 'package:flutter/material.dart';

import 'settings_page_spec.dart';
import 'settings_search.dart';
import 'widgets/settings_widgets.dart';

/// Canonical 13-category rail. Labels MUST stay in this order — pinned by
/// `test/settings_page_order_pin_test.dart`.
const List<SettingsCategorySpec> kSettingsCategories = [
  SettingsCategorySpec(
    id: 'connections',
    icon: Icons.link_rounded,
    label: 'Connections',
    tvSubtitle: 'Debrid, cloud, IPTV & more',
    tvTitle: 'Services, all in one place.',
    tvDescription:
        'See what is ready, what needs attention, and where playback will go.',
    desktopSubtitle: 'Debrid, cloud, IPTV & more',
    desktopEyebrow: 'Connections',
    desktopTitle: 'Services, all in one place.',
    desktopDescription:
        'See what is ready, what needs attention, and where playback will go '
        'before opening a provider.',
  ),
  SettingsCategorySpec(
    id: 'trackers',
    icon: Icons.sync_rounded,
    label: 'Trackers',
    tvSubtitle: 'Trakt & Simkl watch history',
    tvTitle: 'Keep every watch in sync.',
    tvDescription:
        'Choose how tracking works, then connect each watch-history service.',
    desktopSubtitle: 'Trakt & Simkl watch history',
    desktopEyebrow: 'Trackers',
    desktopTitle: 'Keep every watch in sync.',
    desktopDescription:
        'Choose how tracking works, then connect each watch-history service '
        'without digging through account screens.',
  ),
  SettingsCategorySpec(
    id: 'homeDisplay',
    icon: Icons.home_rounded,
    label: 'Home & Display',
    tvSubtitle: 'Home screen rows & keyboard',
    tvTitle: 'Shape the room you come home to.',
    tvDescription:
        'Arrange the home screen and tune this television for the room.',
    desktopSubtitle: 'Rows, artwork & navigation',
    desktopEyebrow: 'Home & Display',
    desktopTitle: 'Shape the room you come home to.',
    desktopDescription:
        'Arrange the home screen and choose the navigation that fits this '
        'device.',
  ),
  SettingsCategorySpec(
    id: 'appearance',
    icon: Icons.auto_awesome_rounded,
    label: 'Appearance',
    tvSubtitle: 'Text, home, sidebar, IPTV & player looks',
    tvTitle: 'Make the interface feel like yours.',
    tvDescription:
        'A Look sets the room. Fine-tune only the controls that matter.',
    desktopSubtitle: 'Look, text, motion & layouts',
    desktopEyebrow: 'Appearance',
    desktopTitle: 'Make the interface feel like yours.',
    desktopDescription:
        'A Look sets the room. Individual controls below let you adjust only '
        'what matters.',
  ),
  SettingsCategorySpec(
    id: 'playback',
    icon: Icons.play_circle_outline_rounded,
    label: 'Playback',
    tvSubtitle: 'Player, skip segments, subtitles & audio',
    tvTitle: 'Playback without surprises.',
    tvDescription:
        'Choose how videos start and what plays them on this television.',
    desktopSubtitle: 'Player, subtitles & audio',
    desktopEyebrow: 'Playback',
    desktopTitle: 'Playback without surprises.',
    desktopDescription:
        'Choose how videos start, what plays them, and the behavior shared by '
        'movies and episodes.',
  ),
  SettingsCategorySpec(
    id: 'search',
    icon: Icons.search_rounded,
    label: 'Search',
    tvSubtitle: 'Engines, filters & providers',
    tvTitle: 'Find the right source faster.',
    tvDescription:
        'Engines, default filters, and provider routing form one pipeline.',
    desktopSubtitle: 'Engines, filters & providers',
    desktopEyebrow: 'Search',
    desktopTitle: 'Find the right source faster.',
    desktopDescription:
        'Search engines, default filters, and provider routing form one clear '
        'pipeline.',
  ),
  SettingsCategorySpec(
    id: 'discover',
    icon: Icons.explore_rounded,
    label: 'Discover',
    tvSubtitle: 'Source & poster cards',
    tvTitle: 'Open Discover where you left it.',
    tvDescription:
        'Remember the last source or choose one place to open every time.',
    desktopSubtitle: 'Source & poster cards',
    desktopEyebrow: 'Discover',
    desktopTitle: 'Open where you want to browse.',
    desktopDescription:
        'Remember the last source you used or choose one source to show every '
        'time Discover opens.',
  ),
  SettingsCategorySpec(
    id: 'liveTv',
    icon: Icons.fiber_dvr_rounded,
    label: 'Live TV & DVR',
    tvSubtitle: 'Debrify TV, recordings & IPTV',
    tvTitle: 'Live television, organized.',
    tvDescription:
        'Manage channel sources, recordings, and the on-screen guide.',
    desktopSubtitle: 'Channels, guide & recordings',
    desktopEyebrow: 'Live TV & DVR',
    desktopTitle: 'Live television, organized.',
    desktopDescription:
        'Manage channel sources, recordings, and the guide from one focused '
        'area.',
  ),
  SettingsCategorySpec(
    id: 'devices',
    icon: Icons.devices_rounded,
    label: 'Devices',
    tvSubtitle: 'Remote control & setup transfer',
    tvTitle: 'Let your devices work together.',
    tvDescription:
        'Control another screen or move this setup without retyping it.',
    desktopSubtitle: 'Remote & setup transfer',
    desktopEyebrow: 'Devices',
    desktopTitle: 'Let your devices work together.',
    desktopDescription:
        'Control another screen or move this setup without re-entering every '
        'service.',
  ),
  SettingsCategorySpec(
    id: 'profiles',
    icon: Icons.switch_account_rounded,
    label: 'Profiles',
    tvSubtitle: 'Who can use this device',
    tvTitle: 'One device, many viewers.',
    tvDescription:
        'Switch between people, add someone new, and shape their access.',
    desktopSubtitle: 'Who can use this device',
    desktopEyebrow: 'Profiles',
    desktopTitle: 'One device, many viewers.',
    desktopDescription:
        'Switch between people, add someone new, and shape what each '
        'profile can reach.',
  ),
  SettingsCategorySpec(
    id: 'dataBackup',
    icon: Icons.storage_rounded,
    label: 'Data & Backup',
    tvSubtitle: 'Downloads, backup & restore',
    tvTitle: 'Your data, under your control.',
    tvDescription:
        'Manage stored state and keep a portable copy of your setup.',
    desktopSubtitle: 'Downloads, backup & restore',
    desktopEyebrow: 'Data & Backup',
    desktopTitle: 'Your data, under your control.',
    desktopDescription:
        'Downloads, playback state, and portable backups are separated into '
        'clear actions.',
  ),
  SettingsCategorySpec(
    id: 'about',
    icon: Icons.info_outline_rounded,
    label: 'About',
    tvSubtitle: 'Updates, version & community',
    tvTitle: 'Debrify, up to date.',
    tvDescription:
        'Version, release checks, and the places where the community meets.',
    desktopSubtitle: 'Updates, version & community',
    desktopEyebrow: 'About',
    desktopTitle: 'Debrify, up to date.',
    desktopDescription:
        'Version, release checks, and the places where the community meets.',
  ),
  SettingsCategorySpec(
    id: 'danger',
    icon: Icons.warning_amber_rounded,
    label: 'Danger Zone',
    tvSubtitle: 'Reset Debrify',
    tvTitle: 'Start over, deliberately.',
    tvDescription:
        'Destructive actions stay isolated and explain what they remove.',
    desktopSubtitle: 'Reset Debrify',
    desktopEyebrow: 'Danger Zone',
    desktopTitle: 'Start over, deliberately.',
    desktopDescription:
        'Destructive actions stay isolated and explain exactly what they '
        'remove.',
    destructive: true,
  ),
];

/// Pages registered once; phone, desktop and TV layouts plus search all
/// read from this. Tests may construct a registry with extra pages to
/// prove a single registration lights up every surface.
class SettingsPageRegistry {
  final List<SettingsCategorySpec> categories;
  final List<SettingsPageSpec> pages;

  const SettingsPageRegistry({
    this.categories = kSettingsCategories,
    required this.pages,
  });

  List<SettingsPageSpec> visibleOn(
    SettingsLayoutSurface surface, {
    String? category,
  }) {
    final list = [
      for (final page in pages)
        if (page.showsOn(surface) &&
            (category == null || page.category == category))
          page,
    ];
    list.sort((a, b) {
      final byOrder = a.orderOn(surface).compareTo(b.orderOn(surface));
      if (byOrder != 0) return byOrder;
      return pages.indexOf(a).compareTo(pages.indexOf(b));
    });
    return list;
  }

  List<String> titlesOn(SettingsLayoutSurface surface, {String? category}) => [
    for (final page in visibleOn(surface, category: category)) page.title,
  ];

  /// Focusable TV rows in [category] (info tiles are not focusable — the
  /// About version chip is the existing case). Used to size the pane node
  /// pool so a new row cannot land past the pool.
  int tvFocusableCount(String category) {
    var n = 0;
    for (final page in pages) {
      if (!page.tv || page.category != category) continue;
      if (page.kindOn(SettingsLayoutSurface.tv) == SettingsRowKind.info) {
        continue;
      }
      n++;
    }
    return n;
  }

  int get tvMaxFocusableRows {
    var max = 0;
    for (final cat in categories) {
      final n = tvFocusableCount(cat.label);
      if (n > max) max = n;
    }
    return max;
  }

  List<SettingsSearchEntry> searchIndex() {
    final entries = <SettingsSearchEntry>[];
    for (final page in pages) {
      if (!page.isSearchVisible) continue;
      if (page.search) entries.add(page.toSearchEntry());
      for (final leaf in page.leaves) {
        if (!(leaf.visible?.call() ?? true)) continue;
        entries.add(
          SettingsSearchEntry(
            icon: page.row.icon,
            title: leaf.title,
            subtitle: leaf.subtitle,
            category: page.searchLeafPage,
            keywords: leaf.keywords,
            onTap: leaf.onTap ?? page.opener ?? () async {},
          ),
        );
      }
    }
    return entries;
  }
}

/// Appearance group blurbs — the wording differs slightly per surface and
/// that difference is a preserved quirk, not a cleanup.
String? settingsGroupBlurb(SettingsLayoutSurface surface, String group) {
  switch (surface) {
    case SettingsLayoutSurface.phone:
      switch (group) {
        case 'Presets':
          return 'One pick that sets the theme, layouts and launch '
              'animation together.';
        case 'Theme':
          return 'Colour, focus and motion. Applies everywhere in the '
              'app.';
        case 'Screen layouts':
          return 'Where things sit. Each screen is chosen separately.';
      }
    case SettingsLayoutSurface.desktop:
      switch (group) {
        case 'Presets':
          return 'One pick sets the theme, layouts, and launch animation '
              'together.';
        case 'Theme':
          return 'Colour, focus, and motion. Applies everywhere.';
        case 'Screen layouts':
          return 'Where things sit. Each screen is chosen separately.';
      }
    case SettingsLayoutSurface.tv:
      switch (group) {
        case 'Presets':
          return 'One pick that sets the theme, layouts and launch '
              'animation together.';
        case 'Theme':
          return 'Colour, focus and motion. Applies everywhere in the app.';
        case 'Screen layouts':
          return 'Where things sit. Each screen is chosen separately.';
        case 'Display':
          return 'How this device draws. These affect performance, not '
              'style.';
        case 'Player':
          return 'The on-screen controls during playback on this TV.';
      }
  }
  return null;
}

Widget settingsPageRow(
  SettingsPageSpec spec, {
  SettingsLayoutSurface surface = SettingsLayoutSurface.phone,
  FocusNode? focusNode,
}) {
  switch (spec.kindOn(surface)) {
    case SettingsRowKind.lookHero:
      return SettingsLookHero(
        label: spec.resolvedSubtitle,
        subtitle: 'Full-bleed art, borderless focus, and ambient detail.',
        onTap: spec.opener ?? () async {},
        focusNode: focusNode,
      );
    case SettingsRowKind.toggle:
      return SettingsToggleTile.spec(
        spec.row,
        value: spec.toggleValue?.call() ?? false,
        onChanged: spec.onToggle ?? (_) {},
        focusNode: focusNode,
      );
    case SettingsRowKind.info:
      return SettingsInfoTile.spec(spec.row, value: spec.resolvedSubtitle);
    case SettingsRowKind.url:
      return SettingsTile.spec(
        spec.row,
        onTap: spec.opener ?? () => launchSettingsUrl(spec.row.url!),
        focusNode: focusNode,
      );
    case SettingsRowKind.tile:
      return SettingsTile.spec(
        spec.row,
        subtitle: spec.subtitleOf?.call(),
        onTap: spec.opener ?? () async {},
        destructive: spec.destructive,
        tag: spec.tag,
        trailing: spec.trailingOf?.call(),
        focusNode: focusNode,
      );
  }
}

/// Renders one category's pages for [surface].
///
/// TV: [paneNodes] are claimed sequentially so Up/Down stays contiguous —
/// the DPAD walker only advances to the immediately adjacent live node, so
/// a gap strands Down. Info tiles and section headers take no node.
List<Widget> buildSettingsCategoryChildren({
  required SettingsPageRegistry registry,
  required SettingsLayoutSurface surface,
  required String category,
  List<FocusNode>? paneNodes,
  Color? accentColor,
}) {
  final pages = registry.visibleOn(surface, category: category);
  if (pages.isEmpty) return const [];

  var paneIdx = 0;
  FocusNode? nextNode() {
    if (paneNodes == null) return null;
    if (paneIdx >= paneNodes.length) return null;
    return paneNodes[paneIdx++];
  }

  final heroes = <Widget>[];
  final grouped = <String?, List<SettingsPageSpec>>{};
  for (final page in pages) {
    if (page.kindOn(surface) == SettingsRowKind.lookHero) {
      heroes.add(
        settingsPageRow(page, surface: surface, focusNode: nextNode()),
      );
      continue;
    }
    grouped.putIfAbsent(page.groupOn(surface), () => []).add(page);
  }

  final flatten =
      surface == SettingsLayoutSurface.phone && category != 'Appearance';
  final tvLabeled =
      surface == SettingsLayoutSurface.tv &&
      (category == 'Data & Backup' || category == 'About');
  // Phone's long column used 24px between sections; TV/desktop panes
  // used 18px between groups. Preserve both.
  final gap = surface == SettingsLayoutSurface.phone
      ? const SizedBox(height: 24)
      : const SizedBox(height: 18);

  final children = <Widget>[];
  for (var i = 0; i < heroes.length; i++) {
    if (i > 0 || children.isNotEmpty) {
      children.add(gap);
    }
    children.add(heroes[i]);
  }

  if (flatten) {
    final rows = [
      for (final group in grouped.values)
        for (final page in group)
          settingsPageRow(page, surface: surface, focusNode: nextNode()),
    ];
    if (rows.isEmpty && children.isEmpty) return const [];
    if (rows.isNotEmpty) {
      if (children.isNotEmpty) children.add(gap);
      children.add(
        SettingsSection(
          title: category == 'Danger Zone' ? 'Danger Zone' : category,
          accentColor: accentColor,
          children: rows,
        ),
      );
    }
    return children;
  }

  var firstSection = children.isEmpty;
  for (final entry in grouped.entries) {
    final groupName = entry.key;
    final rows = [
      for (final page in entry.value)
        settingsPageRow(
          page,
          surface: surface,
          focusNode: page.kindOn(surface) == SettingsRowKind.info
              ? null
              : nextNode(),
        ),
    ];
    if (rows.isEmpty) continue;
    if (!firstSection) children.add(gap);
    firstSection = false;
    final title = groupName ?? '';
    final blurb = groupName == null
        ? null
        : settingsGroupBlurb(surface, groupName);
    if (tvLabeled && groupName != null) {
      children.add(SettingsSectionLabel(groupName));
      children.add(SettingsSection(title: '', children: rows));
    } else {
      children.add(
        SettingsSection(
          title: title,
          blurb: blurb,
          accentColor: category == 'Danger Zone' ? accentColor : null,
          children: rows,
        ),
      );
    }
  }
  return children;
}
