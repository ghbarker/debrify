import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/debrify_tv/channel.dart';
import '../../models/debrify_tv/import_results.dart';
import '../../models/debrify_tv_cache.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../../models/profiles/profile_policy.dart';
import '../../screens/debrify_tv/dialogs/community_channels_dialog.dart';
import '../../screens/debrify_tv/dialogs/export_channels_dialog.dart';
import '../../screens/debrify_tv/dialogs/import_channels_dialog.dart';
import '../../screens/debrify_tv/import_export_dialogs.dart';
import '../../screens/debrify_tv/watch_session.dart';
import '../../screens/settings/profile_backup_flows.dart';
import '../../services/community/community_channel_model.dart';
import '../../services/community/community_channels_service.dart';
import '../../services/community/magnet_yaml_service.dart';
import '../../services/debrify_tv_cache_service.dart';
import '../../services/debrify_tv_channel_archive_service.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/debrify_tv_zip_importer.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../utils/platform_util.dart';

/// Origin `_ChannelImportOrigin`.
enum ChannelImportOrigin { device, url }

/// Origin `_ChannelImportType`.
enum ChannelImportType { zip, yaml, text, debrify }

/// Host seam for M1-2. [ProgressSink] covers snack / progress; this adds
/// library mutation and the few UI hooks import/export still needs
/// (28 origin `setState` calls go through [applyImportState]).
abstract class ChannelImportExportHost implements ProgressSink {
  bool get importExportMounted;
  BuildContext get importExportContext;
  bool get isAndroidTv;
  bool get isBusy;
  set isBusy(bool value);
  set status(String value);
  List<DebrifyTvChannel> get channels;
  set channels(List<DebrifyTvChannel> value);
  Map<String, DebrifyTvChannelCacheEntry> get channelCache;

  void applyImportState(VoidCallback fn);
  void showImportProgress(String title);
  Future<void> reloadImportedChannels();
  Future<void> createImportedTextChannel(DebrifyTvChannel channel);
  Future<bool> confirmDeleteAll({required int channelCount});
}

/// Origin `_formatBytes`.
String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final exponent = min(units.length - 1, (log(bytes) / log(1024)).floor());
  final value = bytes / pow(1024, exponent);
  final formatted = value >= 10
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[exponent]}';
}

/// Origin `_formatImportError`.
String formatImportError(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  return error.toString().replaceFirst('Exception: ', '').trim();
}

/// Origin `_stripExtension`.
String stripExtension(String name) {
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0) {
    return name.trim();
  }
  return name.substring(0, dotIndex).trim();
}

/// Origin `_guessExtensionFromHeaders`.
String guessExtensionFromHeaders(Map<String, String> headers) {
  final contentType =
      headers['content-type'] ?? headers['Content-Type'] ?? 'text/plain';
  if (contentType.contains('zip')) {
    return 'zip';
  }
  if (contentType.contains('yaml') || contentType.contains('yml')) {
    return 'yaml';
  }
  return 'txt';
}

/// Origin `_determineImportType`.
ChannelImportType? determineImportType(String sourceName, Uint8List bytes) {
  final lower = sourceName.toLowerCase();

  // Check extension first
  if (lower.endsWith('.zip')) {
    return ChannelImportType.zip;
  }
  if (lower.endsWith('.debrify')) {
    return ChannelImportType.debrify;
  }
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
    return ChannelImportType.yaml;
  }
  if (lower.endsWith('.txt')) {
    return ChannelImportType.text;
  }

  // Fallback: check file signature for zip
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    // PK — zip signature
    return ChannelImportType.zip;
  }

  // Smart content detection for unknown extensions
  try {
    final content = utf8.decode(bytes).trim();
    if (content.startsWith('debrify://')) {
      return ChannelImportType.debrify;
    }
  } catch (_) {
    // If UTF-8 decode fails, not a text file
  }

  return null;
}

/// Origin `_resolveUniqueChannelName`.
String resolveUniqueChannelName(
  String baseName,
  Set<String> usedLowerCaseNames,
) {
  final String trimmed = baseName.trim().isEmpty
      ? 'Imported Channel'
      : baseName.trim();
  String candidate = trimmed;
  int suffix = 2;
  while (usedLowerCaseNames.contains(candidate.toLowerCase())) {
    candidate = '$trimmed ($suffix)';
    suffix++;
  }
  return candidate;
}

