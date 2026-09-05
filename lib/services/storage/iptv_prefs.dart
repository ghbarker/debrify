import 'dart:convert';

import '../../models/iptv_playlist.dart';
import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../iptv_channel_order.dart';
import '../iptv_media_store.dart';
import '../profiles/connection_resource_service.dart';
import '../profiles/profile_collection_resource_facade.dart';
import '../profiles/profile_preferences.dart';
import '../profiles/profile_runtime.dart';
import '../secret_vault.dart';

/// IPTV playlist, decoder, last-live, startup, series-audio, and
/// continue-watching prefs. [StorageService] forwards to this store.
///
/// Style keys (`iptv_style`, `iptv_channel_preview_enabled`,
/// `iptv_player_guide_style`) live on [AppStylePrefs] (S2-4).
/// Shared startup keys `startup_auto_launch_enabled` / `startup_mode`
/// stay owned by StorageService. Key names and encodings are frozen.
class IptvPrefs {
  IptvPrefs._();

  static const String _iptvDecoderModeKey = 'iptv_decoder_mode';
  // IPTV settings
  static const String _iptvPlaylistsKey = 'iptv_playlists';
  static const String _iptvDefaultPlaylistKey = 'iptv_default_playlist';
  static const String _iptvDefaultsInitializedKey = 'iptv_defaults_initialized';
  static const String _iptvLastLiveChannelKey = 'iptv_last_live_channel';
  static const String _iptvTrackContinueWatchingKey =
      'iptv_track_continue_watching';
  static const String _iptvSeriesAudioLangKey = 'iptv_series_audio_lang';
  static const String _startupIptvModeKey = 'startup_iptv_mode';
  static const String _startupIptvChannelKey = 'startup_iptv_channel';

  /// 'last' (whatever played most recently) or 'pinned' (a chosen channel).
  static const String startupIptvModeLast = 'last';
  static const String startupIptvModePinned = 'pinned';

  /// Payload marker meaning "nothing is remembered yet — start on whatever the
  /// IPTV page lands on". Never persisted; only ever set by [warmStartupIptv].
  static const String startupIptvFirstAvailable = 'firstAvailable';

  static const Set<String> ownedKeys = {
    _iptvDecoderModeKey,
    _iptvPlaylistsKey,
    _iptvDefaultPlaylistKey,
    _iptvDefaultsInitializedKey,
    _iptvLastLiveChannelKey,
    _iptvTrackContinueWatchingKey,
    _iptvSeriesAudioLangKey,
    _startupIptvModeKey,
    _startupIptvChannelKey,
  };

  /// Shared with the general Launch-on-Startup leftovers. Not in [ownedKeys].
  static const String _startupAutoLaunchEnabledKey =
      'startup_auto_launch_enabled';
  static const String _startupModeKey = 'startup_mode';

  /// Android TV IPTV video decoder: 'auto' | 'hardware' | 'software'.
  ///
  /// Some TV boxes (MediaTek/Amlogic especially) freeze the picture while
  /// audio keeps playing when their hardware decoder is handed a live stream
  /// it mishandles — a device defect no app can work around reliably, which
  /// is why every IPTV player ships this switch. 'software' puts Android's
  /// own software codecs (c2.android.* / OMX.google.*) first; 'auto' leaves
  /// the platform's decoder order untouched.
  static const List<String> iptvDecoderModes = ['auto', 'hardware', 'software'];

