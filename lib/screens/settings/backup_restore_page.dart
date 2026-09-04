import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/account_service.dart';
import '../../services/alldebrid_account_service.dart';
import '../../services/backup_restore_service.dart';
import '../../services/iptv_transfer_payload.dart';
import '../../services/premiumize_account_service.dart';
import '../../services/profiles/portable_profile_package.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/torbox_account_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/tv_text_field.dart';
import 'profile_backup_flows.dart';
import 'widgets/settings_widgets.dart';

/// Data & Backup create/restore UI, extracted from [SettingsScreen].
///
/// Behavior is identical to the settings-screen originals. [onRestored]
/// replaces the screen-specific summary reload + integration notify the
/// settings page used to run inline after a successful restore.
class BackupRestorePage {
  const BackupRestorePage(this.context, {required this.onRestored});

  final BuildContext context;
  final Future<void> Function() onRestored;

  Future<void> _createProfileBackup() =>
      ProfileBackupFlows(context).createProfileBackup();

  Future<void> _restoreProfileBackup() async {
    await ProfileBackupFlows(
      context,
      onRestored: onRestored,
    ).restoreProfileBackup();
  }

  Future<void> createBackup() async {
    if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) {
      await _createProfileBackup();
      return;
    }
    final app = AppThemeScope.of(context);
    // Build the payload first so we can warn if it's empty.
    final Map<String, dynamic> payload;
    try {
      payload = await BackupRestoreService.buildBackup();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to build the backup')),
      );
      return;
    }

    final summary = BackupRestoreService.summarize(payload);
    if (summary.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to back up — no services are configured.'),
        ),
      );
      return;
    }

    // File-imported IPTV playlists are left out of the payload on purpose —
    // say so rather than let the user discover it after a restore.
    final iptvProviders = await IptvTransferPayload.countPlaylists();

    if (!context.mounted) return;
    var includeCredentials = true;
    var usePassphrase = false;
    final passphraseController = TextEditingController();
    final confirmController = TextEditingController();
    final passphraseFocus = FocusNode(debugLabel: 'backupPassphrase');
    final confirmFocus = FocusNode(debugLabel: 'backupPassphraseConfirmation');
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final passphraseOk =
              !usePassphrase ||
              (passphraseController.text.isNotEmpty &&
                  passphraseController.text == confirmController.text);
          return AlertDialog(
            title: const Text('Create backup'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The backup will include:'),
                  const SizedBox(height: 8),
                  ...backupSummaryLines(summary).map((line) => Text('• $line')),
                  if (iptvProviders.fileImported > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${iptvProviders.fileImported} IPTV playlist'
                        '${iptvProviders.fileImported == 1 ? '' : 's'} imported from '
                        'a file won\'t be included — re-import the file on the other '
                        'device. Starred channels from them still travel.',
                        style: TextStyle(
                          fontSize: 12,
                          color: app.fade(app.core.tx, 0x99 / 0xFF),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Include credentials'),
                    subtitle: const Text(
                      'Off: share your setup without your accounts. Skips '
                      'anything that embeds them: addons, Xtream providers, '
                      'indexers, starred channels and lists. M3U URLs are '
                      'kept — use a passphrase to protect those.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: includeCredentials,
                    onChanged: (v) =>
                        setDialogState(() => includeCredentials = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Encrypt with a passphrase'),
                    value: usePassphrase,
                    onChanged: (v) => setDialogState(() => usePassphrase = v),
                  ),
                  if (usePassphrase) ...[
                    TvTextField(
                      controller: passphraseController,
                      focusNode: passphraseFocus,
                      obscureText: true,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      keyboardSubmitLabel: 'Next',
                      decoration: const InputDecoration(
                        labelText: 'Passphrase',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) => confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: 8),
                    TvTextField(
                      controller: confirmController,
                      focusNode: confirmFocus,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      keyboardSubmitLabel: 'Save backup',
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) {
                        if (passphraseOk) Navigator.of(context).pop(true);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (usePassphrase)
                    Text(
                      'Encrypted with your passphrase — if you forget it, '
                      'this backup cannot be opened.',
                      style: TextStyle(
                        fontSize: 12,
                        color: app.fade(app.core.tx, 0x99 / 0xFF),
                      ),
                    )
                  else if (includeCredentials)
                    const Text(
                      'Credentials are stored in plain text. Keep this file '
                      'private and treat it like a password.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: passphraseOk
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Save backup'),
              ),
            ],
          );
        },
      ),
    );

    final passphrase = usePassphrase ? passphraseController.text : null;
    passphraseController.dispose();
    confirmController.dispose();
    passphraseFocus.dispose();
    confirmFocus.dispose();
    if (confirmed != true) return;
    if (!context.mounted) return;

    // The pre-dialog payload was only for the summary — rebuild honoring the
    // include-credentials choice.
    Map<String, dynamic> exportMap = includeCredentials
        ? payload
        : await BackupRestoreService.buildBackup(includeCredentials: false);

    // The pre-dialog summary described the FULL payload — stripping
    // credentials can leave nothing behind (a device configured with only
    // accounts), and restore rejects an empty backup anyway.
    if (!includeCredentials &&
        BackupRestoreService.summarize(exportMap).isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing left to back up without credentials — everything on '
            'this device is account data.',
          ),
        ),
      );
      return;
    }

    if (passphrase != null && passphrase.isNotEmpty) {
      if (!context.mounted) return;
      // Captured BEFORE the await: the modal lives on the root navigator and
      // must be popped even if this screen unmounts while Argon2id runs —
      // a mounted-check first would strand an undismissable dialog.
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      // Argon2id takes seconds on TV hardware — show progress.
      showSettingsDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Encrypting backup…')),
              ],
            ),
          ),
        ),
      );
      try {
        exportMap = await BackupRestoreService.encryptBackup(
          exportMap,
          passphrase,
        );
      } catch (_) {
        rootNavigator.pop();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to encrypt the backup')),
        );
        return;
      }
      rootNavigator.pop();
      if (!context.mounted) return;
    }

    final jsonContent = const JsonEncoder.withIndent('  ').convert(exportMap);
    final bytes = Uint8List.fromList(utf8.encode(jsonContent));
    final fileName = backupExportFileName(DateTime.now());

    try {
      final savedPath = await ProfileBackupFlows(
        context,
      ).saveBackupFile(fileName: fileName, bytes: bytes);
      if (!context.mounted || savedPath == null) return;
      // On Android, savedPath may be a content:// URI from the Storage
      // Access Framework — show it raw so the user has at least a
      // breadcrumb of where the backup went.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved to $savedPath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save the backup')),
      );
    }
  }

  /// Passphrase prompt loop for an encrypted backup envelope. Returns the
  /// decrypted inner payload, or null when the user cancels. A wrong
  /// passphrase re-shows the prompt with an inline error instead of aborting.
  Future<Map<String, dynamic>?> _promptAndDecryptBackup(
    Map<String, dynamic> envelope,
  ) async {
    String? errorText;
    while (true) {
      if (!context.mounted) return null;
      final controller = TextEditingController();
      final entered = await showSettingsDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Backup is encrypted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (envelope['createdAt'] is String)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Created: ${envelope['createdAt']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                TvTextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Unlock',
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    errorText: errorText,
                  ),
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      );
      controller.dispose();
      if (entered == null || entered.isEmpty) return null;
      if (!context.mounted) return null;

      // Captured BEFORE the await so the modal is popped even if this screen
      // unmounts while the KDF runs (see _createBackup's encrypt block).
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      showSettingsDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Unlocking backup…')),
              ],
            ),
          ),
        ),
      );
      try {
        final inner = await BackupRestoreService.decryptBackup(
          envelope,
          entered,
        );
        rootNavigator.pop();
        if (!context.mounted) return null;
        return inner;
      } on BackupPassphraseException {
        rootNavigator.pop();
        if (!context.mounted) return null;
        errorText = 'Wrong passphrase — try again';
      } on FormatException {
        rootNavigator.pop();
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The backup format is invalid')),
        );
        return null;
      }
    }
  }

  Future<void> restoreBackup() async {
    if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) {
      await _restoreProfileBackup();
      return;
    }
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final FilePickerResult? pick;
    try {
      // FileType.any instead of custom: Android's MIME mapping for `json` is
      // unreliable and throws PlatformException("Unsupported filter") on many
      // devices, leaving the backup unselectable. The contents are validated by
      // BackupRestoreService.parse below, so no extension filter is needed.
      pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose Debrify backup file',
        type: FileType.any,
        withData: false,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file picker')),
      );
      return;
    }

    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.first;

    // FileType.any lets the user pick anything. Reject an implausibly large
    // file before opening it so a stray huge selection cannot be allocated.
    // Sized so the app always accepts what its own export can produce: a
    // passphrase-encrypted envelope base64-inflates the payload by ~4/3, so an
    // IPTV-heavy ~20 MiB backup arrives here at ~27 MiB.
    if (file.size > 40 * 1024 * 1024) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That file is too large to be a Debrify backup.'),
        ),
      );
      return;
    }

    final String content;
    try {
      if (file.path == null) {
        throw Exception('Could not read backup file contents');
      }
      final selected = File(file.path!);
      content = await PortableProfilePackage.readBoundedUtf8(
        selected.openRead(),
        maxBytes: 40 * 1024 * 1024,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to read the backup file')),
      );
      return;
    }

    Map<String, dynamic> payload;
    try {
      payload = BackupRestoreService.parse(content);
    } on FormatException catch (error) {
      if (!context.mounted) return;
      final looksLikeProfilePackage =
          content.contains('"format":"debrify-profile-package"') ||
          content.contains('"format": "debrify-profile-package"');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            looksLikeProfilePackage
                ? 'This is a profile backup. Enable profiles or update to a build that supports profile restore.'
                : error.message,
          ),
        ),
      );
      return;
    }

    if (BackupRestoreService.isEncrypted(payload)) {
      final inner = await _promptAndDecryptBackup(payload);
      if (inner == null) return; // Cancelled or unrecoverable.
      payload = inner;
    }

    final summary = BackupRestoreService.summarize(payload);
    if (summary.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup contains no data to restore.')),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Created: ${summary.createdAt}',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
            const Text('This backup contains:'),
            const SizedBox(height: 8),
            ...backupSummaryLines(summary).map((line) => Text('• $line')),
            const SizedBox(height: 12),
            const Text(
              'Saved credentials (Real-Debrid, Torbox, Premiumize, AllDebrid, PikPak, Trakt, Simkl) will '
              'be overwritten. Addons, search engines, WebDAV servers, '
              'indexer managers, and IPTV providers you already have are kept '
              'as-is. IPTV favorites and lists merge into what\'s here — '
              'nothing is removed.',
              style: TextStyle(fontSize: 12),
            ),
            if (summary.addonCount > 0 || summary.searchEngineCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Restoring addons and search engines needs a network '
                  'connection.',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
            if (summary.webDavServerCount > 0 ||
                summary.indexerManagerCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'WebDAV and Jackett/Prowlarr URLs may be local-network '
                  'only — they won\'t work on a different network.',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Run the restore. Show a non-dismissible progress dialog while it runs
    // — search engines and addons require network and can take a while.
    showSettingsDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Restoring backup…')),
            ],
          ),
        ),
      ),
    );

    RestoreReport report;
    try {
      report = await BackupRestoreService.applyBackup(payload);
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore failed')));
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final msg = formatRestoreReport(report);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: report.hasAnyFailure ? t.warning : null,
        duration: const Duration(seconds: 5),
      ),
    );

    // Drop any cached account info from a previous session so the cards
    // don't briefly show stale identity while Phase 2 of _loadSummaries
    // re-fetches it for the newly-restored keys.
    if (report.realDebrid) AccountService.clearUserInfo();
    if (report.torbox) TorboxAccountService.clearUserInfo();
    if (report.premiumize) PremiumizeAccountService.clearUserInfo();
    if (report.allDebrid) AllDebridAccountService.clearUserInfo();

    // Re-run the summary loader so the connection cards reflect the newly
    // restored services (and kick off background account refresh).
    // Tell the rest of the app — navbar, home tabs, search surfaces — that
    // integrations changed so they rebuild against the restored services
    // (same hook the individual settings pages use after a credential edit).
    await onRestored();
  }
}

