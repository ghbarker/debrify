import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/screens/video_player/resume_controller.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('torbox / pikpak / hash keys match the origin grammar', () {
    final session = _FakeResumeSession(title: 'Fallback.mkv');
    final resume = ResumeController(session);

    expect(
      resume.idForEntry(
        const PlaylistEntry(
          url: 'https://tb/a',
          title: 'Show.S01E01.mkv',
          provider: 'TorBox',
          torboxWebDownloadId: 22,
          torboxFileId: 33,
        ),
      ),
      'torbox_web_22_33',
    );
    expect(
      resume.idForEntry(
        const PlaylistEntry(
          url: 'https://pk/a',
          title: 'Film.mkv',
          provider: 'pikpak',
          pikpakFileId: 'file-9',
        ),
      ),
      'pikpak_file-9',
    );

    const hashed = PlaylistEntry(url: 'https://x', title: 'Movie.Name.mkv');
    expect(
      resume.idForEntry(hashed),
      session.generateFilenameHash(hashed.title),
    );
  });

  test('ResumeContext exposes entry, position, duration', () {
    final entry = const PlaylistEntry(url: 'https://x', title: 'A');
    final session = _FakeResumeSession(
      playlist: [entry],
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 2),
    );
    final ctx = ResumeController(session).context;
    expect(ctx.entry, entry);
    expect(ctx.position, const Duration(seconds: 12));
    expect(ctx.duration, const Duration(minutes: 2));
  });

  test('IPTV key is the playing channel url, not the launch url', () {
    final session = _FakeResumeSession(
      videoUrl: 'https://opened-first',
      iptv: [
        IptvChannel(name: 'A', url: 'https://ch/a'),
        IptvChannel(name: 'B', url: 'https://ch/b'),
      ],
      iptvIndex: 1,
    );
    expect(ResumeController(session).key, 'https://ch/b');
  });

  test(
    'saveResume no-ops on validation gate, unreadiness, zero duration',
    () async {
      final gated = _FakeResumeSession(
        validationGateActive: true,
        isReady: true,
      );
      await ResumeController(gated).saveResume();

      final unready = _FakeResumeSession(isReady: false);
      await ResumeController(unready).saveResume();

      final zero = _FakeResumeSession(isReady: true, duration: Duration.zero);
      await ResumeController(zero).saveResume();
    },
  );
}

class _FakeResumeSession implements ResumeSession {
  _FakeResumeSession({
    this.videoUrl = 'https://launch',
    this.title = 'Title',
    this.playlist,
    this.position = Duration.zero,
    this.duration = const Duration(minutes: 10),
    this.iptv,
    this.iptvIndex = 0,
    this.validationGateActive = false,
    this.isReady = false,
  });

  @override
  final ResumeWriteGuard writeGuard = ResumeWriteGuard();
  @override
  int resumeVerifyEpoch = 0;
  List<PlaylistEntry>? playlist;
  List<IptvChannel>? iptv;
  int iptvIndex;

  @override
  List<PlaylistEntry>? get activePlaylist => playlist;
  @override
  int get currentIndex => 0;
  @override
  List<IptvChannel>? get effectiveIptvChannels => iptv;
  @override
  int get currentIptvIndex => iptvIndex;
  @override
  String videoUrl;
  @override
  String title;
  @override
  PlaybackResumePolicy resumePolicy = PlaybackResumePolicy.sourceSpecific;
  @override
  double? traktProgressPercent;
  @override
  double? simklProgressPercent;
  @override
  double? mdblistProgressPercent;
  @override
  String? contentImdbId;
  @override
  bool isAutoAdvancing = false;
  @override
  bool isManualEpisodeSelection = false;
  @override
  bool allowResumeForManualSelection = false;
  @override
  bool launchTraktPercentSpent = false;
  @override
  bool launchSimklPercentSpent = false;
  @override
  bool launchMdblistPercentSpent = false;
  @override
  Duration position;
  @override
  Duration duration;
  @override
  Duration get playerPosition => position;
  @override
  Future<void> seek(Duration target) async {}
  @override
  Future<void> setRate(double speed) async {}
  @override
  double playbackSpeed = 1;
  @override
  AspectMode aspectMode = AspectMode.contain;
  @override
  Future<void> applyAspectVideoZoom() async {}
  @override
  Future<void> waitForDuration() async {}
  @override
  Future<double?> currentEpisodeTraktPercent({bool forGuide = false}) async =>
      null;
  @override
  Future<double?> currentEpisodeSimklPercent({bool forGuide = false}) async =>
      null;
  @override
  Future<double?> currentEpisodeMdblistPercent({bool forGuide = false}) async =>
      null;
  @override
  String? currentLocalMovieImdbId;
  @override
  SeriesPlaylist? seriesPlaylist;
  @override
  String? effectiveContentImdbId;
  @override
  String? effectiveContentType;
  @override
  int? effectiveContentSeason;
  @override
  int? effectiveContentEpisode;
  @override
  String? effectiveContentTitle;
  @override
  String? currentStremioTvContentTitle;
  @override
  String? currentStreamUrl;
  @override
  bool validationGateActive;
  @override
  bool isReady;
  @override
  bool isTransitioning = false;
  @override
  bool currentMovieMarkedAsFinished = false;
  @override
  double? speedBeforeHold;
  @override
  bool isMounted = true;
  @override
  bool screenDisposed = false;
  @override
  String generateFilenameHash(String filename) {
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]*$'), '');
    return nameWithoutExt.hashCode.toString();
  }
}
