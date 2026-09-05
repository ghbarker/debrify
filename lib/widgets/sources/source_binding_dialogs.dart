import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/local_bound_source_service.dart';
import '../../services/series_source_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme_scope.dart';
import '../add_source_picker_dialog.dart';
import '../cloud_provider_chrome.dart';

/// Screen-supplied cloud navigation. The dialog owns availability and saving;
/// each callback receives the navigator captured before credential reads.
typedef SourceBindingCloudRoute =
    Future<void> Function(
      NavigatorState navigator,
      StremioMeta item,
      Future<void> Function(SeriesSource) saveSource,
    );

class SourceBindingCloudRoutes {
  const SourceBindingCloudRoutes({
    required this.onRealDebrid,
    required this.onTorbox,
    required this.onPremiumize,
    required this.onAllDebrid,
    required this.onPikPak,
  });

  final SourceBindingCloudRoute onRealDebrid;
  final SourceBindingCloudRoute onTorbox;
  final SourceBindingCloudRoute onPremiumize;
  final SourceBindingCloudRoute onAllDebrid;
  final SourceBindingCloudRoute onPikPak;
}

/// Source edit/add dialogs extracted from `search_screen.dart` (G1'-2).
///
/// Seam: catalog [item] + configured cloud/local binding options → persist
/// via [SeriesSourceService] and host callbacks (torrent/keyword bind, snack).
/// Does not invent a board `Mode`; G1'-0 types stay on the host.
class SourceBindingDialogs {
  SourceBindingDialogs._();