/// Local wall-clock stamp (not UTC) — `BackupRestoreService.buildBackup`
/// stamps `createdAt` in UTC, but the export filename uses `DateTime.now()`.
@visibleForTesting
String backupExportFileName(DateTime ts) =>
    'debrify-backup-${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}-${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.json';

@visibleForTesting
List<String> backupSummaryLines(BackupSummary s) {
  final lines = <String>[];
  if (s.hasRealDebrid) lines.add('Real-Debrid');
  if (s.hasTorbox) lines.add('Torbox');
  if (s.hasPremiumize) lines.add('Premiumize');
  if (s.hasAllDebrid) lines.add('AllDebrid');
  if (s.hasPikpak) lines.add('PikPak');
  if (s.hasTrakt) lines.add('Trakt');
  if (s.hasSimkl) lines.add('Simkl');
  if (s.hasMdblist) lines.add('MDBList');
  if (s.searchEngineCount > 0) {
    lines.add('Search engines (${s.searchEngineCount})');
  }
  if (s.addonCount > 0) lines.add('Stremio addons (${s.addonCount})');
  if (s.webDavServerCount > 0) {
    lines.add('WebDAV servers (${s.webDavServerCount})');
  }
  if (s.indexerManagerCount > 0) {
    lines.add('Jackett/Prowlarr (${s.indexerManagerCount})');
  }
  if (s.iptvPlaylistCount > 0) {
    lines.add('IPTV providers (${s.iptvPlaylistCount})');
  }
  if (s.iptvFavoriteCount > 0) {
    lines.add('IPTV favorites (${s.iptvFavoriteCount} channels)');
  }
  if (s.iptvListCount > 0) {
    lines.add(
      'IPTV lists (${s.iptvListCount}, '
      '${s.iptvListChannelCount} channels)',
    );
  }
  if (s.homeCollectionCount > 0) {
    lines.add('Collections (${s.homeCollectionCount})');
  }
  if (s.streamBadgeSourceCount > 0) {
    lines.add('Stream badge rulesets (${s.streamBadgeSourceCount})');
  }
  return lines;
}

