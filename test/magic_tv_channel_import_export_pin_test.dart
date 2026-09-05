import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// M1-2 characterisation of channel import/export **before** the move to
/// `lib/services/debrify_tv/channel_import_export.dart` and
/// `lib/screens/debrify_tv/import_export_dialogs.dart`.
///
/// Does not import those files (they do not exist on the parent of the
/// move). After the move this suite still matches the same members
/// (optional leading underscore) by also reading the new files when
/// present — same pattern as `magic_tv_channel_cache_warmer_pin_test.dart`.
///
/// Origin (re-located by symbol after #87 / M1-1):
/// `_ChannelImportType`, `_ChannelImportOrigin`, `_handleImportChannels`,
/// `_selectImportMode`, `_handleImport*`, `_runChannelExportProgress`,
/// `_importChannelBytes` / zip / yaml / text / debrify / link,
/// `_determineImportType`, `_escapeYamlString`, `_generateChannelYaml`,
/// `_resolveUniqueChannelName`, `_formatBytes`, `_formatImportError`,
/// `_handleDeleteAllChannels`, `_handleShareChannelAsMagnet`.
///
/// Quirks pinned here (keep, do not "fix"):
/// * Import type prefers extension, then PK zip signature, then a UTF-8
///   `debrify://` prefix. Unknown text that is not a debrify link is
///   rejected (no yaml/txt content sniff).
/// * Text import splits on comma *per line*, trims, first-wins
///   case-insensitive dedup, keeps the first spelling, rejects a part
///   over 120 chars, rejects >500 keywords, empty file throws.
/// * Unique name: blank base → `Imported Channel`; collision suffix
///   starts at ` (2)`.
/// * `_formatBytes`: `<= 0` is `0 B`; value `>= 10` has no decimal.
/// * `_formatImportError`: FormatException uses `.message`; others strip
///   a leading `Exception: `.
/// * YAML string escape is `\` `"` newline CR tab only (no other YAML
///   specials). Torrent `sources` are quoted as-is (not escaped).
/// * YAML emit matches torrents by `keywords.contains(keywordLower)` and
///   dedupes by infohash first-wins. Empty keyword → `torrents: []`.
/// * Device-picker cancel after the mode dialog leaves `_isBusy` true
///   (url/community cancel paths do clear it).
/// * Delete-all on an empty library snacks and returns without a
///   confirm dialog.
/// * Create/update single-channel dialogs and watch flows stay on the
///   host (M1-5 / M1-3).
String _host() => File(
  'lib/screens/magic_tv_screen.dart',
).readAsStringSync().replaceAll('\r\n', '\n');

String _sources() {
  final buf = StringBuffer(_host());
  for (final path in <String>[
    'lib/services/debrify_tv/channel_import_export.dart',
    'lib/screens/debrify_tv/import_export_dialogs.dart',
  ]) {
    final moved = File(path);
    if (moved.existsSync()) {
      buf.writeln(moved.readAsStringSync().replaceAll('\r\n', '\n'));
    }
  }
  return buf.toString();
}

/// Origin `_formatBytes`.
String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final exponent = min(units.length - 1, (log(bytes) / log(1024)).floor());
  final value = bytes / pow(1024, exponent);
  final formatted = value >= 10
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[exponent]}';
}

/// Origin `_formatImportError`.
String formatImportError(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  return error.toString().replaceFirst('Exception: ', '').trim();
}

/// Origin `_stripExtension`.
String stripExtension(String name) {
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0) {
    return name.trim();
  }
  return name.substring(0, dotIndex).trim();
}

/// Origin `_guessExtensionFromHeaders`.
String guessExtensionFromHeaders(Map<String, String> headers) {
  final contentType =
      headers['content-type'] ?? headers['Content-Type'] ?? 'text/plain';
  if (contentType.contains('zip')) {
    return 'zip';
  }
  if (contentType.contains('yaml') || contentType.contains('yml')) {
    return 'yaml';
  }
  return 'txt';
}

enum ChannelImportType { zip, yaml, text, debrify }

/// Origin `_determineImportType`.
ChannelImportType? determineImportType(String sourceName, Uint8List bytes) {
  final lower = sourceName.toLowerCase();

  if (lower.endsWith('.zip')) {
    return ChannelImportType.zip;
  }
  if (lower.endsWith('.debrify')) {
    return ChannelImportType.debrify;
  }
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
    return ChannelImportType.yaml;
  }
  if (lower.endsWith('.txt')) {
    return ChannelImportType.text;
  }

  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    return ChannelImportType.zip;
  }

  try {
    final content = utf8.decode(bytes).trim();
    if (content.startsWith('debrify://')) {
      return ChannelImportType.debrify;
    }
  } catch (_) {}

  return null;
}

