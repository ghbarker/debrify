import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:flutter_test/flutter_test.dart';

// Origin pin: this import must stay on the legacy path across the owner move.
// Read actual lib objects; do not reconstruct copyWithTitle in the test.
Map<String, Object?> fieldsOf(PlaylistEntry entry) => {
  'url': entry.url,
  'title': entry.title,
  'hdVideoUrl': entry.hdVideoUrl,
  'audioUrl': entry.audioUrl,
  'relativePath': entry.relativePath,
  'restrictedLink': entry.restrictedLink,
  'torrentHash': entry.torrentHash,
  'sizeBytes': entry.sizeBytes,
  'provider': entry.provider,
  'torboxTorrentId': entry.torboxTorrentId,
  'torboxWebDownloadId': entry.torboxWebDownloadId,
  'torboxFileId': entry.torboxFileId,
  'pikpakFileId': entry.pikpakFileId,
  'rdTorrentId': entry.rdTorrentId,
  'rdLinkIndex': entry.rdLinkIndex,
  'premiumizeHash': entry.premiumizeHash,
  'premiumizePath': entry.premiumizePath,
  'premiumizeItemId': entry.premiumizeItemId,
  'allDebridLink': entry.allDebridLink,
};

const populated = PlaylistEntry(
  url: 'https://muxed.example/fallback?token=original',
  title: 'Original title',
  hdVideoUrl: 'https://video.example/hd',
  audioUrl: 'https://audio.example/track',
  relativePath: '/Season 01/Episode 02.mkv',
  restrictedLink: 'https://restricted.example/link',
  torrentHash: 'AbCdEf012345',
  sizeBytes: 9007199254740991,
  provider: ' Real_Debrid ',
  torboxTorrentId: 101,
  torboxWebDownloadId: 202,
  torboxFileId: 303,
  pikpakFileId: 'pikpak-file',
  rdTorrentId: 'rd-torrent',
  rdLinkIndex: 404,
  premiumizeHash: 'premiumize-hash',
  premiumizePath: '/PM/Case Sensitive.mkv',
  premiumizeItemId: 'premiumize-item',
  allDebridLink: 'https://alldebrid.example/locked',
);

const populatedFields = <String, Object?>{
  'url': 'https://muxed.example/fallback?token=original',
  'title': 'Original title',
  'hdVideoUrl': 'https://video.example/hd',
  'audioUrl': 'https://audio.example/track',
  'relativePath': '/Season 01/Episode 02.mkv',
  'restrictedLink': 'https://restricted.example/link',
  'torrentHash': 'AbCdEf012345',
  'sizeBytes': 9007199254740991,
  'provider': ' Real_Debrid ',
  'torboxTorrentId': 101,
  'torboxWebDownloadId': 202,
  'torboxFileId': 303,
  'pikpakFileId': 'pikpak-file',
  'rdTorrentId': 'rd-torrent',
  'rdLinkIndex': 404,
  'premiumizeHash': 'premiumize-hash',
  'premiumizePath': '/PM/Case Sensitive.mkv',
  'premiumizeItemId': 'premiumize-item',
  'allDebridLink': 'https://alldebrid.example/locked',
};

