import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/debrify_tv/cache_results.dart';
import '../../models/premiumize_file.dart';
import '../../models/torbox_file.dart';
import '../../models/torbox_torrent.dart';
import '../../utils/file_utils.dart';
import '../../utils/series_parser.dart';
import 'magic_tv_prepare_args.dart';

/// File listing used by Debrify TV prepare. Size-filter fallback and
/// series-title format stay here so TorBox / Premiumize do not drift.
class MagicTvPlayable {
  MagicTvPlayable._();

  static String formatSeriesTitle(SeriesInfo info, String fallback) {
    final season = info.season?.toString().padLeft(2, '0');
    final episode = info.episode?.toString().padLeft(2, '0');
    final descriptor = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : (info.title?.trim().isNotEmpty == true
              ? info.title!.trim()
              : fallback);
    if (season != null && episode != null) {
      return 'S${season}E$episode · $descriptor';
    }
    return fallback;
  }

  static bool torboxFileLooksLikeVideo(TorboxFile file) {
    if (file.zipped) return false;
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    if (FileUtils.isVideoFile(name)) return true;
    final mime = file.mimetype?.toLowerCase();
    return mime != null && mime.startsWith('video/');
  }

  static String torboxDisplayName(TorboxFile file) {
    if (file.shortName.isNotEmpty) {
      return file.shortName;
    }
    if (file.name.isNotEmpty) {
      return FileUtils.getFileName(file.name);
    }
    return 'File ${file.id}';
  }

  static List<TorboxPlayableEntry> buildTorboxEntries(
    TorboxTorrent torrent,
    String fallbackTitle,
    MagicTvPrepareRequest request, {
    bool applySizeFilter = true,
  }) {
    final seriesCandidates = <TorboxPlayableEntry>[];
    final otherCandidates = <TorboxPlayableEntry>[];

    for (final file in torrent.files) {
      if (!torboxFileLooksLikeVideo(file)) continue;
      if (file.size < request.minVideoSizeBytes) continue;
      if (applySizeFilter && !request.sizeMatchesBytes(file.size)) continue;

      final displayName = torboxDisplayName(file);
      final info = SeriesParser.parseFilenameConservative(displayName);
      final title = info.isSeries
          ? formatSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = TorboxPlayableEntry(file: file, title: title, info: info);

      if (info.isSeries && info.season != null && info.episode != null) {
        seriesCandidates.add(entry);
      } else {
        otherCandidates.add(entry);
      }
    }

    seriesCandidates.sort((a, b) {
      final seasonCompare = (a.info.season ?? 0).compareTo(b.info.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.info.episode ?? 0).compareTo(b.info.episode ?? 0);
    });

    otherCandidates.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    final entries = <TorboxPlayableEntry>[
      ...seriesCandidates,
      ...otherCandidates,
    ];
    entries.shuffle(Random());
    if (entries.isEmpty && applySizeFilter && request.hasSizeFilter) {
      debugPrint(
        'DebrifyTV/Torbox: no file matched the size filter in '
        '"$fallbackTitle" — using it unfiltered.',
      );
      return buildTorboxEntries(
        torrent,
        fallbackTitle,
        request,
        applySizeFilter: false,
      );
    }
    return entries;
  }

  static bool premiumizeFileLooksLikeVideo(PremiumizeFile file) {
    final name = file.fileName;
    if (name.isEmpty) return false;
    return FileUtils.isVideoFile(name);
  }

  static List<PremiumizePlayableEntry> buildPremiumizeEntries(
    List<PremiumizeFile> files,
    String fallbackTitle,
    MagicTvPrepareRequest request, {
    bool applySizeFilter = true,
  }) {
    final seriesCandidates = <PremiumizePlayableEntry>[];
    final otherCandidates = <PremiumizePlayableEntry>[];

    for (final file in files) {
      if (!premiumizeFileLooksLikeVideo(file)) continue;
      if (file.size < request.minVideoSizeBytes) continue;
      if (applySizeFilter && !request.sizeMatchesBytes(file.size)) continue;

      final displayName = file.fileName.isNotEmpty
          ? file.fileName
          : fallbackTitle;
      final info = SeriesParser.parseFilenameConservative(displayName);
      final title = info.isSeries
          ? formatSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = PremiumizePlayableEntry(
        file: file,
        title: title,
        info: info,
      );

      if (info.isSeries && info.season != null && info.episode != null) {
        seriesCandidates.add(entry);
      } else {
        otherCandidates.add(entry);
      }
    }

    seriesCandidates.sort((a, b) {
      final seasonCompare = (a.info.season ?? 0).compareTo(b.info.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.info.episode ?? 0).compareTo(b.info.episode ?? 0);
    });

    otherCandidates.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    final entries = <PremiumizePlayableEntry>[
      ...seriesCandidates,
      ...otherCandidates,
    ];
    entries.shuffle(Random());
    if (entries.isEmpty && applySizeFilter && request.hasSizeFilter) {
      debugPrint(
        'DebrifyTV/Premiumize: no file matched the size filter in '
        '"$fallbackTitle" — using it unfiltered.',
      );
      return buildPremiumizeEntries(
        files,
        fallbackTitle,
        request,
        applySizeFilter: false,
      );
    }
    return entries;
  }
}
