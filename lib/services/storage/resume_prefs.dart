/// Playback resume key names. [StorageService] stays the public API; IptvMediaStore
/// still owns the SQLite rows.
class ResumePrefs {
  ResumePrefs._();

  static const videoResumeKey = 'video_resume_v1';
  static const playbackStateKey = 'playback_state_v1';
  static const continueWatchingKey = 'continue_watching_v1';
}