/// Origin `_resolveUniqueChannelName`.
String resolveUniqueChannelName(
  String baseName,
  Set<String> usedLowerCaseNames,
) {
  final String trimmed = baseName.trim().isEmpty
      ? 'Imported Channel'
      : baseName.trim();
  String candidate = trimmed;
  int suffix = 2;
  while (usedLowerCaseNames.contains(candidate.toLowerCase())) {
    candidate = '$trimmed ($suffix)';
    suffix++;
  }
  return candidate;
}

/// Origin `_escapeYamlString`.
String escapeYamlString(String value) {
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
}

/// Origin text-import keyword walk inside `_importTextBytes`.
List<String> parseTextImportKeywords(String content) {
  final keywords = <String>[];
  final seen = <String>{};

  final lines = const LineSplitter().convert(content);
  for (final rawLine in lines) {
    final parts = rawLine.split(',');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.length > 120) {
        throw FormatException(
          'Keyword exceeds 120 characters: "${trimmed.substring(0, trimmed.length > 40 ? 40 : trimmed.length)}${trimmed.length > 40 ? '…' : ''}"',
        );
      }
      final lower = trimmed.toLowerCase();
      if (seen.add(lower)) {
        keywords.add(trimmed);
      }
    }
  }

  if (keywords.isEmpty) {
    throw const FormatException('No keywords found in the selected file.');
  }
  if (keywords.length > 500) {
    throw const FormatException(
      'Channel files must contain 500 keywords or fewer.',
    );
  }
  return keywords;
}

/// Origin `_generateChannelYaml` emit (cache already loaded).
String generateChannelYaml({
  required String name,
  required bool avoidNsfw,
  required List<String> keywords,
  required List<CachedTorrent> cachedTorrents,
}) {
  final buffer = StringBuffer();
  buffer.writeln('channel_name: "$name"');
  buffer.writeln('avoid_nsfw: $avoidNsfw');
  buffer.writeln('');
  buffer.writeln('keywords:');

  for (final keyword in keywords) {
    buffer.writeln('  $keyword:');

    final keywordLower = keyword.toLowerCase();
    final matchingTorrents = cachedTorrents
        .where((t) => t.keywords.contains(keywordLower))
        .toList();

    final seen = <String>{};
    final uniqueTorrents = matchingTorrents.where((t) {
      if (seen.contains(t.infohash)) return false;
      seen.add(t.infohash);
      return true;
    }).toList();

    if (uniqueTorrents.isEmpty) {
      buffer.writeln('    torrents: []');
    } else {
      buffer.writeln('    torrents:');
      for (final torrent in uniqueTorrents) {
        buffer.writeln('      - infohash: ${torrent.infohash}');
        buffer.writeln('        name: "${escapeYamlString(torrent.name)}"');
        buffer.writeln('        size_bytes: ${torrent.sizeBytes}');
        buffer.writeln('        created_unix: ${torrent.createdUnix}');
        buffer.writeln('        seeders: ${torrent.seeders}');
        buffer.writeln('        leechers: ${torrent.leechers}');
        buffer.writeln('        completed: ${torrent.completed}');
        buffer.writeln('        scraped_date: ${torrent.scrapedDate}');
        if (torrent.sources.isNotEmpty) {
          buffer.writeln(
            '        sources: [${torrent.sources.map((s) => '"$s"').join(', ')}]',
          );
        }
      }
    }
  }

  return buffer.toString();
}

CachedTorrent _cached({
  required String infohash,
  String name = 'Show.mkv',
  List<String> keywords = const ['alpha'],
  List<String> sources = const [],
  int sizeBytes = 1,
}) {
  return CachedTorrent(
    rowid: 1,
    infohash: infohash,
    name: name,
    sizeBytes: sizeBytes,
    createdUnix: 0,
    seeders: 1,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    sources: sources,
    keywords: keywords,
  );
}