@visibleForTesting
String formatRestoreReport(RestoreReport r) {
  final parts = <String>[];
  if (r.realDebrid) parts.add('Real-Debrid');
  if (r.torbox) parts.add('Torbox');
  if (r.premiumize) parts.add('Premiumize');
  if (r.allDebrid) parts.add('AllDebrid');
  if (r.pikpak) parts.add('PikPak');
  if (r.trakt) parts.add('Trakt');
  if (r.simkl) parts.add('Simkl');
  if (r.mdblist) parts.add('MDBList');
  if (r.searchEnginesImported > 0) {
    parts.add('${r.searchEnginesImported} new engine(s)');
  }
  if (r.addonsImported > 0) {
    parts.add('${r.addonsImported} new addon(s)');
  }
  if (r.webDavServersImported > 0) {
    parts.add('${r.webDavServersImported} WebDAV server(s)');
  }
  if (r.indexerManagersImported > 0) {
    parts.add('${r.indexerManagersImported} indexer manager(s)');
  }
  if (r.iptvPlaylistsImported > 0) {
    parts.add('${r.iptvPlaylistsImported} IPTV provider(s)');
  }
  if (r.iptvFavoritesImported > 0) {
    parts.add('${r.iptvFavoritesImported} favorite channel(s)');
  }
  if (r.iptvListsCreated > 0) {
    parts.add('${r.iptvListsCreated} IPTV list(s)');
  }
  if (r.iptvListChannelsImported > 0) {
    parts.add('${r.iptvListChannelsImported} list channel(s)');
  }
  if (r.homeCollectionsImported > 0) {
    parts.add('${r.homeCollectionsImported} collection(s)');
  }
  if (r.streamBadgeSourcesImported > 0) {
    parts.add('${r.streamBadgeSourcesImported} badge ruleset(s)');
  }

  if (parts.isEmpty && !r.hasAnyFailure) {
    return 'Nothing new to restore — everything was already present';
  }
  final base = parts.isEmpty
      ? 'Restore finished'
      : 'Restored: ${parts.join(', ')}';
  final notes = <String>[];
  if (r.searchEnginesAlreadyPresent > 0) {
    notes.add('${r.searchEnginesAlreadyPresent} engine(s) already present');
  }
  if (r.addonsAlreadyPresent > 0) {
    notes.add('${r.addonsAlreadyPresent} addon(s) already present');
  }
  if (r.webDavServersAlreadyPresent > 0) {
    notes.add(
      '${r.webDavServersAlreadyPresent} WebDAV server(s) already present',
    );
  }
  if (r.indexerManagersAlreadyPresent > 0) {
    notes.add(
      '${r.indexerManagersAlreadyPresent} indexer manager(s) already present',
    );
  }
  if (r.iptvPlaylistsAlreadyPresent > 0) {
    notes.add(
      '${r.iptvPlaylistsAlreadyPresent} IPTV provider(s) already present',
    );
  }
  if (r.iptvFavoritesAlreadyPresent > 0) {
    notes.add('${r.iptvFavoritesAlreadyPresent} favorite(s) already present');
  }
  if (r.iptvListsMerged > 0) {
    notes.add('${r.iptvListsMerged} existing list(s) topped up');
  }
  final withNotes = notes.isEmpty ? base : '$base (${notes.join(', ')})';

  if (!r.hasAnyFailure) return withNotes;
  final failed = <String>[];
  if (r.pikpakLoginFailed) {
    failed.add('PikPak login (credentials saved — retry from PikPak settings)');
  }
  if (r.searchEnginesFailed > 0) {
    failed.add('${r.searchEnginesFailed} engine(s)');
  }
  if (r.addonsFailed > 0) failed.add('${r.addonsFailed} addon(s)');
  if (r.webDavServersFailed > 0) {
    failed.add('${r.webDavServersFailed} WebDAV server(s)');
  }
  if (r.indexerManagersFailed > 0) {
    failed.add('${r.indexerManagersFailed} indexer manager(s)');
  }
  if (r.iptvPlaylistsFailed > 0) {
    failed.add('${r.iptvPlaylistsFailed} IPTV provider(s)');
  }
  if (r.iptvFavoritesFailed > 0) {
    failed.add('${r.iptvFavoritesFailed} favorite(s)');
  }
  if (r.iptvListsFailed > 0) {
    failed.add('${r.iptvListsFailed} IPTV list entr(ies)');
  }
  failed.addAll(r.errors);
  return '$withNotes — failed: ${failed.join(', ')}';
}
