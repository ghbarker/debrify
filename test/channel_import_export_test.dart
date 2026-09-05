import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/services/debrify_tv/channel_import_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live tests of the moved M1-2 bodies. The origin pin
/// (`magic_tv_channel_import_export_pin_test.dart`) stays import-free
/// and unedited. Quirks match that pin — do not "fix".
void main() {
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
