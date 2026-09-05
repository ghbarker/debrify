import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'package:flutter/foundation.dart';

import '../../models/indexer_manager_config.dart';
import '../../models/webdav_item.dart';
import '../engine/config_loader.dart';
import '../engine/engine_registry.dart';
import '../engine/local_engine_storage.dart';
import '../engine/remote_engine_manager.dart';
import '../storage_service.dart';
import '../stremio_service.dart';
import 'backup_models.dart';

List<String> transferBackupAddonManifestUrls(Iterable<String> urls) => <String>{
  for (final url in urls)
    if (url.trim().isNotEmpty) url.trim(),
}.toList(growable: false);

String transferNormalizeUrl(String url) {
  return url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');
}

/// Merge restored WebDAV servers into the existing list. We de-dupe by
/// normalized base URL — restoring the same backup twice doesn't duplicate
/// entries, but a different server at a different URL is added.
Future<void> restoreWebDavServers(
  List<dynamic> entries,
  RestoreReport report,
) async {
  try {
    final existing = await ProviderCredentialPrefs.getWebDavServers();
    final existingUrls = <String>{
      for (final s in existing) transferNormalizeUrl(s.baseUrl),
    };
    final merged = List<WebDavConfig>.from(existing);
    for (final raw in entries) {
      if (raw is! Map) {
        report.webDavServersFailed++;
        continue;
      }
      try {
        final config = WebDavConfig.fromTransferJson(
          Map<String, dynamic>.from(raw),
        );
        if (config.baseUrl.trim().isEmpty) {
          report.webDavServersFailed++;
          continue;
        }
        final key = transferNormalizeUrl(config.baseUrl);
        if (existingUrls.contains(key)) {
          report.webDavServersAlreadyPresent++;
          continue;
        }
        merged.add(config);
        existingUrls.add(key);
        report.webDavServersImported++;
      } catch (_) {
        debugPrint('BackupRestoreService: WebDAV entry failed');
        report.webDavServersFailed++;
      }
    }
    if (report.webDavServersImported > 0) {
      await ProviderCredentialPrefs.saveWebDavServers(merged);
      // setWebDavEnabled is handled inside saveWebDavServers.
    }
  } catch (_) {
    report.errors.add('WebDAV: restore failed');
  }
}

/// Merge restored indexer manager configs into the existing list. De-duped
/// by (type, normalized baseUrl) so re-importing the same backup is a
/// no-op, but a different host or different type is added.
Future<void> restoreIndexerManagers(
  List<dynamic> entries,
  RestoreReport report,
) async {
  try {
    final existing = await StorageService.getIndexerManagerConfigs();
    String fingerprint(IndexerManagerConfig c) =>
        '${c.type.value}|${transferNormalizeUrl(c.baseUrl)}';
    final existingKeys = <String>{for (final c in existing) fingerprint(c)};
    final merged = List<IndexerManagerConfig>.from(existing);
    for (final raw in entries) {
      if (raw is! Map) {
        report.indexerManagersFailed++;
        continue;
      }
      try {
        final config = IndexerManagerConfig.fromTransferJson(
          Map<String, dynamic>.from(raw),
        );
        if (config.baseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
          report.indexerManagersFailed++;
          continue;
        }
        final key = fingerprint(config);
        if (existingKeys.contains(key)) {
          report.indexerManagersAlreadyPresent++;
          continue;
        }
        merged.add(config);
        existingKeys.add(key);
        report.indexerManagersImported++;
      } catch (_) {
        debugPrint('BackupRestoreService: indexer manager entry failed');
        report.indexerManagersFailed++;
      }
    }
    if (report.indexerManagersImported > 0) {
      await StorageService.setIndexerManagerConfigs(merged);
    }
  } catch (_) {
    report.errors.add('Indexer managers: restore failed');
  }
}

Future<void> restoreSearchEngines(
  List<String> engineIds,
  RestoreReport report, {
  required bool refreshRuntime,
}) async {
  try {
    final remoteManager = RemoteEngineManager();
    final localStorage = LocalEngineStorage.instance;
    await localStorage.initialize();

    final available = await remoteManager.fetchAvailableEngines();
    for (final id in engineIds) {
      try {
        if (await localStorage.isEngineImported(id)) {
          report.searchEnginesAlreadyPresent++;
          continue;
        }
        final info = available.where((e) => e.id == id).firstOrNull;
        if (info == null) {
          report.searchEnginesFailed++;
          continue;
        }
        final yaml = await remoteManager.downloadEngineYaml(info.fileName);
        if (yaml == null) {
          report.searchEnginesFailed++;
          continue;
        }
        await localStorage.saveEngine(
          engineId: id,
          fileName: info.fileName,
          yamlContent: yaml,
          displayName: info.displayName,
          icon: info.icon,
        );
        report.searchEnginesImported++;
      } catch (_) {
        debugPrint('BackupRestoreService: engine import failed');
        report.searchEnginesFailed++;
      }
    }

    // Refresh the in-memory engine registry so newly-imported engines are
    // visible to keyword search without an app restart. Skip when nothing
    // was actually written to disk — the registry already matches.
    if (refreshRuntime && report.searchEnginesImported > 0) {
      ConfigLoader().clearCache();
      await EngineRegistry.instance.reload();
    }
  } catch (_) {
    report.errors.add('Search engines: restore failed');
  }
}

Future<void> restoreAddons(List<String> urls, RestoreReport report) async {
  try {
    // Avoid importing duplicates of disabled owned addons or executable
    // shared addons whose settings representation redacts its URL.
    final existing = await StremioService.instance.getAddonsForManagement();
    final existingUrls = existing.map((a) => a.manifestUrl).toSet();
    for (final url in urls) {
      if (existingUrls.contains(url)) {
        report.addonsAlreadyPresent++;
        continue;
      }
      try {
        await StremioService.instance.addAddon(url);
        report.addonsImported++;
      } catch (_) {
        debugPrint('BackupRestoreService: addon import failed');
        report.addonsFailed++;
      }
    }
  } catch (_) {
    report.errors.add('Addons: restore failed');
  }
}
