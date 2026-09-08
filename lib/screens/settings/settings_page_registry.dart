import 'package:flutter/material.dart';

import 'settings_page_spec.dart';
import 'settings_search.dart';
import 'widgets/appearance_preview_card.dart';
import 'widgets/settings_option_row.dart';
import 'widgets/settings_widgets.dart';

/// Pane nodes the live preview claims on TV — its whole Look strip is one
/// focus stop. Kept next to the registry's count so the two agree.
const int kAppearancePreviewTvNodes = 1;

/// Categories that host the live preview card (AppearancePreviewHost): its
/// mini-stage draws whichever inline Screen-layouts row is under the
/// pointer/D-pad focus. Those rows split across Theme (Looks, App Theme,
/// Theme Tokens, Text Brightness, Launch Animation), Layout (everything
/// else that used to share the old Appearance category with them), and
/// Profiles (Profile Picker, an inline options row of its own).
const Set<String> kPreviewHostCategories = {'Theme', 'Layout', 'Profiles'};

/// Canonical category rail. Labels MUST stay in this order — pinned by
/// `test/settings_page_order_pin_test.dart`.
const List<SettingsCategorySpec> kSettingsCategories = [
  SettingsCategorySpec(
    id: 'connections',
    icon: Icons.link_rounded,
    label: 'Connections',
    tvSubtitle: 'Storage, search, IPTV & tracking',
    tvTitle: 'Services, all in one place.',
    tvDescription:
        'Storage providers, search & playback routing, IPTV sources, and '
        'watch-history tracking, together.',
    desktopSubtitle: 'Storage, search, IPTV & tracking',
    desktopEyebrow: 'Connections',
    desktopTitle: 'Services, all in one place.',
    desktopDescription:
        'Storage providers, search & playback routing, IPTV sources, and '
        'watch-history tracking, together.',
  ),
  SettingsCategorySpec(
    id: 'layout',
    icon: Icons.dashboard_customize_rounded,
    label: 'Layout',
    tvSubtitle: 'Home, sidebar, detail pages, IPTV & player looks',
    tvTitle: 'Shape the room you come home to.',
    tvDescription:
        'Arrange the home screen, sidebar and navigation, then fine-tune '
        'every screen that follows.',
    desktopSubtitle: 'Home, sidebar, detail pages & looks',
    desktopEyebrow: 'Layout',
    desktopTitle: 'Shape the room you come home to.',
    desktopDescription:
        'Arrange the home screen and navigation, then fine-tune the detail, '
        'IPTV and player screens that follow.',
  ),
  SettingsCategorySpec(
    id: 'theme',
    icon: Icons.auto_awesome_rounded,
    label: 'Theme',
    tvSubtitle: 'Look, colour, text & motion',
    tvTitle: 'Make the interface feel like yours.',
    tvDescription:
        'A Look sets the room. Fine-tune only the controls that matter.',
    desktopSubtitle: 'Look, colour, text & motion',
    desktopEyebrow: 'Theme',
    desktopTitle: 'Make the interface feel like yours.',
    desktopDescription:
        'A Look sets the room. Individual controls below let you adjust only '
        'what matters.',
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
    // The live preview card is mounted by buildSettingsCategoryChildren
    // rather than registered as a page, and its Look strip takes one node.
    // Theme AND Layout both host it: every inline Screen-layouts row (now
    // split across the two categories) previews on the same mini-stage.
    var n = kPreviewHostCategories.contains(category)
        ? kAppearancePreviewTvNodes
        : 0;
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
        case 'Storage Providers':
          return 'Debrid and cloud accounts search results are pulled '
              'from.';
        case 'Search & Playback':
          return 'Engines, filters, default provider and the external '
              'player.';
        case 'IPTV':
          return 'Live channel sources, lists and recordings.';
        case 'Tracking':
          return 'Watch-history services and how progress syncs.';
        case 'App Structure':
          return 'The rooms of the app and how you get between them.';
        case 'Detail & Browsing':
          return 'How a movie or series page, and its parents guide, are '
              'laid out.';
        case 'Live TV & IPTV Looks':
          return 'The look of live channels, the guide and Debrify TV.';
        case 'Player Looks':
          return 'The on-screen controls during playback.';
        case 'Screen':
          return 'How this device draws. These affect performance, not '
              'style.';
      }
    case SettingsLayoutSurface.desktop:
      switch (group) {
        case 'Storage Providers':
          return 'Debrid and cloud accounts search results are pulled '
              'from.';
        case 'Search & Playback':
          return 'Engines, filters, default provider and the external '
              'player.';
        case 'IPTV':
          return 'Live channel sources, lists and recordings.';
        case 'Tracking':
          return 'Watch-history services and how progress syncs.';
        case 'App Structure':
          return 'The rooms of the app and how you get between them.';
        case 'Detail & Browsing':
          return 'How a movie or series page, and its parents guide, are '
              'laid out.';
        case 'Live TV & IPTV Looks':
          return 'The look of live channels, the guide and Debrify TV.';
        case 'Player Looks':
          return 'The on-screen controls during playback.';
        case 'Screen':
          return 'How this device draws. These affect performance, not '
              'style.';
      }
    case SettingsLayoutSurface.tv:
      switch (group) {
        case 'Storage Providers':
          return 'Debrid and cloud accounts search results are pulled '
              'from.';
        case 'Search & Playback':
          return 'Engines, filters, default provider and the external '
              'player.';
        case 'IPTV':
          return 'Live channel sources, lists and recordings.';
        case 'Tracking':
          return 'Watch-history services and how progress syncs.';
        case 'App Structure':
          return 'The rooms of the app and how you get between them.';
        case 'Detail & Browsing':
          return 'How a movie or series page, and its parents guide, are '
              'laid out.';
        case 'Live TV & IPTV Looks':
          return 'The look of live channels, the guide and Debrify TV.';
        case 'Player Looks':
          return 'The on-screen controls during playback on this TV.';
        case 'Screen':
          return 'How this device draws. These affect performance, not '
              'style.';
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
    case SettingsRowKind.options:
      // One node for the whole row (Left/Right inside), like any other row —
      // so the TV pane's positional walk and tvFocusableCount are unchanged.
      // singleRow follows the SURFACE being built, not ambient device
      // detection: a long option list (Details Page's 11) wraps into an
      // unreachable second row on any D-pad surface, tests included.
      return SettingsOptionRow(
        icon: spec.row.icon,
        title: spec.title,
        options: spec.layoutOptions!,
        focusNode: focusNode,
        singleRow: surface == SettingsLayoutSurface.tv,
      );
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
///
/// Appearance opens with [AppearancePreviewHost], which is not a page: it
/// claims the FIRST node (its Look strip is one focus stop, Left/Right inside
/// it) so entering the pane lands on the preview and Down reaches the Presets
/// rows. [SettingsPageRegistry.tvFocusableCount] counts that node too, so the
/// pane pool always covers it.
List<Widget> buildSettingsCategoryChildren({
  required SettingsPageRegistry registry,
  required SettingsLayoutSurface surface,
  required String category,
  List<FocusNode>? paneNodes,
  // Phone/desktop have no pane-node pool (rows are plain scroll-list
  // widgets), but the TV sidebar hand-off on tvOS/desktop-with-remote still
  // needs a concrete first-row target to restore focus onto. When set (and
  // [paneNodes] is null) it is handed out as the very first row's node.
  FocusNode? firstRowFocusNode,
  Color? accentColor,
}) {
  final pages = registry.visibleOn(surface, category: category);
  if (pages.isEmpty) return const [];

  var paneIdx = 0;
  var firstRowNodeConsumed = false;
  FocusNode? nextNode() {
    if (paneNodes != null) {
      if (paneIdx >= paneNodes.length) return null;
      return paneNodes[paneIdx++];
    }
    if (!firstRowNodeConsumed && firstRowFocusNode != null) {
      firstRowNodeConsumed = true;
      return firstRowFocusNode;
    }
    return null;
  }

  final heroes = <Widget>[];
  if (kPreviewHostCategories.contains(category)) {
    heroes.add(AppearancePreviewHost(focusNode: nextNode()));
  }
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
      surface == SettingsLayoutSurface.phone &&
      !kPreviewHostCategories.contains(category);
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