/// Origin `_escapeYamlString`.
String escapeYamlString(String value) {
  // Escape special characters for YAML string
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
}

Future<DebrifyTvZipImportResult> parseZipInBackground(Uint8List bytes) {
  return compute(parseZipCompute, bytes);
}

DebrifyTvZipImportResult parseZipCompute(Uint8List bytes) {
  return DebrifyTvZipImporter.parseZip(bytes);
}

Future<DebrifyTvZipImportedChannel> parseYamlInBackground(
  String sourceName,
  String content,
) {
  return compute(parseYamlCompute, <String, String>{
    'sourceName': sourceName,
    'content': content,
  });
}

DebrifyTvZipImportedChannel parseYamlCompute(Map<String, String> payload) {
  final sourceName = payload['sourceName'] ?? 'channel.yaml';
  final content = payload['content'] ?? '';
  return DebrifyTvZipImporter.parseYaml(
    sourceName: sourceName,
    content: content,
  );
}

/// Channel import/export extracted from `lib/screens/magic_tv_screen.dart`
/// (M1-2). Seam is [ChannelImportExportHost] / [ProgressSink] + `channels`
/// / `channelCache`. Create/update dialogs and watch flows stay on the host.
class ChannelImportExport {
  ChannelImportExport({required this.host});

  final ChannelImportExportHost host;

  static const int maxChannelKeywords = 1000;

