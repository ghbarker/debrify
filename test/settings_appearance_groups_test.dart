import 'dart:io';

import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:debrify/screens/settings/widgets/appearance_preview_card.dart';
import 'package:debrify/screens/settings/widgets/settings_option_row.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Theme category's DPAD wiring is POSITIONAL: the pane walker moves
/// focus by node index ± 1, so the numbering IS the on-screen order.
/// [buildSettingsCategoryChildren] claims [_paneNodes] sequentially so a
/// group boundary cannot skip or repeat an index. Theme no longer has
/// sub-groups (Presets/Theme merged away in the settings-menu reorg), so it
/// renders as the live preview hero plus one flat, ungrouped section.
void main() {
  late List<Widget> theme;
  late List<FocusNode> nodes;

  setUpAll(() {
    nodes = List.generate(30, (i) => FocusNode(debugLabel: 'pane-$i'));
    final registry = SettingsPageRegistry(
      pages: buildSettingsPages(
        SettingsPageBindings.noop(isAndroidTv: true, isTelevision: true),
      ),
    );
    theme = buildSettingsCategoryChildren(
      registry: registry,
      surface: SettingsLayoutSurface.tv,
      category: 'Theme',
      paneNodes: nodes,
    );
  });

  tearDownAll(() {
    for (final n in nodes) {
      n.dispose();
    }
  });

  test('the live preview opens the pane and claims exactly node zero', () {
    expect(theme.first, isA<AppearancePreviewHost>());
    final preview = theme.first as AppearancePreviewHost;
    expect(nodes.indexOf(preview.focusNode!), 0);
    expect(
      theme.whereType<AppearancePreviewHost>().length,
      1,
      reason: 'one preview card — the old ACTIVE LOOK hero is absorbed',
    );
    expect(theme.whereType<SettingsLookHero>(), isEmpty);
  });

  test('pane focus indices are contiguous from zero across the category', () {
    final indices = _claimedIndices(theme, nodes);
    expect(indices, isNotEmpty);
    expect(
      indices,
      List<int>.generate(indices.length, (i) => i),
      reason:
          'a gap skips a row on the way down; a repeat means two widgets '
          'share one FocusNode and one becomes unreachable',
    );
  });

  test('the node pool covers the category', () {
    final src = File(
      'lib/screens/settings/settings_tv_layout.dart',
    ).readAsStringSync();
    final pool = int.parse(
      RegExp(r'_kMaxCategoryRows = (\d+)').firstMatch(src)!.group(1)!,
    );
    final highest = _claimedIndices(
      theme,
      nodes,
    ).reduce((a, b) => a > b ? a : b);
    expect(
      highest,
      lessThan(pool),
      reason: 'a row past the pool throws on build',
    );
    // The registry's own count must agree with what was actually claimed —
    // it sizes the pool, and it has to know about the preview's node.
    final registry = SettingsPageRegistry(
      pages: buildSettingsPages(
        SettingsPageBindings.noop(isAndroidTv: true, isTelevision: true),
      ),
    );
    expect(registry.tvFocusableCount('Theme'), highest + 1);
  });

  test('Theme has no sub-group headers — one flat section', () {
    final groups = <String>[];
    void walk(Widget w) {
      if (w is SettingsSection && w.title.isNotEmpty) {
        groups.add(w.title);
      }
      if (w is SettingsSection) {
        for (final c in w.children) {
          walk(c);
        }
      }
    }

    for (final w in theme) {
      walk(w);
    }
    expect(groups, isEmpty);
  });

  // Layout absorbed the old sub-grouped Screen layouts/Display/Player groups
  // (renamed and expanded into App Structure/Detail & Browsing/Live TV &
  // IPTV Looks/Player Looks/Screen) — same positional-DPAD invariant that
  // used to be pinned against Appearance's groups.
  group('Layout groups', () {
    late List<Widget> layout;
    late List<FocusNode> layoutNodes;

    setUpAll(() {
      layoutNodes = List.generate(30, (i) => FocusNode(debugLabel: 'layout-pane-$i'));
      final registry = SettingsPageRegistry(
        pages: buildSettingsPages(
          SettingsPageBindings.noop(isAndroidTv: true, isTelevision: true),
        ),
      );
      layout = buildSettingsCategoryChildren(
        registry: registry,
        surface: SettingsLayoutSurface.tv,
        category: 'Layout',
        paneNodes: layoutNodes,
      );
    });

    tearDownAll(() {
      for (final n in layoutNodes) {
        n.dispose();
      }
    });

    test('pane focus indices are contiguous from zero across every group', () {
      final indices = _claimedIndices(layout, layoutNodes);
      expect(indices, isNotEmpty);
      expect(
        indices,
        List<int>.generate(indices.length, (i) => i),
        reason:
            'a gap skips a row on the way down; a repeat means two widgets '
            'share one FocusNode and one becomes unreachable',
      );
    });

    test('the node pool covers the category', () {
      final src = File(
        'lib/screens/settings/settings_tv_layout.dart',
      ).readAsStringSync();
      final pool = int.parse(
        RegExp(r'_kMaxCategoryRows = (\d+)').firstMatch(src)!.group(1)!,
      );
      final highest = _claimedIndices(
        layout,
        layoutNodes,
      ).reduce((a, b) => a > b ? a : b);
      expect(
        highest,
        lessThan(pool),
        reason: 'a row past the pool throws on build',
      );
      final registry = SettingsPageRegistry(
        pages: buildSettingsPages(
          SettingsPageBindings.noop(isAndroidTv: true, isTelevision: true),
        ),
      );
      expect(registry.tvFocusableCount('Layout'), highest + 1);
    });

    test('every group carries a header and an explanation', () {
      for (final title in [
        'App Structure',
        'Detail & Browsing',
        'Live TV & IPTV Looks',
        'Player Looks',
        // Android-TV-only, and deliberately LAST: the gated section sits at
        // the end so its dead node can't strand DPAD traversal on Apple TV.
        'Screen',
      ]) {
        expect(
          settingsGroupBlurb(SettingsLayoutSurface.tv, title),
          isNotNull,
          reason: title,
        );
      }
      final groups = <String>[];
      void walk(Widget w) {
        if (w is SettingsSection && w.title.isNotEmpty) {
          groups.add(w.title);
        }
        if (w is SettingsSection) {
          for (final c in w.children) {
            walk(c);
          }
        }
      }

      for (final w in layout) {
        walk(w);
      }
      expect(groups, [
        'App Structure',
        'Detail & Browsing',
        'Live TV & IPTV Looks',
        'Player Looks',
        'Screen',
      ]);
    });
  });
}

List<int> _claimedIndices(List<Widget> widgets, List<FocusNode> pool) {
  final out = <int>[];
  void walk(Widget w) {
    FocusNode? node;
    if (w is AppearancePreviewHost) {
      node = w.focusNode;
    } else if (w is SettingsLookHero) {
      node = w.focusNode;
    } else if (w is SettingsTile) {
      node = w.focusNode;
    } else if (w is SettingsToggleTile) {
      node = w.focusNode;
    } else if (w is SettingsOptionRow) {
      // An inline layouts row: one node for the whole strip.
      node = w.focusNode;
    }
    if (node != null) {
      final i = pool.indexOf(node);
      if (i >= 0) out.add(i);
    }
    if (w is SettingsSection) {
      for (final c in w.children) {
        walk(c);
      }
    }
  }

  for (final w in widgets) {
    walk(w);
  }
  return out;
}
