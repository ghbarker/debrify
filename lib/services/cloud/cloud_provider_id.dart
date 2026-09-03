/// Canonical cloud/debrid provider ids used across playback, downloads, magnets,
/// and backups.
///
/// Playback uses [playbackId] (`debrid`, `torbox`, …). Bound sources and Home
/// persist Real-Debrid as [storedId] `rd`. Both map through [parse].
enum CloudProviderId {
  debrid,
  torbox,
  premiumize,
  alldebrid,
  pikpak;

  /// Order shared by [TorrentPlaybackService] silent resolution / picker.
  /// Premiumize is before PikPak on purpose: a silent PikPak fallback would
  /// queue real downloads on the account.
  static const List<CloudProviderId> playbackPrecedence = [
    debrid,
    torbox,
    premiumize,
    alldebrid,
    pikpak,
  ];

  /// Id used by [TorrentPlaybackService] switches and the default-provider pref.
  String get playbackId => name;

  /// Id stored on [SeriesSource] / Home (`rd` instead of `debrid`).
  String get storedId => this == debrid ? 'rd' : name;

  /// SharedPreferences / SecretVault credential key for download binding.
  String get credentialKey => switch (this) {
    debrid => 'real_debrid_api_key',
    torbox => 'torbox_api_key',
    premiumize => 'premiumize_api_key',
    alldebrid => 'alldebrid_api_key',
    pikpak => 'pikpak_email',
  };

  /// Backup JSON field for API-key providers. PikPak uses a nested `pikpak` map.
  String? get backupApiKeyField => switch (this) {
    debrid => 'realDebridApiKey',
    torbox => 'torboxApiKey',
    premiumize => 'premiumizeApiKey',
    alldebrid => 'allDebridApiKey',
    pikpak => null,
  };

  /// Action-sheet title (`TorBox`). Loader copy is [overlayTitle] (`Torbox`).
  String get displayName => switch (this) {
    debrid => 'Real-Debrid',
    torbox => 'TorBox',
    premiumize => 'Premiumize',
    alldebrid => 'AllDebrid',
    pikpak => 'PikPak',
  };

  /// Playback loader title. Distinct from [displayName] only for TorBox.
  String get overlayTitle => this == torbox ? 'Torbox' : displayName;

  /// Two-letter pipeline / catalog chip.
  String get chipCode => switch (this) {
    debrid => 'RD',
    torbox => 'TB',
    premiumize => 'PM',
    alldebrid => 'AD',
    pikpak => 'PP',
  };

  /// Playlist JSON `provider` field. Real-Debrid is `realdebrid`, not `debrid`.
  String get playlistStoredProvider => this == debrid ? 'realdebrid' : name;

  /// Stremio / catalog picker row (`realdebrid` → Real-Debrid).
  MapEntry<String, String> get catalogChoice =>
      MapEntry(playlistStoredProvider, displayName);

  /// [playbackId] only (`debrid`, not `rd` / `realdebrid`).
  static CloudProviderId? fromPlaybackId(String provider) {
    for (final id in values) {
      if (id.playbackId == provider) return id;
    }
    return null;
  }

  /// [storedId] only (`rd`, not `debrid` / `realdebrid`). Bound replay uses
  /// this; [tryParse] would wrongly treat a stored `debrid` as Real-Debrid.
  static CloudProviderId? fromStoredId(String stored) {
    for (final id in values) {
      if (id.storedId == stored) return id;
    }
    return null;
  }

  static CloudProviderId? tryParse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'debrid':
      case 'rd':
      case 'realdebrid':
      case 'real-debrid':
      case 'real_debrid':
        return debrid;
      case 'torbox':
        return torbox;
      case 'premiumize':
        return premiumize;
      case 'alldebrid':
      case 'all-debrid':
      case 'all_debrid':
        return alldebrid;
      case 'pikpak':
        return pikpak;
      default:
        return null;
    }
  }

  static CloudProviderId parse(String raw) {
    final id = tryParse(raw);
    if (id == null) {
      throw ArgumentError.value(raw, 'raw', 'Unknown cloud provider');
    }
    return id;
  }

  /// Real-Debrid is `'rd'` in SeriesSource storage but `'debrid'` as a playback
  /// provider key. Unknown strings pass through unchanged.
  static String playbackIdFromStored(String stored) =>
      tryParse(stored)?.playbackId ?? stored;

  static String storedIdFromPlayback(String provider) =>
      tryParse(provider)?.storedId ?? provider;
}
