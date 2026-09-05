import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/debrify_tv/import_results.dart';
import '../../models/debrify_tv/channel.dart';
import '../../services/community/magnet_yaml_service.dart';
import '../../services/debrify_tv_zip_importer.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/tv_text_field.dart';
import 'dialogs/spotlight_dialog.dart';

/// Share-dialog size/compression/keyword chip. Origin `_SpotlightMetaPill`
/// in `lib/screens/magic_tv_screen.dart` (only used by channel share).
class SpotlightMetaPill extends StatelessWidget {
  final String label;
  final String value;

  const SpotlightMetaPill({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: tv.fillWeak,
        borderRadius: app.shape.br(13),
        border: Border.all(color: tv.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: tv.textFaint,
              fontFamily: 'JetBrainsMono',
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: app.core.tx,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Origin `_showChannelExportUnavailableOnAppleTv`.
Future<void> showChannelExportUnavailableOnAppleTv(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (dialogContext) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(dialogContext).pop();
      },
      child: DebrifyTvSpotlightDialog(
        eyebrow: 'Channel export · Apple TV',
        title: 'Export from another device',
        subtitle:
            'Apple TV does not expose a location where Debrify can save a '
            'portable ZIP. Export the channels from Debrify on a phone or '
            'computer, or send them through Remote.',
        icon: Icons.tv_rounded,
        maxWidth: 580,
        actions: <Widget>[
          DebrifyTvDialogButton(
            autofocus: true,
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

/// Origin `_promptImportUrl`.
Future<String?> promptImportUrl(BuildContext context) async {
  final controller = TextEditingController();
  String? errorText;
  final FocusNode urlFocusNode = FocusNode(
    debugLabel: 'ZipUrlField',
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) {
        return KeyEventResult.ignored;
      }
      final focusContext = node.context;
      if (focusContext == null) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        FocusScope.of(focusContext).nextFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        FocusScope.of(focusContext).previousFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final app = AppThemeScope.of(context);
          return DebrifyTvSpotlightDialog(
            eyebrow: 'Import · from a link',
            title: 'Paste a channel link',
            subtitle:
                'Use a debrify:// share link or an http(s) URL to a supported channel file.',
            icon: Icons.link_rounded,
            maxWidth: 650,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TvTextField(
                  controller: controller,
                  accent: app.settings.accent,
                  keyboardGround: app.youtube.keyboardPanel,
                  keyboardInk: app.core.tx,
                  keyboardInkOnAccent: app.inkOn(app.settings.accent),
                  decoration: InputDecoration(
                    labelText: 'Debrify link or file URL',
                    hintText: 'debrify://channel?... or https://...',
                    errorText: errorText,
                  ),
                  autofocus: true,
                  focusNode: urlFocusNode,
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),
                Text(
                  'Supported: .zip · .yaml · .txt · .debrify',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    color: app.debrifyTv.textFaint,
                  ),
                ),
              ],
            ),
            actions: [
              DebrifyTvDialogButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              DebrifyTvDialogButton(
                label: 'Import',
                icon: Icons.download_rounded,
                tone: DebrifyTvDialogButtonTone.primary,
                onPressed: () {
                  final candidate = controller.text.trim();
                  if (candidate.isEmpty) {
                    setState(() {
                      errorText = 'Enter a link or URL to continue.';
                    });
                    return;
                  }

                  // Check if it's a debrify link (valid and accepted)
                  if (MagnetYamlService.isMagnetLink(candidate)) {
                    Navigator.of(dialogContext).pop(candidate);
                    return;
                  }

                  // Otherwise validate as http(s) URL
                  try {
                    final parsed = Uri.parse(candidate);
                    if (!parsed.hasAbsolutePath ||
                        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
                      throw const FormatException('invalid');
                    }
                  } catch (_) {
                    setState(() {
                      errorText =
                          'Enter a valid debrify:// link or http(s) URL.';
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop(candidate);
                },
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  urlFocusNode.dispose();
  return result;
}

/// Origin `_showZipImportSummary` dialog body (snacks stay on the caller).
Future<void> showZipImportSummaryDialog({
  required BuildContext context,
  required DebrifyTvZipImportResult parsed,
  required ZipImportPersistenceResult persisted,
}) {
  final bool hasSuccess = persisted.successes.isNotEmpty;
  final List<ZipImportFailureDisplay> failureRows = [
    ...parsed.failures.map(
      (failure) => ZipImportFailureDisplay(
        sourceName: failure.entryName,
        reason: failure.reason,
      ),
    ),
    ...persisted.failures.map(
      (failure) => ZipImportFailureDisplay(
        sourceName: failure.sourceName.isEmpty
            ? failure.channelName
            : failure.sourceName,
        reason: failure.reason,
      ),
    ),
  ];

  final String dialogTitle = hasSuccess
      ? 'Zip import complete'
      : 'Zip import failed';

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final tv = AppThemeScope.of(dialogContext).debrifyTv;
      return DebrifyTvSpotlightDialog(
        eyebrow: 'Import · summary',
        title: dialogTitle,
        subtitle: hasSuccess
            ? 'Your imported channels are ready to tune.'
            : 'Nothing was changed. Review the issues below and try again.',
        icon: hasSuccess
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
        maxWidth: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasSuccess) ...[
              Text(
                'Imported ${persisted.successes.length} channel${persisted.successes.length == 1 ? '' : 's'}.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...persisted.successes.map(
                (success) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.check_circle, size: 20),
                  title: Text(success.channelName),
                  subtitle: Text(
                    '${success.keywordCount} keyword${success.keywordCount == 1 ? '' : 's'} • ${success.torrentCount} torrent${success.torrentCount == 1 ? '' : 's'}',
                    style: TextStyle(color: tv.textDim),
                  ),
                ),
              ),
            ] else ...[
              const Text('No channels were imported.'),
            ],
            if (failureRows.isNotEmpty) ...[
              if (hasSuccess) const SizedBox(height: 12),
              Text(
                'Issues detected:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ...failureRows.map(
                (failure) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(
                    Icons.error_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                  title: Text(failure.sourceName),
                  subtitle: Text(failure.reason),
                ),
              ),
            ],
          ],
        ),
        actions: [
          DebrifyTvDialogButton(
            autofocus: true,
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}

/// Rows used by [showZipImportSummary] after the dialog closes.
List<ZipImportFailureDisplay> zipImportFailureRows(
  DebrifyTvZipImportResult parsed,
  ZipImportPersistenceResult persisted,
) {
  return [
    ...parsed.failures.map(
      (failure) => ZipImportFailureDisplay(
        sourceName: failure.entryName,
        reason: failure.reason,
      ),
    ),
    ...persisted.failures.map(
      (failure) => ZipImportFailureDisplay(
        sourceName: failure.sourceName.isEmpty
            ? failure.channelName
            : failure.sourceName,
        reason: failure.reason,
      ),
    ),
  ];
}

/// Origin share-channel magnet dialog.
Future<void> showShareChannelLinkDialog({
  required BuildContext context,
  required DebrifyTvChannel channel,
  required String magnetLink,
  required String linkSizeLabel,
  required String compressionLabel,
  required VoidCallback onCopied,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) {
      final app = AppThemeScope.of(dialogContext);
      final tv = app.debrifyTv;
      return DebrifyTvSpotlightDialog(
        eyebrow:
            'Share channel · ${channel.channelNumber.toString().padLeft(2, '0')}',
        title: channel.name,
        subtitle:
            'Anyone on Debrify can paste this link to import the channel and its saved pool.',
        icon: Icons.share_rounded,
        maxWidth: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: tv.dialogDeep.withValues(alpha: .72),
                borderRadius: app.shape.br(16),
                border: Border.all(color: tv.hairline),
              ),
              child: SelectableText(
                magnetLink,
                style: TextStyle(
                  color: tv.textDim,
                  fontSize: 10,
                  height: 1.5,
                  fontFamily: 'JetBrainsMono',
                ),
                maxLines: 6,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SpotlightMetaPill(label: 'Link size', value: linkSizeLabel),
                SpotlightMetaPill(
                  label: 'Compression',
                  value: compressionLabel,
                ),
                SpotlightMetaPill(
                  label: 'Keywords',
                  value: '${channel.keywords.length}',
                ),
              ],
            ),
          ],
        ),
        actions: [
          DebrifyTvDialogButton(
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          DebrifyTvDialogButton(
            autofocus: true,
            label: 'Copy link',
            icon: Icons.copy_rounded,
            tone: DebrifyTvDialogButtonTone.primary,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: magnetLink));
              onCopied();
              Navigator.of(dialogContext).pop();
            },
          ),
        ],
      );
    },
  );
}
