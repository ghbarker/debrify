import '../../utils/file_utils.dart';
import '../../utils/series_parser.dart';

/// Shared playlist ordering / filename helpers used by every cloud adapter
/// and by bound-source replay in [TorrentPlaybackService].
class CloudPlaybackHelpers {
  CloudPlaybackHelpers._();

  static String fileName(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  static List<T> videoPool<T>(List<T> files, String Function(T) nameOf) {
    final videos = files.where((f) => FileUtils.isVideoFile(nameOf(f))).toList();
    return videos.isNotEmpty ? videos : List<T>.from(files);
  }

  static T? pickLargest<T>(
    List<T> files,
    String Function(T) nameOf,
    int Function(T) sizeOf,
  ) {
    final pool = videoPool(files, nameOf);
    pool.sort((a, b) => sizeOf(b).compareTo(sizeOf(a)));
    return pool.isEmpty ? null : pool.first;
  }

  static int firstEpisodeIndex(List<SeriesInfo> infos) {
    var startIndex = 0;
    int? bestSeason;
    int? bestEpisode;
    for (var i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) continue;
      final betterSeason = bestSeason == null || season < bestSeason;
      final betterEpisode =
          bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);
      if (betterSeason || betterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }
    return startIndex;
  }

  /// Order video items by season/episode (falling back to filename) and return
  /// the sorted list plus the first-episode start index.
  static (List<T>, int) orderBySeries<T>(
    List<T> items,
    String Function(T) nameOf,
  ) {
    final names = [for (final e in items) fileName(nameOf(e))];
    final infos = [for (final n in names) SeriesParser.parseFilename(n)];
    final isSeries = items.length > 1 && SeriesParser.isSeriesPlaylist(names);
    final order = List<int>.generate(items.length, (i) => i);
    if (isSeries) {
      order.sort((a, b) {
        final sc = (infos[a].season ?? 0).compareTo(infos[b].season ?? 0);
        if (sc != 0) return sc;
        final ec = (infos[a].episode ?? 0).compareTo(infos[b].episode ?? 0);
        if (ec != 0) return ec;
        return names[a].toLowerCase().compareTo(names[b].toLowerCase());
      });
    } else {
      order.sort(
        (a, b) => names[a].toLowerCase().compareTo(names[b].toLowerCase()),
      );
    }
    final sorted = [for (final i in order) items[i]];
    final sortedInfos = [for (final i in order) infos[i]];
    var start = isSeries ? firstEpisodeIndex(sortedInfos) : 0;
    if (start < 0 || start >= sorted.length) start = 0;
    return (sorted, start);
  }
}
