import 'package:flutter/foundation.dart';

import '../services/text_brightness.dart';
import '../widgets/detail/theme/detail_themes.dart';
import 'app_looks.dart';
import 'app_theme.dart';
import 'app_theme_adapter.dart';
import 'premium_looks.dart';
import 'theme_core_resolver.dart';
import 'theme_override_applier.dart';
import 'theme_overrides.dart';

/// The inputs that decide what the Appearance preview shows.
///
/// A value, not a controller read: the preview must be able to show a theme
/// the app is NOT running (a Look under the pointer, a Look under DPAD focus)
/// without touching `AppThemeController`, and the same three inputs are what
/// the controller itself derives the live theme from.
@immutable
class AppearancePreviewState {
  /// `app_theme` id — a premium look, a detail theme, or `legacy`.
  final String themeId;

  /// The per-token edits layered over [themeId]. `ThemeOverrides.none` for a
  /// Look that has just been picked, since picking one clears them.
  final ThemeOverrides overrides;

  final TextBrightness preset;

  /// Caption for the card's eyebrow — the Look's name, or null for Custom.
  final String? lookLabel;

  const AppearancePreviewState({
    required this.themeId,
    this.overrides = ThemeOverrides.none,
    this.preset = TextBrightness.bright,
    this.lookLabel,
  });

  /// What the app would look like after applying [look]: its theme and text
  /// brightness, with no token edits (applying a Look clears them).
  factory AppearancePreviewState.forLook(AppLook look) {
    final preset = TextBrightness.values.firstWhere(
      (b) => b.value == look.values['text_brightness'],
      orElse: () => TextBrightness.bright,
    );
    return AppearancePreviewState(
      themeId: look.values['app_theme'] ?? AppThemes.legacyId,
      preset: preset,
      lookLabel: look.label,
    );
  }

  /// Identity for memoising the resolved theme. [lookLabel] is deliberately
  /// excluded — it changes what the caption says, not what is drawn.
  String get cacheKey => '$themeId|${preset.value}|${overrides.encode()}';

  @override
  bool operator ==(Object other) =>
      other is AppearancePreviewState &&
      other.cacheKey == cacheKey &&
      other.lookLabel == lookLabel;

  @override
  int get hashCode => Object.hash(cacheKey, lookLabel);
}

/// Builds the [AppTheme] for [state] WITHOUT applying it.
///
/// Step for step the derivation `AppThemeController` runs for the live theme
/// — resolver, preset, spec-or-detail, overrides — so what the preview draws
/// is what selecting these options would put on screen. Pure: no storage, no
/// notifier, no singleton mutation. Cost is the full twelve-subprofile
/// derivation, so callers memoise on [AppearancePreviewState.cacheKey].
AppTheme resolveAppearancePreview(AppearancePreviewState state) {
  final id = state.themeId;
  // Classic is not editable and not preset-resolved: the controller returns
  // the hand-built theme untouched, and so does the preview.
  if (id == AppThemes.legacyId) return AppThemes.legacy;

  final overrides = state.overrides;
  final core = AppThemeAdapter.resolveCoreText(
    ThemeCoreResolver.resolve(id, overrides),
    state.preset,
  );
  final spec = PremiumLooks.byId(id);
  if (spec != null) {
    return overrides.isEmpty
        ? spec.buildWith(core)
        : ThemeOverrideApplier.applyToSpec(spec, overrides).buildWith(core);
  }
  if (overrides.isEmpty) return AppTheme.fromDetail(core);
  return ThemeOverrideApplier.buildFromDetail(
    core,
    overrides,
    authored: AppThemeAdapter.resolveCoreText(
      DetailThemes.byId(id),
      state.preset,
    ),
  );
}