void main() {
  late String host;
  late String sources;

  setUpAll(() {
    host = _host();
    sources = _sources();
  });

  test('this pin does not import the move targets', () {
    final pin = File(
      'test/magic_tv_channel_import_export_pin_test.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r"^import .+channel_import_export\.dart",
        multiLine: true,
      ).hasMatch(pin),
      isFalse,
    );
    expect(
      RegExp(
        r"^import .+import_export_dialogs\.dart",
        multiLine: true,
      ).hasMatch(pin),
      isFalse,
    );
  });

  group('source still owns the origin import/export bodies', () {
    test('import type / origin / mode switch / export progress', () {
      expect(
        sources,
        contains(
          RegExp(r'enum _?ChannelImportType \{ zip, yaml, text, debrify \}'),
        ),
      );
      expect(
        sources,
        contains(RegExp(r'enum _?ChannelImportOrigin \{ device, url \}')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<void> _?handleImportChannels\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<ImportChannelsMode\?> _?selectImportMode\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<void> _?handleImportChannelsFromDevice\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<void> _?handleImportChannelsFromUrl\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<void> _?handleImportChannelsFromCommunity\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<T> _?runChannelExportProgress<T>\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<void> _?handleExportChannels\(')),
      );
    });

    test('bytes import / zip / yaml / text / debrify / link', () {
      expect(sources, contains(RegExp(r'Future<bool> _?importChannelBytes\(')));
      expect(
        sources,
        contains(RegExp(r'Future<bool> _?safeImportChannelBytes\(')),
      );
      expect(
        sources,
        contains(RegExp(r'_?ChannelImportType\? _?determineImportType\(')),
      );
      expect(sources, contains(RegExp(r'Future<bool> _?importZipBytes\(')));
      expect(sources, contains(RegExp(r'Future<bool> _?importYamlBytes\(')));
      expect(sources, contains(RegExp(r'Future<bool> _?importTextBytes\(')));
      expect(sources, contains(RegExp(r'Future<bool> _?importDebrifyBytes\(')));
      expect(
        sources,
        contains(RegExp(r'Future<void> _?importDebrifyLinkDirectly\(')),
      );
    });

    test('yaml emit / unique name / delete-all / share', () {
      expect(sources, contains(RegExp(r'String _?escapeYamlString\(')));
      expect(
        sources,
        contains(RegExp(r'Future<String> _?generateChannelYaml\(')),
      );
      expect(sources, contains(RegExp(r'String _?resolveUniqueChannelName\(')));
      expect(
        sources,
        contains(RegExp(r'Future<void> _?handleDeleteAllChannels\(')),
      );
      expect(
        sources,
        contains(RegExp(r'Future<void> _?handleShareChannelAsMagnet\(')),
      );
      expect(sources, contains(RegExp(r'String _?formatImportError\(')));
      expect(sources, contains(RegExp(r'String _?formatBytes\(')));
    });
  });

  group('_determineImportType origin algorithm', () {
    test('extension wins over content', () {
      final pk = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]);
      expect(determineImportType('pack.zip', pk), ChannelImportType.zip);
      expect(
        determineImportType('link.debrify', utf8.encode('not a link')),
        ChannelImportType.debrify,
      );
      expect(
        determineImportType('ch.yaml', utf8.encode('x')),
        ChannelImportType.yaml,
      );
      expect(
        determineImportType('ch.yml', utf8.encode('x')),
        ChannelImportType.yaml,
      );
      expect(
        determineImportType('kw.txt', utf8.encode('foo')),
        ChannelImportType.text,
      );
    });

    test('PK signature then debrify:// prefix; unknown text is rejected', () {
      expect(
        determineImportType('unknown.bin', Uint8List.fromList([0x50, 0x4b])),
        ChannelImportType.zip,
      );
      expect(
        determineImportType(
          'unknown.bin',
          utf8.encode('debrify://channel?v=1'),
        ),
        ChannelImportType.debrify,
      );
      expect(
        determineImportType('unknown.bin', utf8.encode('keywords: foo')),
        isNull,
      );
      expect(sources, contains('bytes[0] == 0x50 && bytes[1] == 0x4b'));
      expect(sources, contains("content.startsWith('debrify://')"));
    });
  });

  group('_formatBytes / _formatImportError / strip / headers', () {
    test('zero and negative are 0 B; >=10 has no decimal', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-3), '0 B');
      expect(formatBytes(9), '9.0 B');
      expect(formatBytes(10), '10 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(10 * 1024), '10 KB');
      expect(sources, contains("return '0 B';"));
      expect(sources, contains('value >= 10'));
    });

    test('FormatException uses message; others strip Exception: ', () {
      expect(formatImportError(const FormatException('bad yaml')), 'bad yaml');
      expect(formatImportError(Exception('boom')), 'boom');
      expect(
        sources,
        contains("error.toString().replaceFirst('Exception: ', '')"),
      );
    });

    test('stripExtension and header guess', () {
      expect(stripExtension('.hidden'), '.hidden');
      expect(stripExtension('channel.yaml'), 'channel');
      expect(stripExtension('  name  '), 'name');
      expect(
        guessExtensionFromHeaders({'content-type': 'application/zip'}),
        'zip',
      );
      expect(guessExtensionFromHeaders({'Content-Type': 'text/yaml'}), 'yaml');
      expect(guessExtensionFromHeaders(const {}), 'txt');
    });
  });

  group('_resolveUniqueChannelName origin algorithm', () {
    test('blank base becomes Imported Channel; suffix starts at 2', () {
      expect(resolveUniqueChannelName('  ', {}), 'Imported Channel');
      expect(resolveUniqueChannelName('News', {'news'}), 'News (2)');
      expect(
        resolveUniqueChannelName('News', {'news', 'news (2)'}),
        'News (3)',
      );
      expect(sources, contains("? 'Imported Channel'"));
      expect(sources, contains('int suffix = 2;'));
    });
  });

  group('_escapeYamlString / generateChannelYaml', () {
    test('escapes backslash quote newline CR tab only', () {
      expect(escapeYamlString(r'a\b"c'), r'a\\b\"c');
      expect(escapeYamlString('a\nb\rc\td'), r'a\nb\rc\td');
      expect(sources, contains(".replaceAll('\\\\', '\\\\\\\\')"));
    });

    test('empty keyword emits torrents: []; sources quoted as-is', () {
      final yaml = generateChannelYaml(
        name: 'News',
        avoidNsfw: true,
        keywords: ['Alpha', 'gone'],
        cachedTorrents: [
          _cached(
            infohash: 'aa',
            name: 'Show "1"',
            keywords: ['alpha'],
            sources: ['pb'],
          ),
          _cached(infohash: 'aa', name: 'dup', keywords: ['alpha']),
        ],
      );
      expect(yaml, contains('channel_name: "News"'));
      expect(yaml, contains('avoid_nsfw: true'));
      expect(yaml, contains('  Alpha:'));
      expect(yaml, contains('        name: "Show \\"1\\""'));
      expect(yaml, contains('        sources: ["pb"]'));
      expect(yaml, contains('  gone:\n    torrents: []\n'));
      expect('infohash: aa'.allMatches(yaml).length, 1);
    });
  });

  group('text import keyword walk', () {
    test('splits per line on comma; first-wins spelling; empty throws', () {
      expect(parseTextImportKeywords('  Foo, bar,\nFOO, baz  '), [
        'Foo',
        'bar',
        'baz',
      ]);
      expect(
        () => parseTextImportKeywords('  ,\n  '),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'No keywords found in the selected file.',
          ),
        ),
      );
      expect(sources, contains('if (trimmed.length > 120)'));
      expect(sources, contains('if (keywords.length > 500)'));
    });

    test('part over 120 chars throws with a 40-char preview', () {
      final long = 'x' * 121;
      expect(
        () => parseTextImportKeywords(long),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('busy / delete-all / apple-tv / device-cancel quirks', () {
    test('device-picker cancel does not clear busy; url/community do', () {
      expect(sources, contains('await _handleImportChannelsFromDevice();'));
      expect(
        host.contains(
              'if (selection == null || selection.files.isEmpty) {\n'
              '      return;\n'
              '    }',
            ) ||
            sources.contains(
              'if (selection == null || selection.files.isEmpty) {\n'
              '      return;\n'
              '    }',
            ),
        isTrue,
      );
      expect(
        sources,
        contains("Enter a valid debrify:// link or http(s) URL."),
      );
    });

    test('delete-all empty library snacks and returns', () {
      expect(sources, contains("'No channels to delete.'"));
      expect(
        sources,
        contains('await DebrifyTvRepository.instance.clearAll();'),
      );
      expect(sources, contains('await DebrifyTvCacheService.clearAll();'));
    });

    test('Apple TV export is a dedicated unavailable dialog', () {
      expect(sources, contains('if (PlatformUtil.isTvOS)'));
      expect(sources, contains("'Channel export · Apple TV'"));
      expect(
        sources,
        contains("'The ZIP is over 100 MB. Export fewer channels at a time.'"),
      );
    });
  });

  group('create/update and watch flows stay on the host', () {
    test('single-channel create/update dialogs are not this move', () {
      expect(host, contains('Future<void> _handleAddChannel()'));
      expect(host, contains('Future<void> _handleEditChannel('));
      expect(host, contains('Future<void> _createOrUpdateChannel('));
      expect(host, contains('_showChannelCreationDialog('));
      expect(host, contains('Future<void> _handleDeleteChannel('));
    });

    test('watch flows stay on the host (M1-3)', () {
      expect(host, contains('_watchChannel('));
      expect(host, contains('Future<Map<String, dynamic>?> _switchToChannel('));
    });
  });
}