void main() {
  test('old constructor leaves every omitted optional field null', () {
    const entry = PlaylistEntry(url: 'raw-url', title: 'raw-title');
    expect(fieldsOf(entry), {
      'url': 'raw-url',
      'title': 'raw-title',
      'hdVideoUrl': null,
      'audioUrl': null,
      'relativePath': null,
      'restrictedLink': null,
      'torrentHash': null,
      'sizeBytes': null,
      'provider': null,
      'torboxTorrentId': null,
      'torboxWebDownloadId': null,
      'torboxFileId': null,
      'pikpakFileId': null,
      'rdTorrentId': null,
      'rdLinkIndex': null,
      'premiumizeHash': null,
      'premiumizePath': null,
      'premiumizeItemId': null,
      'allDebridLink': null,
    });
    final renamed = entry.copyWithTitle('');
    expect(fieldsOf(renamed), {...fieldsOf(entry), 'title': ''});
    expect(entry.title, 'raw-title');
    expect(identical(renamed, entry), isFalse);
  });

  test('old constructor preserves all explicit fields without normalization', () {
    expect(fieldsOf(populated), populatedFields);
  });

  test('explicit empty strings and zero identifiers survive constructor and copy', () {
    const entry = PlaylistEntry(
      url: '', title: '', hdVideoUrl: '', audioUrl: '', relativePath: '',
      restrictedLink: '', torrentHash: '', sizeBytes: 0, provider: '',
      torboxTorrentId: 0, torboxWebDownloadId: 0, torboxFileId: 0,
      pikpakFileId: '', rdTorrentId: '', rdLinkIndex: 0,
      premiumizeHash: '', premiumizePath: '', premiumizeItemId: '',
      allDebridLink: '',
    );
    final expected = <String, Object?>{
      'url': '', 'title': '', 'hdVideoUrl': '', 'audioUrl': '',
      'relativePath': '', 'restrictedLink': '', 'torrentHash': '',
      'sizeBytes': 0, 'provider': '', 'torboxTorrentId': 0,
      'torboxWebDownloadId': 0, 'torboxFileId': 0, 'pikpakFileId': '',
      'rdTorrentId': '', 'rdLinkIndex': 0, 'premiumizeHash': '',
      'premiumizePath': '', 'premiumizeItemId': '', 'allDebridLink': '',
    };
    expect(fieldsOf(entry), expected);
    final copy = entry.copyWithTitle('  S01E02  ');
    expect(fieldsOf(copy), {...expected, 'title': '  S01E02  '});
    expect(fieldsOf(entry), expected);
  });

  test('provider dialects and unknown strings remain opaque through copying', () {
    for (final provider in <String?>[
      null, '', 'debrid', 'rd', 'RD', 'realdebrid', 'real_debrid',
      'torbox', 'premiumize', 'alldebrid', 'pikpak', ' Real_Debrid ',
      '__unknown_provider__',
    ]) {
      final entry = PlaylistEntry(url: '', title: 'old', provider: provider);
      expect(entry.provider, provider, reason: 'constructor provider=$provider');
      final copy = entry.copyWithTitle('new');
      expect(copy.provider, provider, reason: 'copy provider=$provider');
      expect(entry.title, 'old');
      expect(copy.title, 'new');
    }
  });

  test('copyWithTitle changes only title and leaves its source unchanged', () {
    final renamed = populated.copyWithTitle('S01E02 — renamed');
    expect(fieldsOf(renamed), {...populatedFields, 'title': 'S01E02 — renamed'});
    expect(fieldsOf(populated), populatedFields);
    expect(identical(renamed, populated), isFalse);
    final sameTitle = populated.copyWithTitle(populated.title);
    expect(fieldsOf(sameTitle), populatedFields);
    expect(identical(sameTitle, populated), isFalse);
    final renamedAgain = renamed.copyWithTitle('');
    expect(fieldsOf(renamedAgain), {...populatedFields, 'title': ''});
    expect(fieldsOf(renamed), {...populatedFields, 'title': 'S01E02 — renamed'});
    expect(fieldsOf(populated), populatedFields);
  });

  test('every field rejects reassignment on origin and returned copy', () {
    final setters = <String, void Function(dynamic)>{
      'url': (entry) { entry.url = 'changed'; },
      'title': (entry) { entry.title = 'changed'; },
      'hdVideoUrl': (entry) { entry.hdVideoUrl = 'changed'; },
      'audioUrl': (entry) { entry.audioUrl = 'changed'; },
      'relativePath': (entry) { entry.relativePath = 'changed'; },
      'restrictedLink': (entry) { entry.restrictedLink = 'changed'; },
      'torrentHash': (entry) { entry.torrentHash = 'changed'; },
      'sizeBytes': (entry) { entry.sizeBytes = -1; },
      'provider': (entry) { entry.provider = 'changed'; },
      'torboxTorrentId': (entry) { entry.torboxTorrentId = -2; },
      'torboxWebDownloadId': (entry) { entry.torboxWebDownloadId = -3; },
      'torboxFileId': (entry) { entry.torboxFileId = -4; },
      'pikpakFileId': (entry) { entry.pikpakFileId = 'changed'; },
      'rdTorrentId': (entry) { entry.rdTorrentId = 'changed'; },
      'rdLinkIndex': (entry) { entry.rdLinkIndex = -5; },
      'premiumizeHash': (entry) { entry.premiumizeHash = 'changed'; },
      'premiumizePath': (entry) { entry.premiumizePath = 'changed'; },
      'premiumizeItemId': (entry) { entry.premiumizeItemId = 'changed'; },
      'allDebridLink': (entry) { entry.allDebridLink = 'changed'; },
    };
    for (final entry in [populated, populated.copyWithTitle(populated.title)]) {
      for (final setter in setters.entries) {
        expect(() => setter.value(entry), throwsA(isA<NoSuchMethodError>()),
            reason: '${setter.key} must stay final');
        expect(fieldsOf(entry), populatedFields);
      }
    }
  });
}
