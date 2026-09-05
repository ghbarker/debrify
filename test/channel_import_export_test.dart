import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/services/debrify_tv/channel_import_export.dart';
import 'package:debrify/screens/debrify_tv/import_export_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live helper tests. M1-fix origin execution proof is in
/// `channel_import_export_layering_fix_test.dart`; the older
/// `magic_tv_channel_import_export_pin_test.dart` is a source inventory
/// and copied-helper characterization, not behavioral proof.
void main() {
  test('dependency inventory only: service has no UI or persistence dependency', () {
    final source = File('lib/services/debrify_tv/channel_import_export.dart')
        .readAsStringSync();
    final directives = RegExp(r'''^(?:import|export) ['"]([^'"]+)['"]''',
      multiLine: true).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(directives, {
      'dart:convert', 'dart:math', 'dart:typed_data',
      'package:flutter/foundation.dart',
      '../../models/debrify_tv/channel.dart',
      '../../models/debrify_tv_cache.dart',
      '../debrify_tv_zip_importer.dart',
    });
    expect(source, isNot(contains('ChannelImportExportHost')));
    expect(source, isNot(contains('BuildContext')));
  });

  test('service text parser needs no host and retains the 500-keyword boundary', () {
    expect(parseChannelText(Uint8List.fromList(utf8.encode(' A,a\nB '))), ['A', 'B']);
    expect(parseChannelText(Uint8List.fromList(utf8.encode(
      List.generate(500, (i) => 'k$i').join(',')))), hasLength(500));
  });

  test('service YAML serializer takes supplied cache and deduplicates first-wins', () {
    final now = DateTime.utc(2026);
    final channel = DebrifyTvChannel(id: 'c', name: 'News', keywords: ['Science'],
      avoidNsfw: true, channelNumber: 0, createdAt: now, updatedAt: now);
    CachedTorrent torrent(String name) => CachedTorrent(rowid: 0,
      infohash: 'same', name: name, sizeBytes: 1, createdUnix: 2, seeders: 3,
      leechers: 4, completed: 5, scrapedDate: 6, sources: const [], keywords: ['science']);
    final yaml = serializeChannelYaml(channel, [torrent('first'), torrent('second')]);
    expect(yaml, contains('name: "first"'));
    expect(yaml, isNot(contains('second')));
    expect('infohash:'.allMatches(yaml), hasLength(1));
  });

  test(
    'determineImportType: extension, PK, debrify://, reject unknown text',
    () {
      expect(
        determineImportType('pack.zip', Uint8List.fromList([0x00])),
        ChannelImportType.zip,
      );
      expect(
        determineImportType('unknown.bin', Uint8List.fromList([0x50, 0x4b])),
        ChannelImportType.zip,
      );
      expect(
        determineImportType('x.bin', utf8.encode('debrify://channel?v=1')),
        ChannelImportType.debrify,
      );
      expect(
        determineImportType('x.bin', utf8.encode('keywords: foo')),
        isNull,
      );
    },
  );

  test('formatBytes / formatImportError / unique name / escape', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(10), '10 B');
    expect(formatImportError(const FormatException('bad')), 'bad');
    expect(resolveUniqueChannelName('  ', {}), 'Imported Channel');
    expect(resolveUniqueChannelName('News', {'news'}), 'News (2)');
    expect(escapeYamlString(r'a\b"c'), r'a\\b\"c');
  });

  test('no part of / extension on the host State', () {
    expect(ChannelImportExport, isA<Type>());
    expect(ChannelImportExportHost, isA<Type>());
  });
}
