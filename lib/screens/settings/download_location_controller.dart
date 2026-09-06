import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../services/android_native_downloader.dart';
import '../../services/storage/download_destination_prefs.dart';
import '../../theme/app_theme_scope.dart';

/// Download-location picker extracted from [SettingsScreen].
///
/// Android uses SAF; Windows/Linux use a plain picked path. macOS is
/// deliberately excluded: the sandbox grants read-only user-selected access,
/// so a writable custom folder needs security-scoped bookmarks (own feature).
class DownloadLocationController {
  DownloadLocationController({
    required this.isMounted,
    required this.setState,
    required this.contextOf,
  });

  final bool Function() isMounted;
  final void Function(VoidCallback fn) setState;
  final BuildContext Function() contextOf;

  String downloadLocationSubtitle = 'Downloads/Debrify (default)';

  bool get downloadLocationSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isLinux);

  bool get downloadLocationUsesSaf => !kIsWeb && Platform.isAndroid;

  String get defaultDownloadLocationLabel {
    if (downloadLocationUsesSaf || Platform.isWindows) {
      return 'Downloads/Debrify (default)';
    }
    // Linux: getDownloadsDirectory isn't used there — the app writes under
    // its documents dir (see DownloadService._appDownloadsSubdir fallback).
    return 'App folder (default)';
  }

  Future<void> loadDownloadLocation() async {
    if (!downloadLocationSupported) return;
    final String? name = downloadLocationUsesSaf
        ? await DownloadDestinationPrefs.getDownloadTreeDisplayName()
        : await DownloadDestinationPrefs.getDownloadDirPath();
    if (!isMounted()) return;
    setState(() {
      downloadLocationSubtitle = name == null
          ? defaultDownloadLocationLabel
          : 'Custom: $name';
    });
  }

  Future<void> openDownloadLocationSettings() async {
    final String? currentTree = downloadLocationUsesSaf
        ? await DownloadDestinationPrefs.getDownloadTreeUri()
        : await DownloadDestinationPrefs.getDownloadDirPath();
    if (!isMounted()) return;
    final context = contextOf();
    await showModalBottomSheet<void>(
      // Origin used State.context after `if (!mounted) return`.
      // ignore: use_build_context_synchronously
      context: context,
      // ignore: use_build_context_synchronously
      backgroundColor: AppThemeScope.of(context).settings.sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: const Text('Download location'),
                subtitle: Text(downloadLocationSubtitle),
              ),
              const Divider(height: 1),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.drive_folder_upload_rounded),
                title: const Text('Choose folder…'),
                subtitle: Text(
                  downloadLocationUsesSaf
                      ? 'Pick any folder, including an SD card. New downloads go there.'
                      : 'Pick any folder, including another drive. New downloads go there.',
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  chooseDownloadFolder();
                },
              ),
              if (currentTree != null)
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Reset to default'),
                  subtitle: Text(
                    'Save to ${defaultDownloadLocationLabel.replaceAll(' (default)', '')} again',
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    resetDownloadFolder();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> chooseDownloadFolder() async {
    if (!downloadLocationUsesSaf) {
      await chooseDownloadFolderDesktop();
      return;
    }
    final res = await AndroidNativeDownloader.pickDownloadDirectory();
    if (res == null) return; // user backed out of the picker
    final newTree = (res['treeUri'] ?? '').toString();
    final name = (res['displayName'] ?? 'Custom folder').toString();
    if (newTree.isEmpty) return;
    final old = await DownloadDestinationPrefs.getDownloadTreeUri();
    if (old != null && old.isNotEmpty && old != newTree) {
      // Release the previous grant — persisted-permission slots are limited.
      await AndroidNativeDownloader.releaseDownloadDirectory(old);
    }
    await DownloadDestinationPrefs.setDownloadTreeUri(newTree, name);
    await loadDownloadLocation();
    if (!isMounted()) return;
    ScaffoldMessenger.of(contextOf()).showSnackBar(
      SnackBar(content: Text('New downloads will be saved to "$name"')),
    );
  }

  /// Windows/Linux: a picked folder is a plain path — no grants to manage,
  /// but verify it's writable before persisting so the pref can't be born
  /// pointing at a read-only location.
  Future<void> chooseDownloadFolderDesktop() async {
    String? dir;
    try {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose download folder',
      );
    } catch (e) {
      // file_picker shells out to zenity/qarma/kdialog on Linux and throws
      // when none is installed — surface it instead of failing silently.
      if (!isMounted()) return;
      ScaffoldMessenger.of(contextOf()).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't open a folder picker on this system (a dialog tool like zenity may be missing).",
          ),
        ),
      );
      return;
    }
    if (dir == null || dir.trim().isEmpty) return; // user backed out
    // Normalize (also drops any trailing separator, so a drive-root pick
    // like "C:\" can't render doubled separators downstream).
    dir = path.normalize(dir.trim());
    // UNC network shares break background_downloader's task construction
    // (its Task constructor strips the leading backslash) — refuse rather
    // than accept a folder downloads can't actually reach.
    if (Platform.isWindows && dir.startsWith(r'\\')) {
      if (!isMounted()) return;
      ScaffoldMessenger.of(contextOf()).showSnackBar(
        const SnackBar(
          content: Text(
            'Network shares aren\'t supported yet — map the share to a drive letter or pick a local folder.',
          ),
        ),
      );
      return;
    }
    bool writable = false;
    try {
      final probe = File(
        path.join(
          dir,
          '.debrify_write_probe_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      await probe.writeAsString('probe', flush: true);
      // Write success alone proves writability; delete is best-effort (a
      // Windows AV/indexer lock on the fresh file must not fail the pick).
      try {
        await probe.delete();
      } catch (_) {}
      writable = true;
    } catch (_) {}
    if (!writable) {
      if (!isMounted()) return;
      ScaffoldMessenger.of(contextOf()).showSnackBar(
        const SnackBar(
          content: Text("That folder isn't writable — pick another one."),
        ),
      );
      return;
    }
    await DownloadDestinationPrefs.setDownloadDirPath(dir);
    await loadDownloadLocation();
    if (!isMounted()) return;
    ScaffoldMessenger.of(contextOf()).showSnackBar(
      SnackBar(content: Text('New downloads will be saved to "$dir"')),
    );
  }

  Future<void> resetDownloadFolder() async {
    if (downloadLocationUsesSaf) {
      final old = await DownloadDestinationPrefs.getDownloadTreeUri();
      if (old != null && old.isNotEmpty) {
        await AndroidNativeDownloader.releaseDownloadDirectory(old);
      }
      await DownloadDestinationPrefs.clearDownloadTreeUri();
    } else {
      await DownloadDestinationPrefs.clearDownloadDirPath();
    }
    await loadDownloadLocation();
    if (!isMounted()) return;
    ScaffoldMessenger.of(contextOf()).showSnackBar(
      SnackBar(
        content: Text(
          'Downloads will be saved to ${defaultDownloadLocationLabel.replaceAll(' (default)', '')}',
        ),
      ),
    );
  }
}
