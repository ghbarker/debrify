import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'iptv_transfer_payload.dart';
import 'storage_service.dart';
import 'transfer/backup_models.dart';
import 'transfer/backup_selection.dart';
import 'transfer/transfer_category.dart';
import 'transfer/transfer_category_registry.dart';
import 'transfer/transfer_categories.dart';
import 'transfer/transfer_restore_helpers.dart';

export 'transfer/backup_models.dart';
export 'transfer/backup_selection.dart';
export 'transfer/transfer_categories.dart' show TransferCategories;
export 'transfer/transfer_category.dart' show TransferCategory;

/// Service for creating and applying configuration backups.
///
/// The backup payload mirrors what the Remote feature's "Transfer Everything"
/// flow sends over UDP, but assembled into a single JSON document suitable
/// for writing to a file. Categories covered:
///   - Real-Debrid API key
///   - Torbox API key
///   - Premiumize API key
///   - PikPak credentials (email + password)
///   - Trakt session (access, refresh, expiry, username)
///   - Simkl session (access token, username — no refresh/expiry, Simkl
///     tokens don't expire)
///   - Search engine IDs (restore re-downloads YAML from the remote registry)
///   - Stremio addon manifest URLs (restore re-fetches manifests)
///   - WebDAV servers (URL + credentials, may be LAN-only)
///   - Indexer managers (Jackett / Prowlarr — URL + API key, may be LAN-only)
///   - IPTV providers (M3U URLs and Xtream server + credentials), including
///     their manual category order and default landing category. Playlists
///     imported from a file are NOT included — their definition is the raw
///     M3U text, which would bloat the file past the size restore will read;
///     re-import the file on the other device.
///   - IPTV Favorites (starred channels)
///   - IPTV custom lists (each list with its channels)
///   - Home collections (imported Nuvio-style folder collections)
///   - Stream badge rulesets (imported badges.json sources)
///
/// Restore intentionally skips remote validation (network) for credentials —
/// the user trusts their own backup, so we write the stored values directly.
/// Search engines and addons still require network on restore.
class BackupRestoreService {
  /// Highest envelope version this app can read. v1 = the plain payload,
  /// v2 = the passphrase-encrypted envelope wrapping a v1 payload.
  static const int currentVersion = 2;

  /// Version stamped on plain payloads. Deliberately still 1: an unencrypted
  /// export must stay restorable on app versions that predate encryption,
  /// and only the v2 envelope needs the higher gate.
  static const int payloadVersion = 1;

  /// Build a backup payload from the current device's configuration.
  ///
  /// With [includeCredentials] false, account secrets are omitted entirely
  /// (debrid keys, PikPak, Trakt, Simkl, MDBList) or blanked in place (WebDAV
  /// passwords, indexer API keys, Xtream usernames/passwords) so a setup can
  /// be shared without handing over accounts. M3U playlist URLs are kept —
  /// the URL *is* the provider config; users who need those protected should
  /// use a passphrase instead.
  static Future<Map<String, dynamic>> buildBackup({
    bool includeCredentials = true,
  }) async {
    final ctx = TransferBuildContext(includeCredentials: includeCredentials);
    ctx.payload['version'] = payloadVersion;
    ctx.payload['createdAt'] = DateTime.now().toUtc().toIso8601String();
    for (final category in TransferCategoryRegistry.instance.all) {
      await category.build(ctx);
    }
    return ctx.payload;
  }

  @visibleForTesting
  static List<String> backupAddonManifestUrls(Iterable<String> urls) =>
      transferBackupAddonManifestUrls(urls);

  /// Summarize what's inside a parsed backup map (for the confirm dialog).
  static BackupSummary summarize(Map<String, dynamic> map) {
    int countOf(TransferCategory category) => category.count(map);
    bool present(TransferCategory category) => countOf(category) > 0;
    return BackupSummary(
      version: (map['version'] as num?)?.toInt(),
      createdAt: map['createdAt'] as String?,
      hasRealDebrid: present(TransferCategories.realDebrid),
      hasTorbox: present(TransferCategories.torbox),
      hasPremiumize: present(TransferCategories.premiumize),
      hasAllDebrid: present(TransferCategories.allDebrid),
      hasPikpak: present(TransferCategories.pikpak),
      hasTrakt: present(TransferCategories.trakt),
      hasSimkl: present(TransferCategories.simkl),
      hasMdblist: present(TransferCategories.mdblist),
      searchEngineCount: countOf(TransferCategories.searchEngines),
      addonCount: countOf(TransferCategories.addons),
      webDavServerCount: countOf(TransferCategories.webDav),
      indexerManagerCount: countOf(TransferCategories.indexerManagers),
      iptvPlaylistCount: countOf(TransferCategories.iptvPlaylists),
      iptvFavoriteCount: countOf(TransferCategories.iptvFavorites),
      iptvListCount: countOf(TransferCategories.iptvLists),
      iptvListChannelCount: IptvTransferPayload.countListChannels(
        (map['iptvLists'] as List?) ?? const [],
      ),
      homeCollectionCount: countOf(TransferCategories.homeCollections),
      streamBadgeSourceCount: countOf(TransferCategories.streamBadges),
    );
  }

