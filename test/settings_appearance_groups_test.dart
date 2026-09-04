import 'dart:io';

import 'package:debrify/screens/settings/settings_catalog.dart';
import 'package:debrify/screens/settings/settings_page_registry.dart';
import 'package:debrify/screens/settings/settings_page_spec.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Appearance category's DPAD wiring is POSITIONAL: the pane walker
/// moves focus by node index ± 1, so the numbering IS the on-screen order.
/// [buildSettingsCategoryChildren] claims [_paneNodes] sequentially so a
/// group boundary cannot skip or repeat an index.
void main() {
  late List<Widget> appearance;
  late List<FocusNode> nodes;

  setUpAll(() {
    nodes = List.generate(30, (i) => FocusNode(debugLabel: 'pane-$i'));
    final registry = SettingsPageRegistry(
      pages: buildSettingsPages(
        SettingsPageBindings.noop(isAndroidTv: true, isTelevision: true),
      ),
    );
    appearance = buildSettingsCategoryChildren(
      registry: registry,
      surface: SettingsLayoutSurface.tv,
      category: 'Appearance',
      paneNodes: nodes,
    );
  });

  tearDownAll(() {
    for (final n in nodes) {
      n.dispose();
    }
  });

  test('pane focus indices are contiguous from zero across every group', () {
    final indices = _claimedIndices(appearance, nodes);
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
      appearance,
      nodes,
    ).reduce((a, b) => a > b ? a : b);
    expect(
      highest,
      lessThan(pool),
      reason: 'a row past the pool throws on build',
    );
  });

  test('every group carries a header and an explanation', () {
    for (final title in [
      'Presets',
      'Theme',
      'Screen layouts',
      'Display',
      // Android-TV-only, and deliberately LAST: the gated section sits at the
      // end so its dead node can't strand DPAD traversal on Apple TV.
      'Player',
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

    for (final w in appearance) {
      walk(w);
    }
    expect(groups, ['Presets', 'Theme', 'Screen layouts', 'Display', 'Player']);
  });
}

List<int> _claimedIndices(List<Widget> widgets, List<FocusNode> pool) {
  final out = <int>[];
  void walk(Widget w) {
    FocusNode? node;
    if (w is SettingsLookHero) {
      node = w.focusNode;
    } else if (w is SettingsTile) {
      node = w.focusNode;
    } else if (w is SettingsToggleTile) {
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
