import 'package:flutter/foundation.dart';

/// One selectable layout on an inline "Screen layouts" row.
@immutable
class LayoutOption {
  /// The stored pref value (`'showcase'`, `'canvas'`, …).
  final String id;
  final String label;

  /// One line saying what the layout does — the opener page's subtitle.
  final String blurb;

  const LayoutOption(this.id, this.label, this.blurb);
}

/// The inline option set a Screen-layouts row renders instead of opening a
/// picker page.
///
/// [current] is read synchronously at build time (the settings screen keeps
/// every layout pref in state, exactly as it did for the row subtitles).
/// [apply] MUST go through the same setter the opener page used — including
/// its `LookApplier.noteExternalWrite` and `MainPageBridge` side effects — so
/// choosing inline and choosing on the page are indistinguishable downstream.
@immutable
class SettingsLayoutOptions {
  /// Stable row id — the [SettingsPageSpec.id]; also the preview stage's key.
  final String rowId;
  final List<LayoutOption> options;
  final String Function() current;
  final Future<void> Function(String id) apply;

  /// A row that carries more than one setting (Player Controls: palette and
  /// size) keeps its page reachable through a trailing chip.
  final String? moreLabel;
  final Future<void> Function()? onMore;

  const SettingsLayoutOptions({
    required this.rowId,
    required this.options,
    required this.current,
    required this.apply,
    this.moreLabel,
    this.onMore,
  }) : assert(
         (moreLabel == null) == (onMore == null),
         'moreLabel and onMore come together',
       );

  LayoutOption? byId(String id) {
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  String labelOf(String id) => byId(id)?.label ?? id;
}

/// The applied value of every Screen-layouts pref, as the settings screen
/// holds it. Defaults match each pref's own default so a binding built
/// without values (tests, the noop bindings) still selects a real option.
@immutable
class LayoutRowValues {
  final String tvHomeStyle;
  final String discoverLayout;
  final String detailPageStyle;
  final String tvSidebarStyle;
  final String iptvStyle;
  final String debrifyTvStyle;
  final String playerGuideStyle;
  final String playLoaderStyle;
  final String playerDockStyle;
  final String parentsGuideStyle;
  final String profileGateStyle;
  final String phoneNavStyle;
  final String desktopSidebarStyle;

  const LayoutRowValues({
    this.tvHomeStyle = 'canvas',
    this.discoverLayout = 'stage',
    this.detailPageStyle = 'showcase',
    this.tvSidebarStyle = 'ghost',
    this.iptvStyle = 'command',
    this.debrifyTvStyle = 'grid',
    this.playerGuideStyle = 'classic',
    this.playLoaderStyle = 'marquee',
    this.playerDockStyle = 'classic',
    this.parentsGuideStyle = 'compass',
    this.profileGateStyle = 'stage_cards',
    this.phoneNavStyle = 'classic',
    this.desktopSidebarStyle = 'rail',
  });
}
