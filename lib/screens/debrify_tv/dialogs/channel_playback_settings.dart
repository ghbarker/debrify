import 'dart:async';
import 'package:flutter/material.dart';

import '../../../models/torrent_filter_state.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../../services/profiles/profile_policy_guard.dart';
import '../../../services/cloud/cloud_provider_id.dart';
import '../../../services/cloud/magic_tv_provider.dart';
import 'package:debrify/services/storage/debrify_tv_prefs.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/debrify_tv_filters.dart';
import '../channel_playback_settings_state.dart';
import '../widgets/random_start_slider.dart';
import '../widgets/spotlight_choice_chip.dart';
import '../widgets/switch_row.dart';
import 'spotlight_dialog.dart';

enum _SettingsScope { quickPlay, channels }

Future<void> showChannelPlaybackSettings(
  BuildContext context,
  ChannelPlaybackSettingsState state, {
  required StateSetter rebuildHost,
  required VoidCallback invalidateStats,
  required VoidCallback showResetSuccess,
  required bool Function() isBusy,
  required bool Function() isAndroidTv,
  required Map<CloudProviderId, bool> Function() readAvailability,
}) async {
  Widget tvFilterChips({StateSetter? dialogSetState}) {
    void applyFilters(DebrifyTvFilters next) {
      rebuildHost(() => state.tvFilters = next);
      // "At your quality" is computed WITH the filter; stale memos would
      // keep the old filter's count while playback uses the new one.
      invalidateStats();
      dialogSetState?.call(() {});
    }

    void toggleQuality(QualityTier quality) {
      final next = Set<QualityTier>.from(state.tvFilters.qualities);
      if (!next.remove(quality)) next.add(quality);
      applyFilters(
        DebrifyTvFilters(qualities: next, sizes: state.tvFilters.sizes),
      );
      unawaited(
        DebrifyTvPrefs.setDebrifyTvFilterQualities(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    void toggleSize(SizeBucket bucket) {
      final next = Set<SizeBucket>.from(state.tvFilters.sizes);
      if (!next.remove(bucket)) next.add(bucket);
      applyFilters(
        DebrifyTvFilters(qualities: state.tvFilters.qualities, sizes: next),
      );
      unawaited(
        DebrifyTvPrefs.setDebrifyTvFilterSizes(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppThemeScope.of(context).debrifyTv.textMeta,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playback filters',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'Applies to channels and quick play. If nothing matches, Debrify TV '
          'plays what it can rather than showing an empty channel.',
          style: labelStyle,
        ),
        const SizedBox(height: 10),
        Text('Quality', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quality in QualityTier.values)
              SpotlightChoiceChip(
                label: DebrifyTvFilters.qualityLabel(quality),
                selected: state.tvFilters.qualities.contains(quality),
                enabled: !isBusy(),
                onPressed: () => toggleQuality(quality),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('File size (per episode/movie)', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final bucket in SizeBucket.values)
              SpotlightChoiceChip(
                label: DebrifyTvFilters.sizeLabel(bucket),
                selected: state.tvFilters.sizes.contains(bucket),
                enabled: !isBusy(),
                onPressed: () => toggleSize(bucket),
              ),
          ],
        ),
      ],
    );
  }

  Widget providerChoiceChips(
    _SettingsScope scope, {
    StateSetter? dialogSetState,
  }) {
    final bool isQuickScope = scope == _SettingsScope.quickPlay;
    final String currentProvider = isQuickScope
        ? state.quickProvider
        : state.provider;

    void handleSelection(String value) {
      if (readAvailability()[CloudProviderId.fromMagicTvId(value) ??
              CloudProviderId.debrid] !=
          true) {
        return;
      }
      if (isQuickScope) {
        if (state.quickProvider == value) {
          return;
        }
        rebuildHost(() {
          state.quickProvider = value;
        });
        dialogSetState?.call(() {});
        return;
      }

      if (state.provider == value) {
        return;
      }
      rebuildHost(() {
        state.provider = value;
      });
      dialogSetState?.call(() {});
      unawaited(DebrifyTvPrefs.saveDebrifyTvProvider(value));
    }

    Widget providerChip({
      required String value,
      required String label,
      required bool available,
      required String unavailableMessage,
    }) {
      return Tooltip(
        message: available ? 'Use $label for Debrify TV' : unavailableMessage,
        child: SpotlightChoiceChip(
          label: label,
          selected: currentProvider == value,
          enabled: available && !isBusy(),
          onPressed: () => handleSelection(value),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        providerChip(
          value: CloudProviderId.debrid.magicTvId,
          label: 'Real Debrid',
          available: readAvailability()[CloudProviderId.debrid] == true,
          unavailableMessage:
              'Enable Real Debrid and add an API key in Settings.',
        ),
        providerChip(
          value: CloudProviderId.torbox.magicTvId,
          label: 'Torbox',
          available: readAvailability()[CloudProviderId.torbox] == true,
          unavailableMessage: 'Enable Torbox and add an API key in Settings.',
        ),
        providerChip(
          value: CloudProviderId.pikpak.magicTvId,
          label: 'PikPak',
          available: readAvailability()[CloudProviderId.pikpak] == true,
          unavailableMessage: 'Log in to PikPak in Settings.',
        ),
        providerChip(
          value: CloudProviderId.premiumize.magicTvId,
          label: 'Premiumize',
          available: readAvailability()[CloudProviderId.premiumize] == true,
          unavailableMessage:
              'Enable Premiumize and add an API key in Settings.',
        ),
        providerChip(
          value: CloudProviderId.alldebrid.magicTvId,
          label: 'AllDebrid',
          available: readAvailability()[CloudProviderId.alldebrid] == true,
          unavailableMessage:
              'Enable AllDebrid and add an API key in Settings.',
        ),
      ],
    );
  }

  Widget buildSettingsCard({
    required _SettingsScope scope,
    required bool includeNsfwToggle,
    required String title,
    StateSetter? dialogSetState,
  }) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final bool isQuickScope = scope == _SettingsScope.quickPlay;

    final bool startRandom = isQuickScope
        ? state.quickStartRandom
        : state.startRandom;
    void setStartRandom(bool value) {
      rebuildHost(() {
        if (isQuickScope) {
          state.quickStartRandom = value;
        } else {
          state.startRandom = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvPrefs.saveDebrifyTvStartRandom(value));
      }
    }

    final int randomStartPercent = isQuickScope
        ? state.quickRandomStartPercent
        : state.randomStartPercent;
    void setRandomStartPercent(int value) {
      rebuildHost(() {
        if (isQuickScope) {
          state.quickRandomStartPercent = value;
        } else {
          state.randomStartPercent = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvPrefs.saveDebrifyTvRandomStartPercent(value));
      }
    }

    final bool showChannelName = isQuickScope
        ? state.quickShowChannelName
        : state.showChannelName;
    void setShowChannelName(bool value) {
      rebuildHost(() {
        if (isQuickScope) {
          state.quickShowChannelName = value;
        } else {
          state.showChannelName = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvPrefs.saveDebrifyTvShowChannelName(value));
      }
    }

    final bool showVideoTitle = isQuickScope
        ? state.quickShowVideoTitle
        : state.showVideoTitle;
    void setShowVideoTitle(bool value) {
      rebuildHost(() {
        if (isQuickScope) {
          state.quickShowVideoTitle = value;
        } else {
          state.showVideoTitle = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvPrefs.saveDebrifyTvShowVideoTitle(value));
      }
    }

    // Hardcoded to false - no longer changeable
    const bool hideOptions = false;
    void setHideOptions(bool value) {
      // No-op: hideOptions is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    // Hardcoded to false - no longer changeable
    const bool hideBackButton = false;
    void setHideBackButton(bool value) {
      // No-op: hideBackButton is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Container(
        decoration: BoxDecoration(
          color: tv.fillWeak.withValues(alpha: .55),
          borderRadius: app.shape.br(20),
          border: Border.all(color: tv.hairline, width: 1),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: tv.textFaint,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Content provider',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            providerChoiceChips(scope, dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            SwitchRow(
              title: 'Start from random timestamp',
              subtitle: 'Each Debrify TV video starts at a random point',
              value: startRandom,
              onChanged: (v) => setStartRandom(v),
            ),
            if (startRandom) ...[
              const SizedBox(height: 8),
              RandomStartSlider(
                value: randomStartPercent,
                isAndroidTv: isAndroidTv(),
                onChanged: (next) => setRandomStartPercent(next),
                onChangeEnd: isQuickScope
                    ? null
                    : (next) =>
                          DebrifyTvPrefs.saveDebrifyTvRandomStartPercent(next),
              ),
            ],
            // Removed Hide all options and Hide back button settings
            // These are now hardcoded to false (visible by default)
            if (includeNsfwToggle && isQuickScope) ...[
              const SizedBox(height: 8),
              SwitchRow(
                title: 'Avoid NSFW content',
                subtitle:
                    !ProfilePolicyGuard.allowsSync(
                      ProfileFeature.allowAdultContent,
                    )
                    ? 'Always on for this profile'
                    : 'Filter adult/inappropriate torrents • Best effort, not 100% accurate',
                value:
                    !ProfilePolicyGuard.allowsSync(
                      ProfileFeature.allowAdultContent,
                    ) ||
                    state.quickAvoidNsfw,
                onChanged: (v) {
                  // Role-locked: a child session cannot loosen it.
                  if (!ProfilePolicyGuard.allowsSync(
                    ProfileFeature.allowAdultContent,
                  )) {
                    return;
                  }
                  rebuildHost(() {
                    state.quickAvoidNsfw = v;
                  });
                  dialogSetState?.call(() {});
                },
              ),
            ],
            const SizedBox(height: 16),
            // Kept LAST (above Reset) on purpose: these are ~14 focusable
            // chips, and placing them higher would push every existing switch
            // that many extra D-pad presses away on TV.
            tvFilterChips(dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            DebrifyTvDialogButton(
              expand: true,
              icon: Icons.restore_rounded,
              label: 'Reset to defaults',
              onPressed: () async {
                final defaultProvider = MagicTvProvider.pickDefault(
                  preferred: null,
                  available: readAvailability(),
                );

                rebuildHost(() {
                  if (isQuickScope) {
                    state.quickStartRandom = true;
                    state.quickRandomStartPercent =
                        ChannelPlaybackSettingsState.randomStartPercentDefault;
                    state.quickHideSeekbar = true;
                    state.quickShowChannelName = true;
                    state.quickShowVideoTitle = true;
                    state.quickHideOptions = false; // Hardcoded to false
                    state.quickHideBackButton = false; // Hardcoded to false
                    state.quickAvoidNsfw = true;
                    state.quickProvider = defaultProvider;
                  } else {
                    state.startRandom = true;
                    state.randomStartPercent =
                        ChannelPlaybackSettingsState.randomStartPercentDefault;
                    state.hideSeekbar = true;
                    state.showChannelName = true;
                    state.showVideoTitle = true;
                    state.hideOptions = false; // Hardcoded to false
                    state.hideBackButton = false; // Hardcoded to false
                    state.provider = defaultProvider;
                  }
                  // Playback filters are shared by both scopes, so reset
                  // them from either one.
                  state.tvFilters = const DebrifyTvFilters.empty();
                });
                invalidateStats();
                dialogSetState?.call(() {});

                await DebrifyTvPrefs.setDebrifyTvFilterQualities(const []);
                await DebrifyTvPrefs.setDebrifyTvFilterSizes(const []);

                if (!isQuickScope) {
                  await DebrifyTvPrefs.saveDebrifyTvStartRandom(true);
                  await DebrifyTvPrefs.saveDebrifyTvHideSeekbar(true);
                  await DebrifyTvPrefs.saveDebrifyTvShowChannelName(true);
                  await DebrifyTvPrefs.saveDebrifyTvShowVideoTitle(true);
                  // No longer saving hideOptions and hideBackButton - they're hardcoded to false
                  await DebrifyTvPrefs.saveDebrifyTvProvider(defaultProvider);
                }

                showResetSuccess();
              },
            ),
          ],
        ),
      ),
    );
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return DebrifyTvSpotlightDialog(
            eyebrow: 'Debrify TV · applies to every channel',
            title: 'Channel playback',
            subtitle:
                'Choose the provider, filters, and starting behavior used when a channel tunes.',
            icon: Icons.settings_rounded,
            maxWidth: 920,
            maxHeightFactor: .94,
            child: buildSettingsCard(
              scope: _SettingsScope.channels,
              includeNsfwToggle: false,
              title: 'Playback rules',
              dialogSetState: setDialogState,
            ),
            actions: [
              DebrifyTvDialogButton(
                autofocus: true,
                label: 'Done',
                icon: Icons.check_rounded,
                tone: DebrifyTvDialogButtonTone.primary,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      );
    },
  );
}