  Future<void> handleImportChannels() async {
    if (host.isBusy) {
      return;
    }

    // Set busy to block interactions during dialog
    host.applyImportState(() {
      host.isBusy = true;
    });

    final mode = await selectImportMode();

    // Wait for frames to ensure UI has updated and touch events are processed
    if (host.importExportMounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (mode == null || !host.importExportMounted) {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
        });
      }
      return;
    }

    switch (mode) {
      case ImportChannelsMode.device:
        await _handleImportChannelsFromDevice();
        break;
      case ImportChannelsMode.url:
        await handleImportChannelsFromUrl();
        break;
      case ImportChannelsMode.community:
        await handleImportChannelsFromCommunity();
        break;
    }
  }

  Future<ImportChannelsMode?> selectImportMode() async {
    if (!host.importExportMounted) {
      return null;
    }

    return showDialog<ImportChannelsMode>(
      context: host.importExportContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return ImportChannelsDialog(isAndroidTv: host.isAndroidTv);
      },
    );
  }

  Future<T> runChannelExportProgress<T>(
    Future<T> Function(void Function(String) setStage) run,
  ) async {
    if (!host.importExportMounted) {
      throw StateError('Channel export screen is no longer available');
    }
    final stage = ValueNotifier<String>('Reading selected channel pools…');
    final done = ValueNotifier<bool>(false);
    final dialog = showDialog<void>(
      context: host.importExportContext,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (_) => ChannelExportProgressDialog(stage: stage, done: done),
    );
    try {
      return await run((value) => stage.value = value);
    } finally {
      done.value = true;
      await dialog;
      stage.dispose();
      done.dispose();
    }
  }

  Future<void> handleExportChannels() async {
    if (host.isBusy || !host.importExportMounted) return;
    if (PlatformUtil.isTvOS) {
      await showChannelExportUnavailableOnAppleTv(host.importExportContext);
      return;
    }

    host.applyImportState(() {
      host.isBusy = true;
      host.status = 'Loading channels for export…';
    });

    try {
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.debrifyTv,
      );
      Future<T> runCaptured<T>(Future<T> Function() body) =>
          capability == null ? body() : capability.runIfCurrent(body);

      final channels = await runCaptured(
        DebrifyTvRepository.instance.fetchAllChannels,
      );
      final health = await runCaptured(DebrifyTvCacheService.loadRailHealth);
      if (!host.importExportMounted) return;
      if (channels.isEmpty) {
        host.showSnack(
          'There are no channels to export.',
          color: Colors.orange,
        );
        return;
      }

      final exportContext = host.importExportContext;
      if (!exportContext.mounted) return;
      final selectedIds = await showDialog<Set<String>>(
        context: exportContext,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .72),
        builder: (_) => ExportChannelsDialog(
          channels: channels,
          savedHashCounts: <String, int>{
            for (final entry in health.entries) entry.key: entry.value.pooled,
          },
        ),
      );
      if (!host.importExportMounted ||
          selectedIds == null ||
          selectedIds.isEmpty) {
        return;
      }

      host.applyImportState(() => host.status = 'Preparing channel archive…');
      late List<DebrifyTvChannelArchiveSource> sources;
      final bytes = await runChannelExportProgress<Uint8List>((setStage) async {
        sources = await runCaptured(() async {
          // Re-read after the selection dialog: a channel can be edited or
          // removed while an overlay is open, and the archive must reflect
          // the rows that actually exist at export time.
          final current = await DebrifyTvRepository.instance.fetchAllChannels();
          final selected = current
              .where((channel) => selectedIds.contains(channel.channelId))
              .toList(growable: false);
          final result = <DebrifyTvChannelArchiveSource>[];
          for (var index = 0; index < selected.length; index++) {
            final channel = selected[index];
            setStage(
              'Reading channel ${index + 1} of ${selected.length}: '
              '${channel.name}',
            );
            result.add(
              DebrifyTvChannelArchiveSource(
                channel: channel,
                cacheEntry:
                    await DebrifyTvCacheService.getEntryForPortableExport(
                      channel.channelId,
                    ),
              ),
            );
          }
          return result;
        });
        if (sources.isEmpty) {
          throw StateError('The selected channels are no longer available');
        }
        setStage('Compressing ${sources.length} channels into one ZIP…');
        return DebrifyTvChannelArchiveService.buildZip(sources);
      });
      if (!host.importExportMounted) return;
      if (bytes.length > DebrifyTvZipImporter.maxPortableFileBytes) {
        host.showSnack(
          'The ZIP is over 100 MB. Export fewer channels at a time.',
          color: Colors.orange,
        );
        return;
      }

      if (capability != null) {
        await capability.runIfCurrent(() async {});
      }
      if (!host.importExportMounted) return;
      final now = DateTime.now();
      final stamp = <int>[
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ].map((part) => part.toString().padLeft(2, '0')).join();
      final saveContext = host.importExportContext;
      if (!saveContext.mounted) return;
      final savedPath = await ProfileBackupFlows(saveContext)
          .saveBackupFile(
            fileName: 'debrify-tv-channels-$stamp.zip',
            bytes: bytes,
            mimeType: 'application/zip',
            artifactLabel: 'channel archive',
          );
      if (!host.importExportMounted || savedPath == null) return;
      final hashes = sources.fold<int>(
        0,
        (sum, source) => sum + source.savedHashCount,
      );
      host.showSnack(
        'Exported ${sources.length} channel${sources.length == 1 ? '' : 's'} '
        'with $hashes saved hash${hashes == 1 ? '' : 'es'}.',
        color: Colors.green,
      );
    } catch (error) {
      debugPrint(
        'DebrifyTV: channel archive export failed (${error.runtimeType})',
      );
      if (host.importExportMounted) {
        host.showSnack('Failed to export channels.', color: Colors.red);
      }
    } finally {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
          host.status = '';
        });
      }
    }
  }

  Future<void> _handleImportChannelsFromDevice() async {
    // FileType.any instead of custom: Android has no MimeTypeMap entry for
    // `yaml`/`yml`/`debrify`, so a custom filter silently greys those files out
    // in the system picker (and throws "Unsupported filter" outright when every
    // extension is unmapped). The importer validates the bytes/format below.
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      withReadStream: true,
    );

    if (selection == null || selection.files.isEmpty) {
      return;
    }

    final pickedFile = selection.files.first;

    // Reject an implausibly large pick before reading it into memory.
    if (pickedFile.size > DebrifyTvZipImporter.maxPortableFileBytes) {
      host.showSnack(
        'Selected file is too large to import.',
        color: Colors.orange,
      );
      return;
    }
    Uint8List bytes;
    try {
      bytes = await readPickedFileBytes(pickedFile);
    } catch (error) {
      host.showSnack(
        'Unable to read selected file: ${formatImportError(error)}',
        color: Colors.red,
      );
      return;
    }

    if (bytes.isEmpty) {
      host.showSnack(
        'Selected file appears to be empty.',
        color: Colors.orange,
      );
      return;
    }

    if (!host.importExportMounted) {
      return;
    }

    host.applyImportState(() {
      host.isBusy = true;
      host.status = 'Importing channel from local storage…';
    });

    try {
      await safeImportChannelBytes(
        sourceName: pickedFile.name,
        bytes: bytes,
        origin: ChannelImportOrigin.device,
      );
    } catch (error) {
      host.showSnack(
        'Import failed: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
          host.status = '';
        });
        host.closeProgressDialog();
      }
    }
  }

  Future<void> handleImportChannelsFromUrl() async {
    if (!host.importExportMounted) {
      return;
    }
    final input = await promptImportUrl(host.importExportContext);
    if (input == null) {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
        });
      }
      return;
    }

    final trimmedInput = input.trim();

    // Check if it's a debrify link (pasted directly)
    if (MagnetYamlService.isMagnetLink(trimmedInput)) {
      await importDebrifyLinkDirectly(trimmedInput);
      return;
    }

    // Otherwise, treat as URL
    Uri uri;
    try {
      uri = Uri.parse(trimmedInput);
      if (!uri.hasAbsolutePath ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const FormatException('invalid');
      }
    } catch (_) {
      host.showSnack(
        'Enter a valid debrify:// link or http(s) URL.',
        color: Colors.red,
      );
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
        });
      }
      return;
    }

    if (!host.importExportMounted) {
      return;
    }

    host.applyImportState(() {
      host.isBusy = true;
      host.status = 'Downloading channel file…';
    });

    host.showImportProgress('Importing channel…');
    host.updateProgress(['Downloading channel file…']);

    try {
      final streamedResponse = await http.Request('GET', uri).send();
      if (streamedResponse.statusCode != 200) {
        throw FormatException('HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;
      final builder = BytesBuilder(copy: false);

      await for (final chunk in streamedResponse.stream) {
        builder.add(chunk);
        receivedBytes += chunk.length;
        final percent = totalBytes > 0
            ? (receivedBytes / totalBytes * 100).clamp(0, 100)
            : null;
        final progressMessage = percent != null
            ? 'Downloading… ${percent.toStringAsFixed(0)}%'
            : 'Downloading… ${formatBytes(receivedBytes)}';
        host.updateProgress([progressMessage], replace: true);
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        host.updateProgress(['Downloaded file is empty.'], replace: true);
        host.showSnack('Downloaded file is empty.', color: Colors.orange);
        return;
      }

      final sourceName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'channel.${guessExtensionFromHeaders(streamedResponse.headers)}';

      host.updateProgress(['Download complete. Processing…'], replace: true);

      await safeImportChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: ChannelImportOrigin.url,
      );
    } catch (error) {
      host.showSnack(
        'Import failed: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
          host.status = '';
        });
        host.closeProgressDialog();
      }
    }
  }

  Future<void> handleImportChannelsFromCommunity() async {
    final selectedChannels = await promptCommunityChannelsDialog();
    if (selectedChannels == null || selectedChannels.isEmpty) {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
        });
      }
      return;
    }

    // Wait for frames to ensure UI has updated and touch events are processed
    if (host.importExportMounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (!host.importExportMounted) {
      return;
    }

    host.applyImportState(() {
      host.isBusy = true;
      host.status = 'Importing community channels...';
    });

    host.showImportProgress('Importing community channels...');

    int successCount = 0;
    int failureCount = 0;
    final List<String> errors = [];

    for (int i = 0; i < selectedChannels.length; i++) {
      final channel = selectedChannels[i];
      host.updateProgress([
        'Downloading channel ${i + 1} of ${selectedChannels.length}...',
        channel.name,
      ], replace: true);

      try {
        // Download the channel file
        final bytes = await CommunityChannelsService.downloadChannelFile(
          channel.url,
        );

        if (bytes.isEmpty) {
          throw Exception('Downloaded file is empty');
        }

        // Import using existing method (don't show dialog/summary for each channel)
        final success = await importDebrifyBytes(
          channel.name,
          bytes,
          showDialog: false,
          showSummary: false,
        );

        if (success) {
          successCount++;
        } else {
          failureCount++;
          errors.add('${channel.name}: Import failed');
        }
      } catch (error) {
        failureCount++;
        errors.add('${channel.name}: ${error.toString()}');
      }
    }

    host.updateProgress([
      'Import complete!',
      if (successCount > 0) 'Successfully imported $successCount channel(s)',
      if (failureCount > 0) 'Failed to import $failureCount channel(s)',
      ...errors.take(5), // Show first 5 errors
    ], replace: true);

    // Show summary
    final Color snackColor = successCount > 0
        ? (failureCount > 0 ? Colors.orange : Colors.green)
        : Colors.red;

    final String message = successCount > 0
        ? 'Imported $successCount channel${successCount > 1 ? 's' : ''}${failureCount > 0 ? ', $failureCount failed' : ''}'
        : 'Failed to import channels';

    host.showSnack(message, color: snackColor);

    // Keep dialog open for 2 seconds to show summary
    await Future.delayed(const Duration(seconds: 2));

    if (host.importExportMounted) {
      host.applyImportState(() {
        host.isBusy = false;
        host.status = '';
      });
      host.closeProgressDialog();
    }
  }

  Future<List<CommunityChannel>?> promptCommunityChannelsDialog() async {
    if (!host.importExportMounted) {
      return null;
    }

    return showDialog<List<CommunityChannel>>(
      context: host.importExportContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return CommunityChannelsDialog(isAndroidTv: host.isAndroidTv);
      },
    );
  }

  Future<Uint8List> readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return Uint8List.fromList(file.bytes!);
    }

    final stream = file.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    }

    throw const FormatException('Unable to access file bytes.');
  }

  Future<bool> importChannelBytes({
    required String sourceName,
    required Uint8List bytes,
    required ChannelImportOrigin origin,
  }) async {
    final type = determineImportType(sourceName, bytes);
    if (type == null) {
      host.showSnack(
        'Unsupported file type. Select a .zip, .yaml, .txt, or .debrify file.',
        color: Colors.orange,
      );
      return false;
    }

    switch (type) {
      case ChannelImportType.zip:
        return await importZipBytes(bytes, origin);
      case ChannelImportType.yaml:
        return await importYamlBytes(sourceName, bytes, origin);
      case ChannelImportType.text:
        return await importTextBytes(sourceName, bytes);
      case ChannelImportType.debrify:
        return await importDebrifyBytes(sourceName, bytes);
    }
  }

  Future<bool> safeImportChannelBytes({
    required String sourceName,
    required Uint8List bytes,
    required ChannelImportOrigin origin,
  }) async {
    try {
      return await importChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: origin,
      );
    } on FormatException catch (error) {
      host.showSnack(error.message, color: Colors.red);
      return false;
    } catch (error) {
      // Corrupt archives throw ArchiveException/RangeError etc., not just
      // FormatException — surface them the same way instead of leaving the
      // import flow (and any progress dialog) stuck.
      host.showSnack(
        'Failed to import channel file: $error',
        color: Colors.red,
      );
      return false;
    }
  }

  Future<bool> importZipBytes(
    Uint8List bytes,
    ChannelImportOrigin origin,
  ) async {
    final dialogLabel = origin == ChannelImportOrigin.device
        ? 'Importing zip…'
        : 'Processing zip…';

    host.showImportProgress(dialogLabel);
    host.updateProgress(['Parsing archive…']);

    final parsed = await parseZipInBackground(bytes);
    host.updateProgress([
      'Parsed ${parsed.channels.length} channel(s)',
      'Saving channel data…',
    ]);

    final persistence = await persistImportedZipChannels(parsed.channels);
    host.updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await showZipImportSummary(parsed, persistence);
    return persistence.successes.isNotEmpty;
  }

  Future<bool> importYamlBytes(
    String sourceName,
    Uint8List bytes,
    ChannelImportOrigin origin,
  ) async {
    final content = utf8.decode(bytes);
    final dialogLabel = origin == ChannelImportOrigin.device
        ? 'Importing YAML…'
        : 'Processing YAML…';

    host.showImportProgress(dialogLabel);
    host.updateProgress(['Parsing YAML…']);

    final channel = await parseYamlInBackground(sourceName, content);

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    host.updateProgress(['Saving channel…']);
    final persistence = await persistImportedZipChannels(parsed.channels);
    host.updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await showZipImportSummary(parsed, persistence);
    return persistence.successes.isNotEmpty;
  }

  Future<bool> importTextBytes(String sourceName, Uint8List bytes) async {
    final content = utf8.decode(bytes);
    final keywords = <String>[];
    final seen = <String>{};

    final lines = const LineSplitter().convert(content);
    for (final rawLine in lines) {
      final parts = rawLine.split(',');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (trimmed.length > 120) {
          throw FormatException(
            'Keyword exceeds 120 characters: "${trimmed.substring(0, trimmed.length > 40 ? 40 : trimmed.length)}${trimmed.length > 40 ? '…' : ''}"',
          );
        }
        final lower = trimmed.toLowerCase();
        if (seen.add(lower)) {
          keywords.add(trimmed);
        }
      }
    }

    if (keywords.isEmpty) {
      throw const FormatException('No keywords found in the selected file.');
    }
    if (keywords.length > 500) {
      throw const FormatException(
        'Channel files must contain 500 keywords or fewer.',
      );
    }

    final baseName = stripExtension(sourceName);
    final lowerExisting = host.channels
        .map((c) => c.name.toLowerCase())
        .toSet();
    final channelName = resolveUniqueChannelName(baseName, lowerExisting);
    final now = DateTime.now();
    final channel = DebrifyTvChannel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: channelName,
      keywords: keywords,
      avoidNsfw: true,
      channelNumber: 0,
      createdAt: now,
      updatedAt: now,
    );

    await host.createImportedTextChannel(channel);
    host.showSnack('Imported "${channel.name}"', color: Colors.green);
    return true;
  }

  Future<bool> importDebrifyBytes(
    String sourceName,
    Uint8List bytes, {
    bool showDialog = true,
    bool showSummary = true,
  }) async {
    final content = utf8.decode(bytes).trim();

    // Validate debrify link format
    if (!MagnetYamlService.isMagnetLink(content)) {
      throw const FormatException('Not a valid Debrify link.');
    }

    if (showDialog) {
      host.showImportProgress('Importing channel…');
    }
    host.updateProgress(['Decoding debrify link…']);

    // Decode debrify link
    final result = MagnetYamlService.decode(content);

    host.updateProgress(['Parsing channel data…']);

    // Parse the decoded YAML
    final channel = await parseYamlInBackground(
      result.channelName,
      result.yamlContent,
    );

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    host.updateProgress(['Saving channel…']);
    final persistence = await persistImportedZipChannels(parsed.channels);
    host.updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    if (showSummary) {
      await showZipImportSummary(parsed, persistence);
    }
    return persistence.successes.isNotEmpty;
  }

  Future<void> importDebrifyLinkDirectly(String debrifyLink) async {
    if (!host.importExportMounted) {
      return;
    }

    host.applyImportState(() {
      host.isBusy = true;
      host.status = 'Decoding debrify link…';
    });

    try {
      final bytes = utf8.encode(debrifyLink);
      await safeImportChannelBytes(
        sourceName: 'debrify_link',
        bytes: Uint8List.fromList(bytes),
        origin: ChannelImportOrigin.url,
      );
    } catch (error) {
      host.showSnack(
        'Import failed: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
          host.status = '';
        });
        host.closeProgressDialog();
      }
    }
  }

  Future<ZipImportPersistenceResult> persistImportedZipChannels(
    List<DebrifyTvZipImportedChannel> channels,
  ) async {
    if (channels.isEmpty) {
      return const ZipImportPersistenceResult(successes: [], failures: []);
    }

    final successes = <ZipImportSuccess>[];
    final failures = <ZipImportSaveFailure>[];

    final List<DebrifyTvChannel> appendedChannels = [];
    final Map<String, DebrifyTvChannelCacheEntry> appendedCache = {};

    final Set<String> usedNames = host.channels
        .map((channel) => channel.name.toLowerCase())
        .toSet();

    for (final channel in channels) {
      if (channel.normalizedKeywords.length > maxChannelKeywords) {
        failures.add(
          ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: channel.channelName,
            reason:
                'Channel has ${channel.normalizedKeywords.length} keywords; maximum supported is $maxChannelKeywords.',
          ),
        );
        continue;
      }

      final uniqueName = resolveUniqueChannelName(
        channel.channelName,
        usedNames,
      );
      final channelId = DateTime.now().microsecondsSinceEpoch.toString();
      final now = DateTime.now();

      final record = DebrifyTvChannelRecord(
        channelId: channelId,
        name: uniqueName,
        keywords: channel.displayKeywords,
        avoidNsfw: channel.avoidNsfw,
        channelNumber: 0,
        createdAt: now,
        updatedAt: now,
      );

      final entry = DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channelId,
        normalizedKeywords: channel.normalizedKeywords,
        fetchedAt: now.millisecondsSinceEpoch,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        torrents: channel.torrents,
        keywordStats: channel.keywordStats,
      );

      try {
        await DebrifyTvRepository.instance.upsertChannel(record);
        await DebrifyTvCacheService.saveEntry(entry);

        appendedChannels.add(
          DebrifyTvChannel(
            id: channelId,
            name: uniqueName,
            keywords: const <String>[],
            avoidNsfw: channel.avoidNsfw,
            channelNumber: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
        appendedCache[channelId] = entry;

        successes.add(
          ZipImportSuccess(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            keywordCount: channel.normalizedKeywords.length,
            torrentCount: channel.torrentCount,
          ),
        );

        usedNames.add(uniqueName.toLowerCase());
      } catch (error) {
        failures.add(
          ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            reason: formatImportError(error),
          ),
        );
      }
    }

    if (appendedChannels.isNotEmpty && host.importExportMounted) {
      host.applyImportState(() {
        host.channels = [...host.channels, ...appendedChannels];
        host.channelCache.addAll(appendedCache);
      });
      await host.reloadImportedChannels();
    }

    return ZipImportPersistenceResult(successes: successes, failures: failures);
  }

  Future<void> showZipImportSummary(
    DebrifyTvZipImportResult parsed,
    ZipImportPersistenceResult persisted,
  ) async {
    if (!host.importExportMounted) {
      return;
    }

    final bool hasSuccess = persisted.successes.isNotEmpty;
    final List<ZipImportFailureDisplay> failureRows = zipImportFailureRows(
      parsed,
      persisted,
    );

    if (!hasSuccess && failureRows.isEmpty) {
      host.showSnack(
        'No channels found in the selected zip.',
        color: Colors.orange,
      );
      return;
    }

    await showZipImportSummaryDialog(
      context: host.importExportContext,
      parsed: parsed,
      persisted: persisted,
    );

    if (hasSuccess) {
      final String names = persisted.successes
          .map((success) => '"${success.channelName}"')
          .join(', ');
      host.showSnack(
        'Imported ${persisted.successes.length} channel${persisted.successes.length == 1 ? '' : 's'}: $names',
        color: Colors.green,
      );
    } else if (failureRows.isNotEmpty) {
      host.showSnack(
        'Zip import failed: ${failureRows.first.reason}',
        color: Colors.red,
      );
    }
  }

  Future<void> handleShareChannelAsMagnet(DebrifyTvChannel channel) async {
    if (!host.importExportMounted) {
      return;
    }

    host.applyImportState(() {
      host.isBusy = true;
      host.status = 'Generating channel link…';
    });

    try {
      // Generate YAML for sharing (with cached torrents from DB)
      final yamlContent = await generateChannelYaml(channel);

      // Encode as magnet link
      final magnetLink = MagnetYamlService.encode(
        yamlContent: yamlContent,
        channelName: channel.name,
      );

      // Estimate sizes for display
      final estimatedSize = MagnetYamlService.estimateMagnetLinkSize(
        yamlContent,
      );
      final compressionRatio = MagnetYamlService.getCompressionRatio(
        yamlContent,
      );

      if (!host.importExportMounted) {
        return;
      }

      final shareContext = host.importExportContext;
      if (!shareContext.mounted) return;
      await showShareChannelLinkDialog(
        context: shareContext,
        channel: channel,
        magnetLink: magnetLink,
        linkSizeLabel: formatBytes(estimatedSize),
        compressionLabel: '${compressionRatio.toStringAsFixed(1)}×',
        onCopied: () {
          host.showSnack('Channel link copied!', color: Colors.green);
        },
      );
    } catch (error) {
      host.showSnack(
        'Failed to generate channel link: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
          host.status = '';
        });
      }
    }
  }

  Future<String> generateChannelYaml(DebrifyTvChannel channel) async {
    // Generate YAML with channel config and torrent data from cache
    final buffer = StringBuffer();
    buffer.writeln('channel_name: "${channel.name}"');
    buffer.writeln('avoid_nsfw: ${channel.avoidNsfw}');
    buffer.writeln('');
    buffer.writeln('keywords:');

    // Get cached torrents from database (not in-memory cache)
    final cacheEntry = await DebrifyTvCacheService.getEntry(channel.id);
    final cachedTorrents = cacheEntry?.torrents ?? <CachedTorrent>[];
    for (final keyword in channel.keywords) {
      buffer.writeln('  $keyword:');

      // Find all torrents that match this keyword (case-insensitive)
      final keywordLower = keyword.toLowerCase();
      final matchingTorrents = cachedTorrents
          .where((t) => t.keywords.contains(keywordLower))
          .toList();

      // Dedupe by infohash
      final seen = <String>{};
      final uniqueTorrents = matchingTorrents.where((t) {
        if (seen.contains(t.infohash)) return false;
        seen.add(t.infohash);
        return true;
      }).toList();

      if (uniqueTorrents.isEmpty) {
        buffer.writeln('    torrents: []');
      } else {
        buffer.writeln('    torrents:');
        for (final torrent in uniqueTorrents) {
          // Output full torrent object for proper import
          buffer.writeln('      - infohash: ${torrent.infohash}');
          buffer.writeln('        name: "${escapeYamlString(torrent.name)}"');
          buffer.writeln('        size_bytes: ${torrent.sizeBytes}');
          buffer.writeln('        created_unix: ${torrent.createdUnix}');
          buffer.writeln('        seeders: ${torrent.seeders}');
          buffer.writeln('        leechers: ${torrent.leechers}');
          buffer.writeln('        completed: ${torrent.completed}');
          buffer.writeln('        scraped_date: ${torrent.scrapedDate}');
          if (torrent.sources.isNotEmpty) {
            buffer.writeln(
              '        sources: [${torrent.sources.map((s) => '"$s"').join(', ')}]',
            );
          }
        }
      }
    }

    return buffer.toString();
  }

  Future<void> handleDeleteAllChannels() async {
    if (host.channels.isEmpty) {
      host.showSnack('No channels to delete.', color: Colors.orange);
      return;
    }

    if (!host.importExportMounted) {
      return;
    }

    // Set busy immediately to block any other interactions
    host.applyImportState(() {
      host.isBusy = true;
    });

    final confirmed = await host.confirmDeleteAll(
      channelCount: host.channels.length,
    );

    // Wait for TWO frames to ensure UI has fully updated and touch events are processed
    if (host.importExportMounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (confirmed != true || !host.importExportMounted) {
      // Release busy state if cancelled
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
        });
      }
      return;
    }

    host.applyImportState(() {
      host.isBusy = true;
    });

    try {
      await DebrifyTvRepository.instance.clearAll();
      await DebrifyTvCacheService.clearAll();
      host.applyImportState(() {
        host.channels = const <DebrifyTvChannel>[];
        host.channelCache.clear();
      });
      host.showSnack('All channels deleted.', color: Colors.orange);
    } catch (error) {
      host.showSnack(
        'Failed to delete channels: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (host.importExportMounted) {
        host.applyImportState(() {
          host.isBusy = false;
        });
      }
    }
  }
}