  /// Origin IMDb helper — empty string and non-`tt` catalog ids are null.
  static String? imdbOf(StremioMeta item) {
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// Manage the bound sources for [item]: list them, reorder by priority
  /// (series — first match wins), delete individually, Remove All, or add
  /// another via the picker. Ported from the catalog/aggregated detail flow.
  static Future<void> showEdit({
    required BuildContext context,
    required StremioMeta item,
    required SourceBindingCloudRoutes cloudRoutes,
    required List<SeriesSource> initial,
    required Future<void> Function() onRefreshBound,
    required void Function(StremioMeta item) onTorrentSearch,
    required void Function(StremioMeta item) onKeywordSearch,
    required void Function(String message) onSnack,
    required bool Function() isHostMounted,
  }) async {
    final imdbId = imdbOf(item);
    if (imdbId == null) return;
    final isMovie = item.type == 'movie';
    final sources = List<SeriesSource>.of(initial);
    if (sources.isEmpty) return;

    // [closeIfEmpty] pops the dialog via its OWN route (passed in from the
    // builder) when the last source is removed — robust to nested navigators,
    // and a callback (not a BuildContext) so it's safe across the awaits here.
    Future<void> refreshInto(
      void Function(void Function()) setDialogState,
      VoidCallback closeIfEmpty,
    ) async {
      final updated = await SeriesSourceService.getSources(imdbId);
      if (!isHostMounted()) return;
      setDialogState(() {
        sources
          ..clear()
          ..addAll(updated);
      });
      await onRefreshBound();
      if (updated.isEmpty) closeIfEmpty();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final app = AppThemeScope.of(dialogContext);
            void closeIfEmpty() {
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            }

            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: app.shape.br(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  maxHeight: 500,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: isMovie
                            ? ListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                itemBuilder: (context, index) =>
                                    _buildSourceListTile(
                                      key: ValueKey(sources[index].bindingKey),
                                      context: context,
                                      source: sources[index],
                                      index: index,
                                      showDragHandle: false,
                                      onDelete: () async {
                                        await SeriesSourceService.removeSourceEntry(
                                          imdbId,
                                          sources[index],
                                        );
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                        );
                                      },
                                    ),
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                // ignore: deprecated_member_use
                                onReorder: (oldIndex, newIndex) {
                                  if (newIndex > oldIndex) newIndex--;
                                  setDialogState(() {
                                    final moved = sources.removeAt(oldIndex);
                                    sources.insert(newIndex, moved);
                                  });
                                  SeriesSourceService.setSources(
                                    imdbId,
                                    List.of(sources),
                                  );
                                  onRefreshBound();
                                },
                                proxyDecorator: (child, index, animation) =>
                                    Material(
                                      color: Colors.transparent,
                                      elevation: 4,
                                      child: child,
                                    ),
                                itemBuilder: (context, index) =>
                                    _buildSourceListTile(
                                      key: ValueKey(sources[index].bindingKey),
                                      context: context,
                                      source: sources[index],
                                      index: index,
                                      onDelete: () async {
                                        await SeriesSourceService.removeSourceEntry(
                                          imdbId,
                                          sources[index],
                                        );
                                        await refreshInto(
                                          setDialogState,
                                          closeIfEmpty,
                                        );
                                      },
                                    ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                showAdd(
                                  context: context,
                                  item: item,
                                  cloudRoutes: cloudRoutes,
                                  onRefreshBound: onRefreshBound,
                                  onTorrentSearch: onTorrentSearch,
                                  onKeywordSearch: onKeywordSearch,
                                  onSnack: onSnack,
                                  isHostMounted: isHostMounted,
                                );
                              },
                              icon: Icon(
                                isMovie
                                    ? Icons.swap_horiz_rounded
                                    : Icons.add_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isMovie ? 'Change Source' : 'Add Source',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: app.shape.br(10),
                                ),
                              ),
                            ),
                          ),
                          if (!isMovie && sources.length > 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  await onRefreshBound();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                  color: app.home.danger,
                                ),
                                label: Text(
                                  'Remove All',
                                  style: TextStyle(color: app.home.danger),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: app.home.danger,
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: app.shape.br(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (isMovie) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  await onRefreshBound();
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: app.home.danger,
                                ),
                                label: Text(
                                  'Remove',
                                  style: TextStyle(color: app.home.danger),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: app.home.danger,
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: app.shape.br(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Add-source picker: Torrent Search (imdb) / Keyword Search (free-text) /
  /// Local file plus every configured cloud provider.
  static Future<void> showAdd({
    required BuildContext context,
    required StremioMeta item,
    required SourceBindingCloudRoutes cloudRoutes,
    required Future<void> Function() onRefreshBound,
    required void Function(StremioMeta item) onTorrentSearch,
    required void Function(StremioMeta item) onKeywordSearch,
    required void Function(String message) onSnack,
    required bool Function() isHostMounted,
  }) async {
    final imdbId = imdbOf(item);
    if (imdbId == null) {
      onSnack('No IMDb match to pin a source for "${item.name}".');
      return;
    }
    // Capture the navigator before the awaits so the RD/TorBox push closures
    // don't reference `context` across an async gap.
    final navigator = Navigator.of(context);
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final premiumizeKey = await StorageService.getPremiumizeApiKey();
    final premiumizeIntegration =
        await ProviderCredentialPrefs.getPremiumizeIntegrationEnabled();
    final allDebridKey = await StorageService.getAllDebridApiKey();
    final pikpakEnabled = await ProviderCredentialPrefs.getPikPakEnabled();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;
    final premiumizeEnabled =
        premiumizeIntegration &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridEnabled = allDebridKey != null && allDebridKey.isNotEmpty;
    if (!isHostMounted() || !context.mounted) return;

    final isMovie = item.type == 'movie';
    final supportsLocal = !LocalBoundSourceService.isLocalBindingDisabled;

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
      await onRefreshBound();
    }

    // No cloud providers and no local option → go straight to torrent search.
    if (!rdEnabled &&
        !torboxEnabled &&
        !premiumizeEnabled &&
        !allDebridEnabled &&
        !pikpakEnabled &&
        !supportsLocal) {
      onTorrentSearch(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => onTorrentSearch(item),
      onKeywordSearch: () => onKeywordSearch(item),
      onLocal: supportsLocal
          ? () => pickAndSaveLocal(
              context: context,
              item: item,
              onRefreshBound: onRefreshBound,
              onSnack: onSnack,
              isHostMounted: isHostMounted,
            )
          : null,
      localDisabledReason: LocalBoundSourceService.localDisabledReason,
      onRealDebrid: rdEnabled
          ? () => cloudRoutes.onRealDebrid(navigator, item, saveSource)
          : null,
      onTorbox: torboxEnabled
          ? () => cloudRoutes.onTorbox(navigator, item, saveSource)
          : null,
      onPremiumize: premiumizeEnabled
          ? () => cloudRoutes.onPremiumize(navigator, item, saveSource)
          : null,
      onAllDebrid: allDebridEnabled
          ? () => cloudRoutes.onAllDebrid(navigator, item, saveSource)
          : null,
      onPikPak: pikpakEnabled
          ? () => cloudRoutes.onPikPak(navigator, item, saveSource)
          : null,
    );
  }

  static Future<void> pickAndSaveLocal({
    required BuildContext context,
    required StremioMeta item,
    required Future<void> Function() onRefreshBound,
    required void Function(String message) onSnack,
    required bool Function() isHostMounted,
  }) async {
    final imdbId = imdbOf(item);
    if (imdbId == null) return;
    final SeriesSource? source;
    if (item.type == 'series') {
      source = await LocalBoundSourceService.pickSeriesSource(
        context,
        title: item.name,
      );
    } else {
      source = await LocalBoundSourceService.pickMovieSource(
        context,
        title: item.name,
        year: item.year,
      );
    }
    if (source == null) return;
    if (item.type == 'series') {
      await SeriesSourceService.addSource(imdbId, source);
    } else {
      await SeriesSourceService.setSources(imdbId, [source]);
    }
    await onRefreshBound();
    if (!isHostMounted()) return;
    onSnack('Local source set: ${source.torrentName}');
  }
}

/// One bound-source row for the edit dialog (index badge, name, provider
/// chip, delete). Ported from the catalog/aggregated detail flow.
Widget _buildSourceListTile({
  required BuildContext context,
  required Key key,
  required SeriesSource source,
  required int index,
  required VoidCallback onDelete,
  bool showDragHandle = true,
}) {
  final app = AppThemeScope.of(context);
  final chip = CloudProviderChrome.sourceChip(source.debridService);
  final serviceColor = chip.color;
  final serviceLabel = chip.label;

  return Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: app.fade(app.core.tx, 0.05),
      borderRadius: app.shape.br(8),
      border: Border.all(color: app.fade(app.core.tx, 0.08)),
    ),
    child: Row(
      children: [
        if (showDragHandle) ...[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
              borderRadius: app.shape.br(6),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.torrentName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: serviceColor.withValues(alpha: 0.15),
                  borderRadius: app.shape.br(3),
                ),
                child: Text(
                  serviceLabel,
                  style: TextStyle(
                    color: serviceColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 16, color: app.home.danger),
          onPressed: onDelete,
          tooltip: 'Remove source',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        if (showDragHandle)
          Icon(
            Icons.drag_handle_rounded,
            size: 18,
            color: app.core.tx.withValues(alpha: 0x3D / 0xFF),
          ),
      ],
    ),
  );
}