  static Future<String> getIptvDecoderMode() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_iptvDecoderModeKey) ?? 'auto';
    return iptvDecoderModes.contains(value) ? value : 'auto';
  }

  static Future<void> setIptvDecoderMode(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _iptvDecoderModeKey,
      iptvDecoderModes.contains(value) ? value : 'auto',
    );
  }

  // ==========================================================================
  // IPTV Channel Favorites
  // ==========================================================================

  /// Canonical comparison key for an IPTV channel URL (see
  /// [IptvMediaStore.canonicalChannelKey]).
  static String canonicalIptvChannelKey(String url) {
    return IptvMediaStore.canonicalChannelKey(url);
  }

  /// Rewrite stored favorite URLs to the current format when a fetched
  /// channel matches an existing favorite canonically but not literally
  /// (e.g. favorites saved before the Xtream /live/ URL fix). Keeps the
  /// Home favorites row playing working URLs.
  static Future<void> reconcileIptvFavoriteUrls(List<IptvChannel> channels) {
    return IptvMediaStore.reconcileFavoriteUrls(channels);
  }

  /// DB-catalog variant: the fresh URLs come from the catalog rows on a
  /// worker isolate instead of a channel list.
  static Future<void> reconcileIptvFavoriteUrlsForCatalog(String catalogKey) {
    return IptvMediaStore.reconcileFavoriteUrlsForCatalog(catalogKey);
  }

  /// Set favorite status for an IPTV channel
  static Future<void> setIptvChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelFavorited(
      channelUrl,
      isFavorited,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  // ── IPTV custom lists ────────────────────────────────────────────────────

  /// Reserved id of the built-in Favorites list.
  static const String iptvFavoritesListId = IptvMediaStore.favoritesListId;

  /// Every channel list, Favorites first then custom lists in user order.
  static Future<List<IptvListMeta>> getIptvLists() {
    return IptvMediaStore.lists();
  }

  /// Create a channel list and return its id.
  static Future<String> createIptvList(String name) {
    return IptvMediaStore.createList(name);
  }

  static Future<void> renameIptvList(String listId, String name) {
    return IptvMediaStore.renameList(listId, name);
  }

  /// Delete a custom list. The channels themselves are untouched.
  static Future<void> deleteIptvList(String listId) {
    return IptvMediaStore.deleteList(listId);
  }

  static Future<void> reorderIptvLists(List<String> orderedIds) {
    return IptvMediaStore.reorderLists(orderedIds);
  }

  /// Add or remove a channel in a list.
  static Future<void> setIptvChannelInList(
    String listId,
    String channelUrl,
    bool inList, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
  }) {
    return IptvMediaStore.setChannelInList(
      listId,
      channelUrl,
      inList,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
    );
  }

  /// One list's channels, url → metadata.
  static Future<Map<String, Map<String, dynamic>>> getIptvListChannels(
    String listId,
  ) {
    return IptvMediaStore.listChannels(listId);
  }

  /// Persist the display order of channels inside Favorites or a custom list.
  static Future<void> reorderIptvListChannels(
    String listId,
    Iterable<String> orderedUrls,
  ) {
    return IptvMediaStore.reorderListChannels(listId, orderedUrls);
  }

  static Future<List<IptvChannelOrderEntry>> getIptvCategoryOrderEntries(
    String sourceId,
    Iterable<IptvChannel> channels,
    String group,
  ) {
    return IptvMediaStore.categoryOrderEntries(sourceId, channels, group);
  }

  static Future<void> setIptvCategoryChannelOrder(
    String sourceId,
    String group,
    Iterable<IptvChannelOrderIdentity> ordered,
  ) {
    return IptvMediaStore.setCategoryChannelOrder(sourceId, group, ordered);
  }

  static Future<List<IptvChannel>> applyIptvCategoryChannelOrders(
    String sourceId,
    List<IptvChannel> channels,
  ) {
    return IptvMediaStore.applyCategoryChannelOrders(sourceId, channels);
  }

  static Future<void> removeIptvCategoryOrdersForSource(String sourceId) {
    return IptvMediaStore.removeCategoryOrdersForSource(sourceId);
  }

  /// Which lists each stored channel belongs to, url → list ids.
  static Future<Map<String, Set<String>>> getIptvChannelMembership() {
    return IptvMediaStore.channelMembership();
  }

  /// Membership + per-(list, url) origin providers in one read (see
  /// [IptvMediaStore.membershipSnapshot]).
  static Future<
    ({
      Map<String, Set<String>> membership,
      Map<(String, String), String> origins,
    })
  >
  getIptvMembershipSnapshot() {
    return IptvMediaStore.membershipSnapshot();
  }

  /// The lists one channel belongs to, matched canonically.
  static Future<Set<String>> getIptvListsForChannel(String channelUrl) {
    return IptvMediaStore.listsForChannel(channelUrl);
  }

  /// Remove every membership belonging to a playlist, across all lists.
  static Future<void> removeIptvListChannelsByPlaylistId(String playlistId) {
    return IptvMediaStore.removeListChannelsByPlaylistId(playlistId);
  }

  /// Per-channel HTTP headers stored with a favorite (see
  /// [setIptvChannelFavorited]). JSON round-trips them as a dynamic map, and
  /// favorites saved before headers existed simply have none.
  static Map<String, String> iptvFavoriteHeaders(Map<String, dynamic> meta) {
    final raw = meta['httpHeaders'];
    if (raw is! Map) return const {};
    final headers = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) headers[key] = value.toString();
    });
    return headers;
  }

  /// Remove all IPTV favorites that belong to a specific playlist
  static Future<void> removeIptvFavoritesByPlaylistId(String playlistId) {
    return IptvMediaStore.removeFavoritesByPlaylistId(playlistId);
  }

  /// Get all favorite IPTV channel URLs with metadata
  static Future<Map<String, Map<String, dynamic>>> getIptvFavoriteChannels() {
    return IptvMediaStore.favoriteChannels();
  }

  /// Get all favorite IPTV channel URLs
  static Future<Set<String>> getIptvFavoriteChannelUrls() async {
    final favorites = await getIptvFavoriteChannels();
    return favorites.keys.toSet();
  }

  // ── IPTV watch history (backs the virtual "Continue watching" playlist) ──

  /// A watched item counts as in-progress between these fractions: below the
  /// floor nothing meaningful was watched (a mis-click, or a few seconds of
  /// buffering), and above the ceiling it's effectively finished.
  static const double _iptvWatchStartedFraction = 0.02;
  static const double iptvWatchFinishedFraction = 0.95;

  /// Whether on-demand IPTV playback feeds the Continue Watching shelves at
  /// all. Off is enforced at BOTH ends — nothing new is recorded, and whatever
  /// is already stored is filtered out of [getIptvContinueWatching] — so the
  /// shelves empty out immediately without deleting anything: turning it back
  /// on restores the rows that were there.
  ///
  /// Deliberately does NOT touch playback positions. Those live in the
  /// separate video-resume store, which the players write directly and which
  /// backs both resuming a movie where you left off and the progress bars on
  static Future<bool> getIptvTrackContinueWatching() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvTrackContinueWatchingKey) ?? true;
  }

  static Future<void> setIptvTrackContinueWatching(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvTrackContinueWatchingKey, value);
  }

  /// Remember that an on-demand IPTV item was played, capturing enough
  /// metadata to rebuild its row without re-fetching the panel — the same
  /// trick [setIptvChannelFavorited] uses, and necessary for the same reason:
  /// the provider's catalog can be renumbered or gone by the time the shelf
  /// is read.
  ///
  /// The playback position is deliberately NOT stored here. Both players
  /// already write it to the shared video-resume store keyed by stream URL,
  /// and copying it would hand the shelf a second, staler truth to disagree
  /// with; [getIptvContinueWatching] joins the two at read time instead.
  ///
  /// A no-op when [getIptvTrackContinueWatching] is off. Gating here rather
  /// than at each caller is deliberate: this is the single funnel every
  /// on-demand play goes through — both players, the IPTV page, the series
  /// page, the Home shelf, and the native TV player's bridge hop — and live
  /// channels never reach it.
  static Future<void> recordIptvWatch(
    String channelUrl, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    Map<String, String>? httpHeaders,
    // Series-episode markers (Xtream series only). When set, the Continue
    // Watching shelf collapses a series' episodes into one row and keeps the
    // series present after a mid-series episode finishes. Absent for movies /
    // catchup / live — their behavior is unchanged.
    String? seriesId,
    String? seriesName,
    int? season,
    int? episode,
    bool? hasNextEpisode,
  }) async {
    if (!await getIptvTrackContinueWatching()) return;
    return IptvMediaStore.recordWatch(
      channelUrl,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      httpHeaders: httpHeaders,
      seriesId: seriesId,
      seriesName: seriesName,
      season: season,
      episode: episode,
      hasNextEpisode: hasNextEpisode,
    );
  }

  static int _iptvWatchTimestamp(dynamic meta) {
    if (meta is Map) {
      final value = meta['lastPlayedAt'];
      if (value is num) return value.toInt();
    }
    return 0;
  }

  /// All remembered on-demand IPTV items (url → metadata).
  static Future<Map<String, Map<String, dynamic>>> getIptvWatchHistory() {
    return IptvMediaStore.watchHistory();
  }

  /// Watched-but-unfinished IPTV items, most recent first. Joins the metadata
  /// captured at play time with the position the players persist to the
  /// video-resume store (both keyed by stream URL), so an item only appears
  /// once it has real progress behind it.
  ///
  /// Each entry is the stored metadata plus `url`, `positionMs`, `durationMs`
  /// and `progress` (0-1).
  static Future<List<Map<String, dynamic>>> getIptvContinueWatching() async {
    // Tracking off hides the shelf everywhere at once: Home's two IPTV rows,
    // the IPTV page's virtual `continue://` playlist (which already drops
    // itself when this comes back empty), and the command rail's count.
    if (!await getIptvTrackContinueWatching()) return [];
    final history = await getIptvWatchHistory();
    if (history.isEmpty) return [];

    // History is capped at 100 entries, so this is a small batched lookup.
    final resumeMap = await IptvMediaStore.resumeEntries(history.keys);

    // Series identity for grouping: <playlistId>::<seriesId>. Same shape the
    // shelf and per-series audio use.
    String? seriesKeyOf(Map<String, dynamic> meta) {
      final sid = meta['seriesId'];
      if (sid == null || (sid is String && sid.isEmpty)) return null;
      return '${meta['playlistId'] ?? ''}::$sid';
    }

    // First pass: gather every started entry with its recency, and track the
    // most-recent recency per series.
    final started = <Map<String, dynamic>>[];
    final seriesLatest = <String, int>{};
    for (final entry in history.entries) {
      final resume = resumeMap[entry.key];
      if (resume == null) continue;
      final positionMs = (resume['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (resume['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0) continue;
      final progress = positionMs / durationMs;
      if (progress < _iptvWatchStartedFraction) continue;

      final sortAt =
          (resume['updatedAt'] as num?)?.toInt() ??
          _iptvWatchTimestamp(entry.value);
      final seriesKey = seriesKeyOf(entry.value);
      if (seriesKey != null) {
        final prev = seriesLatest[seriesKey];
        if (prev == null || sortAt > prev) seriesLatest[seriesKey] = sortAt;
      }
      started.add({
        ...entry.value,
        'url': entry.key,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'progress': progress,
        // Prefer when playback last moved; a rebuilt-metadata entry can be
        // older than the watching it describes.
        'sortAt': sortAt,
        if (seriesKey != null) '_seriesKey': seriesKey,
      });
    }

    // Second pass: a partially-watched item always shows. A FINISHED item is
    // kept only when it's a series episode that (a) still has a next episode
    // and (b) is the most-recent watched episode of its series — so a series
    // stays for "next up" after finishing a middle episode, but leaves once
    // its finale (or last-watched episode) is done. Movies/catchup and older
    // finished episodes drop out as before.
    final items = <Map<String, dynamic>>[];
    for (final item in started) {
      final progress = item['progress'] as double;
      if (progress <= iptvWatchFinishedFraction) {
        items.add(item);
        continue;
      }
      final seriesKey = item['_seriesKey'] as String?;
      final keep =
          seriesKey != null &&
          item['hasNext'] == true &&
          (item['sortAt'] as int) == seriesLatest[seriesKey];
      if (keep) items.add(item);
    }

    items.sort((a, b) => (b['sortAt'] as int).compareTo(a['sortAt'] as int));
    return items;
  }

  /// Stored position/duration for whichever of [urls] the players have
  /// progress for. Reads the resume map once — callers are typically a list of
  /// thousands of rows.
  static Future<
    Map<String, ({int positionMs, int durationMs, double fraction})>
  >
  _iptvResumeStates(Iterable<String> urls) async {
    final wanted = urls.toSet();
    if (wanted.isEmpty) return {};

    final resumeMap = await IptvMediaStore.resumeEntries(wanted);
    final states =
        <String, ({int positionMs, int durationMs, double fraction})>{};
    for (final entry in resumeMap.entries) {
      final resume = entry.value;
      final positionMs = (resume['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (resume['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0) continue;
      states[entry.key] = (
        positionMs: positionMs,
        durationMs: durationMs,
        fraction: (positionMs / durationMs).clamp(0.0, 1.0),
      );
    }
    return states;
  }

  /// Resume fractions (0-1) for whichever of [urls] have been started. No
  /// upper bound — a finished item shows a full bar, which is the point.
  static Future<Map<String, double>> getIptvProgressForUrls(
    Iterable<String> urls,
  ) async {
    final states = await _iptvResumeStates(urls);
    return {
      for (final entry in states.entries)
        if (entry.value.fraction >= _iptvWatchStartedFraction)
          entry.key: entry.value.fraction,
    };
  }

  /// Resume position in ms for each part-watched item among [urls], using the
  /// same window as the shelf — so a finished item restarts from the
  /// beginning rather than resuming a second from the end.
  static Future<Map<String, int>> getIptvResumePositions(
    Iterable<String> urls,
  ) async {
    final states = await _iptvResumeStates(urls);
    return {
      for (final entry in states.entries)
        if (entry.value.fraction >= _iptvWatchStartedFraction &&
            entry.value.fraction <= iptvWatchFinishedFraction)
          entry.key: entry.value.positionMs,
    };
  }

  /// Remove all watch history that belongs to a deleted playlist — mirrors
  /// [removeIptvFavoritesByPlaylistId] so a removed provider leaves nothing
  /// behind pointing at URLs that no longer authenticate.
  static Future<void> removeIptvWatchHistoryByPlaylistId(String playlistId) {
    return IptvMediaStore.removeWatchHistoryByPlaylistId(playlistId);
  }

  /// Take one on-demand IPTV item off the Continue Watching shelf (history +
  /// saved position). The local counterpart of [removeContinueWatchingItem].
  static Future<void> removeIptvContinueWatchingItem(String url) {
    return IptvMediaStore.removeWatchEntry(url);
  }

  /// Take a whole IPTV series off the Continue Watching shelf — every watched
  /// episode of it, since the shelf collapses them into one card.
  static Future<void> removeIptvContinueWatchingSeries({
    required String playlistId,
    required String seriesId,
  }) {
    return IptvMediaStore.removeWatchSeries(
      playlistId: playlistId,
      seriesId: seriesId,
    );
  }

  /// The audio LANGUAGE the user last chose for an IPTV series (keyed by the
  /// series' name). Language, not the mpv track ordinal — episodes are
  /// separate files whose track ordering differs, so an ordinal wouldn't
  /// carry. Null when the series has no remembered choice.
  static Future<String?> getIptvSeriesAudioLanguage(String seriesKey) async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map[seriesKey] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Remember the audio language for an IPTV series so later episodes (and
  /// future sessions) default to it.
  static Future<void> setIptvSeriesAudioLanguage(
    String seriesKey,
    String languageCode,
  ) async {
    if (seriesKey.isEmpty || languageCode.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    Map<String, dynamic> map = {};
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    map[seriesKey] = languageCode;
    await prefs.setString(_iptvSeriesAudioLangKey, jsonEncode(map));
  }

  // IPTV Playlist Settings

  /// Credential-bearing fields of a stored playlist. Encrypted field-level
  /// rather than sealing the whole element: `content` can be a multi-megabyte
  /// raw M3U body and this getter sits on hot paths, so blob-level AES would
  /// cost real time on TV hardware for data that arrived as a plaintext file
  /// the user chose. Residual: URLs embedded inside a file-imported `content`
  /// body stay plaintext — accepted.
  static const List<String> _iptvPlaylistSecretFields = [
    'url', 'serverUrl', 'username', 'password', 'epgUrl', //
  ];

  /// Restores the `url` key the legacy→profile migration erased.
  ///
  /// An Xtream provider legitimately stores `url: ''` — its endpoint is
  /// [IptvPlaylist.serverUrl]. The migration's shared resource writer stripped
  /// every empty value before sealing, so an Xtream resource migrated by an
  /// affected build carries no `url` key at all, and `IptvPlaylist.fromJson`
  /// threw on the required cast. That took out the ENTIRE playlist list — and
  /// with it the IPTV page — rather than the one provider.
  ///
  /// Fixing the migration cannot help these devices: migration is a one-way
  /// door that never re-runs. Repairing on read is what brings them back, and
  /// it keeps working for anyone who migrated on an affected build and updates
  /// later.
  ///
  /// TWO provider kinds legitimately carry an empty `url`, and both are
  /// repaired: an Xtream login (endpoint in `serverUrl`) and a playlist
  /// imported from a file (body in `content` — see the IPTV settings page,
  /// which writes `url: ''` for exactly that reason). Neither field is
  /// stripped by the migration, so either one identifies a record whose empty
  /// `url` was real rather than missing.
  ///
  /// Still deliberately narrow: a row with none of the three is genuinely
  /// malformed and keeps throwing, because papering over that would turn real
  /// corruption into a silent blank provider.
  static Map<String, dynamic> _repairMigratedIptvRow(Map<String, dynamic> row) {
    if (row['url'] != null) return row;
    if (!_hasText(row['serverUrl']) && !_hasText(row['content'])) return row;
    return <String, dynamic>{...row, 'url': ''};
  }

  static bool _hasText(Object? value) =>
      value is String && value.trim().isNotEmpty;

  /// Get all saved IPTV playlists
  static Future<List<IptvPlaylist>> getIptvPlaylists({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows
          .map(_repairMigratedIptvRow)
          .map(IptvPlaylist.fromJson)
          .toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = prefs.getStringList(_iptvPlaylistsKey) ?? [];
    var legacySeen = false;
    var anyDropped = false;
    final playlists = <IptvPlaylist>[];
    for (final json in jsonList) {
      try {
        final opened = await SecretVault.openFields(
          Map<String, dynamic>.from(jsonDecode(json) as Map),
          _iptvPlaylistSecretFields,
        );
        if (opened.wasLegacy) legacySeen = true;
        // A playlist whose url failed to decrypt throws in fromJson and is
        // dropped here — same signed-out semantics as the standalone keys.
        playlists.add(IptvPlaylist.fromJson(opened.map));
      } catch (e) {
        // Skip malformed entries FOR THIS READ only.
        anyDropped = true;
      }
    }
    // Migrate lazily, but never off a lossy read: rewriting while an entry
    // failed (possibly a transient vault-key hiccup) would turn a one-launch
    // read error into permanent deletion. A later clean read migrates.
    if (legacySeen && !anyDropped) {
      await setIptvPlaylists(playlists);
    }
    return playlists;
  }

  /// Save IPTV playlists.
  ///
  /// Virtual playlists (Favorites, custom lists, Continue watching, Stremio
  /// addon shelves) are dropped here rather than trusted not to arrive: the
  /// page's own list holds real and virtual entries side by side, and a
  /// virtual one that reached the preference would be restored AND injected
  /// on the next load — two entries with the same id, where id-only equality
  /// makes lookups resolve the stale copy.
  static Future<void> setIptvPlaylists(
    List<IptvPlaylist> playlists, {
    bool revokeBorrowers = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final stored = playlists.where((playlist) => !playlist.isVirtual);
      await ProfileCollectionResourceFacade.replace(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        items: <ResourceCollectionItem>[
          for (final playlist in stored)
            ResourceCollectionItem(
              type: playlist.isXtreamCodes
                  ? ConnectionResourceType.iptvXtream
                  : ConnectionResourceType.iptvM3u,
              label: playlist.name,
              publicConfig: <String, dynamic>{
                'playlistName': playlist.name,
                'providerKind': playlist.isXtreamCodes ? 'xtream' : 'm3u',
              },
              secretConfig: playlist.toJson(),
              sourceResourceId: playlist.connectionResourceId,
            ),
        ],
        revokeBorrowers: revokeBorrowers,
      );
      return;
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = <String>[];
    for (final p in playlists.where((p) => !p.isVirtual)) {
      jsonList.add(
        jsonEncode(
          await SecretVault.sealFields(p.toJson(), _iptvPlaylistSecretFields),
        ),
      );
    }
    await prefs.setStringList(_iptvPlaylistsKey, jsonList);
  }

  /// Persists an IPTV collection and returns the authoritative records.
  ///
  /// In profile mode a collection write can mint or rotate connection
  /// resources, so the caller's input objects are deliberately not execution
  /// capabilities. UI code that keeps using those objects would have no
  /// resource ID for a new playlist, or a stale revision for an existing one.
  static Future<List<IptvPlaylist>> setIptvPlaylistsAndReload(
    List<IptvPlaylist> playlists, {
    required bool forSettings,
    bool revokeBorrowers = false,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active
        ? ProfileRuntime.scope.value
        : null;
    await setIptvPlaylists(playlists, revokeBorrowers: revokeBorrowers);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active ||
            ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while saving IPTV playlists');
    }
    final saved = await getIptvPlaylists(forSettings: forSettings);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active ||
            ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while loading IPTV playlists');
    }
    return saved;
  }

  /// Get default IPTV playlist ID
  static Future<String?> getIptvDefaultPlaylist() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iptvDefaultPlaylistKey);
  }

  /// Set default IPTV playlist ID
  static Future<void> setIptvDefaultPlaylist(String? playlistId) async {
    final prefs = await ProfilePreferences.instance();
    if (playlistId == null || playlistId.isEmpty) {
      await prefs.remove(_iptvDefaultPlaylistKey);
    } else {
      await prefs.setString(_iptvDefaultPlaylistKey, playlistId);
    }
  }

  /// Check if IPTV defaults have been initialized (to avoid re-adding after user deletes)
  static Future<bool> getIptvDefaultsInitialized() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_iptvDefaultsInitializedKey) ?? false;
  }

  /// Mark IPTV defaults as initialized
  static Future<void> setIptvDefaultsInitialized(bool initialized) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_iptvDefaultsInitializedKey, initialized);
  }

  // ==========================================================================
  // Last live IPTV channel (startup-channel memory)
  //
  // Single slot, overwritten. Written ONLY once a live channel has actually
  // reached a playing state — never at tune time. Both players call in from
  // their playing-state transition; recording an *attempted* tune would let one
  // dead stream replace the last working channel, and the startup feature
  // re-tunes this unattended on every cold boot, so a dead entry would mean
  // booting into failure until the user cancels out of it.
  //
  // Deliberately NOT [recordIptvWatch]: that store is the Continue Watching
  // shelf, which is on-demand only ("62% through Sky Sports" is meaningless).
  // ==========================================================================

  /// Remember [url]/[name] as the last live channel that actually played.
  ///
  /// [playlistId] is the channel's ORIGIN provider, not whichever shelf it was
  /// launched from — a channel played out of Favourites or a custom list must
  /// come back under its real provider's credentials.
  ///
  /// The provider fingerprint (`serverUrl` + `username`) is resolved here from
  /// [playlistId] rather than asked of callers: the players know only a source
  /// id, and the fingerprint has to be captured while the playlist still
  /// exists — it is what allows a re-added Xtream account (which mints a fresh
  /// playlist id) to be recognised later. Resolving it costs one prefs read,
  /// paid once per settled channel, never per zap.
  static Future<void> setIptvLastLiveChannel(
    String url, {
    required String name,
    String? playlistId,
    int? channelNumber,
    String? group,
    String? logoUrl,
    Map<String, String>? httpHeaders,
  }) async {
    if (url.isEmpty) return;
    String? serverUrl;
    String? username;
    if (playlistId != null && playlistId.isNotEmpty) {
      try {
        for (final playlist in await getIptvPlaylists()) {
          if (playlist.id == playlistId) {
            if (playlist.isXtreamCodes) {
              serverUrl = playlist.serverUrl;
              username = playlist.username;
            }
            break;
          }
        }
      } catch (_) {
        // Fingerprint is a recovery aid, never a precondition — a failed
        // lookup still stores a usable entry keyed by playlist id.
      }
    }
    final prefs = await ProfilePreferences.instance();
    // Sealed whole: the stored Xtream `url` embeds the account password.
    await SecretVault.setString(
      prefs,
      _iptvLastLiveChannelKey,
      jsonEncode({
        'url': url,
        'name': name,
        if (playlistId != null && playlistId.isNotEmpty)
          'playlistId': playlistId,
        if (channelNumber != null) 'channelNumber': channelNumber,
        if (group != null && group.isNotEmpty) 'group': group,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (httpHeaders != null && httpHeaders.isNotEmpty)
          'httpHeaders': httpHeaders,
        if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
        if (username != null && username.isNotEmpty) 'username': username,
        'playedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// The last live channel that reached a playing state, or null.
  static Future<Map<String, dynamic>?> getIptvLastLiveChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _iptvLastLiveChannelKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Malformed (hand-edited prefs, or a format change): treat as absent
      // rather than throwing on a startup path.
    }
    return null;
  }

  static Future<void> clearIptvLastLiveChannel() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_iptvLastLiveChannelKey);
  }

  // ==========================================================================
  // Startup channel (boot straight into a live IPTV channel)
  //
  // Reuses the surviving `startup_auto_launch_enabled` / `startup_mode` keys
  // from the removed general Launch-on-Startup feature; `startup_mode` is set
  // to 'iptv' so a future second mode can coexist without another master flag.
  // ==========================================================================
  static Future<bool> getStartupIptvEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getBool(_startupAutoLaunchEnabledKey) ?? false) &&
        prefs.getString(_startupModeKey) == 'iptv';
  }

  static Future<void> setStartupIptvEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_startupAutoLaunchEnabledKey, enabled);
    if (enabled) {
      await prefs.setString(_startupModeKey, 'iptv');
    } else {
      // Leave the mode behind rather than clearing it: re-enabling should come
      // back to IPTV, not to a blank slate.
      await prefs.remove(_startupModeKey);
    }
  }

  static Future<String> getStartupIptvMode() async {
    final prefs = await ProfilePreferences.instance();
    final mode = prefs.getString(_startupIptvModeKey);
    return mode == startupIptvModePinned
        ? startupIptvModePinned
        : startupIptvModeLast;
  }

  static Future<void> setStartupIptvMode(String mode) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _startupIptvModeKey,
      mode == startupIptvModePinned
          ? startupIptvModePinned
          : startupIptvModeLast,
    );
  }

  /// The pinned startup channel. Same blob shape as [setIptvLastLiveChannel],
  /// so both modes resolve through one code path at launch.
  static Future<Map<String, dynamic>?> getStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, _startupIptvChannelKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// [playlistId] must be the channel's ORIGIN provider — the picker aggregates
  /// Favourites and custom lists, where the same URL can exist under two
  /// different providers, so a URL alone cannot identify which one was chosen.
  static Future<void> setStartupIptvChannel(
    String url, {
    required String name,
    String? playlistId,
    int? channelNumber,
    String? group,
    String? logoUrl,
    Map<String, String>? httpHeaders,
  }) async {
    if (url.isEmpty) return;
    String? serverUrl;
    String? username;
    if (playlistId != null && playlistId.isNotEmpty) {
      try {
        for (final playlist in await getIptvPlaylists()) {
          if (playlist.id == playlistId) {
            if (playlist.isXtreamCodes) {
              serverUrl = playlist.serverUrl;
              username = playlist.username;
            }
            break;
          }
        }
      } catch (_) {}
    }
    final prefs = await ProfilePreferences.instance();
    // Sealed whole for the same reason as the last-live-channel blob: the
    // Xtream `url` embeds the account password.
    await SecretVault.setString(
      prefs,
      _startupIptvChannelKey,
      jsonEncode({
        'url': url,
        'name': name,
        if (playlistId != null && playlistId.isNotEmpty)
          'playlistId': playlistId,
        if (channelNumber != null) 'channelNumber': channelNumber,
        if (group != null && group.isNotEmpty) 'group': group,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logoUrl': logoUrl,
        if (httpHeaders != null && httpHeaders.isNotEmpty)
          'httpHeaders': httpHeaders,
        if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
        if (username != null && username.isNotEmpty) 'username': username,
      }),
    );
  }

  static Future<void> clearStartupIptvChannel() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_startupIptvChannelKey);
  }

  // --- Synchronous startup handoff -----------------------------------------
  //
  // MainPage's `_selectedIndex` is a FIELD INITIALIZER: it runs at construction,
  // long before any async prefs read could answer. Warming the decision in
  // main() before runApp is the same trick `PlatformUtil.isAndroidTvCached`
  // uses, and it is what keeps the Home board from mounting and starting its
  // cold-start IO before we swap to IPTV.

  /// The channel to boot into, or null. Only meaningful after [warmStartupIptv].
  static Map<String, dynamic>? startupIptvChannelCached;

  /// Resolve the startup channel once, before `runApp`. Never throws — a
  /// failure here must degrade to "no startup channel", never to a broken boot.
  static Future<void> warmStartupIptv() async {
    try {
      if (!await getStartupIptvEnabled()) return;
      final mode = await getStartupIptvMode();
      final channel = mode == startupIptvModePinned
          ? await getStartupIptvChannel()
          : await getIptvLastLiveChannel();
      final url = channel?['url'];
      if (url is! String || url.isEmpty) {
        // Nothing remembered yet — the very first boot after switching this on.
        // Rather than doing nothing (which reads as broken), hand the IPTV page
        // a sentinel and let it bootstrap from whatever it lands on. Resolved
        // there, not here, because picking "the first channel" needs the loaded
        // catalog and this runs before the first frame.
        //
        // Only for 'last': "a specific channel" with none chosen is a
        // deliberate blank the settings row already labels, and auto-picking
        // something else would contradict what the user asked for.
        if (mode == startupIptvModeLast) {
          startupIptvChannelCached = const {startupIptvFirstAvailable: true};
        }
        return;
      }
      startupIptvChannelCached = channel;
    } catch (_) {
      startupIptvChannelCached = null;
    }
  }

  static Future<void> clearStartupIptvKeys() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_iptvLastLiveChannelKey);
    await prefs.remove(_startupIptvModeKey);
    await prefs.remove(_startupIptvChannelKey);
  }
}