  /// Parse a JSON string into a backup map. Throws [FormatException] on
  /// invalid JSON or unrecognized shape.
  static Map<String, dynamic> parse(String jsonContent) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonContent);
    } catch (e) {
      throw const FormatException('File is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup file is not a JSON object');
    }
    final version = (decoded['version'] as num?)?.toInt();
    if (version == null) {
      throw const FormatException('Missing "version" field');
    }
    if (version > currentVersion) {
      throw FormatException(
        'Backup version $version is newer than this app supports '
        '(max $currentVersion). Update the app and try again.',
      );
    }
    return decoded;
  }

  /// Whether a parsed map is a passphrase-encrypted v2 envelope (whose inner
  /// payload must be recovered with [decryptBackup] before use).
  static bool isEncrypted(Map<String, dynamic> map) => map['encrypted'] == true;

  /// Wrap a plain backup payload in a passphrase-encrypted v2 envelope.
  ///
  /// `createdAt` is duplicated outside the ciphertext so the restore dialog
  /// can show it before asking for the passphrase. Always writes Argon2id;
  /// [kdfParams] exists so tests can use fast parameters.
  static Future<Map<String, dynamic>> encryptBackup(
    Map<String, dynamic> payload,
    String passphrase, {
    @visibleForTesting BackupKdfParams kdfParams = const BackupKdfParams(),
  }) async {
    final salt = _randomBytes(16);
    final key = await Argon2id(
      parallelism: kdfParams.parallelism,
      memory: kdfParams.memory,
      iterations: kdfParams.iterations,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
    );
    return <String, dynamic>{
      'version': 2,
      'encrypted': true,
      if (payload['createdAt'] is String) 'createdAt': payload['createdAt'],
      'kdf': <String, dynamic>{
        'algo': 'argon2id',
        'salt': base64Encode(salt),
        'm': kdfParams.memory,
        't': kdfParams.iterations,
        'p': kdfParams.parallelism,
      },
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(<int>[...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Recover the inner payload of a v2 envelope.
  ///
  /// Throws [BackupPassphraseException] when the passphrase is wrong (GCM tag
  /// failure) and [FormatException] when the envelope itself is malformed or
  /// uses an unknown KDF. KDF parameters are read FROM the envelope;
  /// `pbkdf2-hmac-sha256` is accepted on import for forward compatibility
  /// even though this app only ever writes `argon2id`.
  static Future<Map<String, dynamic>> decryptBackup(
    Map<String, dynamic> envelope,
    String passphrase,
  ) async {
    final kdf = envelope['kdf'];
    final nonceB64 = envelope['nonce'];
    final ciphertextB64 = envelope['ciphertext'];
    if (kdf is! Map || nonceB64 is! String || ciphertextB64 is! String) {
      throw const FormatException('Encrypted backup is missing fields');
    }
    final List<int> salt;
    final List<int> nonce;
    final List<int> packed;
    try {
      salt = base64Decode(kdf['salt'] as String);
      nonce = base64Decode(nonceB64);
      packed = base64Decode(ciphertextB64);
    } catch (_) {
      throw const FormatException('Encrypted backup is corrupted');
    }
    if (packed.length < 16) {
      throw const FormatException('Encrypted backup is corrupted');
    }

    // The KDF cost parameters come from the FILE — cap them before deriving,
    // or a crafted backup can request gigabytes of Argon2 memory and freeze
    // the app the moment the user enters a passphrase.
    int boundedParam(dynamic value, int fallback, int min, int max) {
      if (value != null && value is! num) {
        throw const FormatException('Encrypted backup is corrupted');
      }
      final parsed = value == null ? fallback : (value as num).toInt();
      if (parsed < min || parsed > max) {
        throw const FormatException(
          'Encrypted backup requests unreasonable KDF cost',
        );
      }
      return parsed;
    }

    if (salt.length < 8 || salt.length > 64) {
      throw const FormatException('Encrypted backup is corrupted');
    }

    final algo = kdf['algo'];
    final SecretKey key;
    if (algo == 'argon2id') {
      final parallelism = boundedParam(kdf['p'], 1, 1, 8);
      final memory = boundedParam(kdf['m'], 19456, 8, 131072); // ≤ 128 MiB
      // Argon2 itself requires memory ≥ 8·parallelism; values passing the
      // independent bounds (e.g. p=8, m=8) would throw an ArgumentError out
      // of the KDF instead of the FormatException the UI handles.
      if (memory < 8 * parallelism) {
        throw const FormatException(
          'Encrypted backup requests unreasonable KDF cost',
        );
      }
      key = await Argon2id(
        parallelism: parallelism,
        memory: memory,
        iterations: boundedParam(kdf['t'], 2, 1, 16),
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    } else if (algo == 'pbkdf2-hmac-sha256') {
      key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: boundedParam(kdf['iterations'], 600000, 1000, 5000000),
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    } else {
      throw FormatException('Unknown backup KDF "$algo"');
    }

    final box = SecretBox(
      packed.sublist(0, packed.length - 16),
      nonce: nonce,
      mac: Mac(packed.sublist(packed.length - 16)),
    );
    final List<int> plaintext;
    try {
      plaintext = await AesGcm.with256bits().decrypt(box, secretKey: key);
    } catch (_) {
      throw const BackupPassphraseException();
    }
    final dynamic inner;
    try {
      inner = jsonDecode(utf8.decode(plaintext));
    } catch (_) {
      throw const FormatException('Encrypted backup is corrupted');
    }
    if (inner is! Map<String, dynamic>) {
      throw const FormatException('Encrypted backup is corrupted');
    }
    // The decrypted payload bypasses parse(), so it needs the same version
    // gate — an envelope wrapping a future (or version-less) payload must
    // fail here, exactly as its plaintext twin would.
    final innerVersion = (inner['version'] as num?)?.toInt();
    if (innerVersion == null) {
      throw const FormatException('Missing "version" field');
    }
    if (innerVersion > currentVersion) {
      throw FormatException(
        'Backup version $innerVersion is newer than this app supports '
        '(max $currentVersion). Update the app and try again.',
      );
    }
    return inner;
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  /// Apply a parsed backup. Returns a [RestoreReport] summarizing what was
  /// applied and what failed. Network is only required for search engines
  /// and addons; credential restores are local writes.
  static Future<RestoreReport> applyBackup(
    Map<String, dynamic> map, {
    BackupSelection? selection,
    bool refreshEngineRuntime = true,
  }) async {
    final selected = selection ?? BackupSelection.all();
    final report = RestoreReport();
    final ctx = TransferApplyContext(
      map: map,
      report: report,
      refreshEngineRuntime: refreshEngineRuntime,
    );

    for (final category in TransferCategoryRegistry.instance.all) {
      if (!selected.contains(category)) continue;
      await category.apply(ctx);
    }

    final trackingPreferences = map['trackingPreferences'];
    if (trackingPreferences == null &&
        (report.trakt || report.simkl || report.mdblist)) {
      // Old backup: it restored the legacy per-tracker sync-catalog switches
      // but carries no tracking payload. The scrobble masters were already
      // seeded on this install's first policy read, so re-adopt the
      // just-restored legacy values (absent-key rule: Trakt/Simkl default ON,
      // MDBList follows its restored switch).
      //
      // Same as the pre-registry `else if`: this also runs when tracking
      // preferences were not selected, as long as the key is absent.
      await StorageService.reseedTrackingScrobbleTargetsFromLegacy();
    }

    return report;
  }
}

/// Wrong passphrase for an encrypted backup (GCM authentication failed).
/// Distinct from [FormatException] so the import UI can re-prompt instead of
/// aborting.
class BackupPassphraseException implements Exception {
  const BackupPassphraseException();

  @override
  String toString() => 'Wrong passphrase';
}

/// Argon2id cost parameters for [BackupRestoreService.encryptBackup].
/// Defaults are the OWASP minimum recommendation (19 MiB, t=2, p=1) — heavy
/// enough to matter, light enough for TV hardware on a user-initiated action.
class BackupKdfParams {
  /// Memory in 1 KiB blocks.
  final int memory;
  final int iterations;
  final int parallelism;

  const BackupKdfParams({
    this.memory = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });
}
