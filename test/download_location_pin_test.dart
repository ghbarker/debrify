import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G2 characterisation of the settings download-location block **before**
/// it moves to `lib/screens/settings/download_location_controller.dart`.
///
/// Does not import that file (it does not exist on the parent of the move).
/// After the move this suite still matches the same members (optional
/// leading underscore) by also reading the new file when present — same
/// pattern as `magic_tv_watch_session_fields_pin_test.dart`.
///
/// Quirks pinned here (keep, do not "fix"):
/// * Android uses SAF (`getDownloadTree*`); Windows/Linux use a plain path
///   (`getDownloadDirPath`). macOS is excluded (sandbox / bookmarks).
/// * Default label is `Downloads/Debrify (default)` on SAF or Windows;
///   Linux is `App folder (default)`.
/// * Chosen-folder subtitle is `Custom: $name`; null name uses the default
///   label (not an empty string).
/// * Reset snack strips ` (default)` from that label. Choose snacks quote
///   the SAF display name or the desktop path.
String _host() => File(
  'lib/screens/settings_screen.dart',
).readAsStringSync().replaceAll('\r\n', '\n');

/// Host plus the extracted controller so this suite stays green after the
/// verbatim move.
String _sources() {
  final buf = StringBuffer(_host());
  final moved = File(
    'lib/screens/settings/download_location_controller.dart',
  );
  if (moved.existsSync()) {
    buf.writeln(moved.readAsStringSync().replaceAll('\r\n', '\n'));
  }
  return buf.toString();
}

/// Replica of origin `_downloadLocationSupported`.
bool _supported({
  required bool isWeb,
  required bool isAndroid,
  required bool isWindows,
  required bool isLinux,
}) =>
    !isWeb && (isAndroid || isWindows || isLinux);

/// Replica of origin `_downloadLocationUsesSaf`.
bool _usesSaf({required bool isWeb, required bool isAndroid}) =>
    !isWeb && isAndroid;

/// Replica of origin `_defaultDownloadLocationLabel`.
String _defaultLabel({required bool usesSaf, required bool isWindows}) {
  if (usesSaf || isWindows) {
    return 'Downloads/Debrify (default)';
  }
  return 'App folder (default)';
}

/// Replica of origin `_loadDownloadLocation` subtitle assignment.
String _subtitle({required String? name, required String defaultLabel}) =>
    name == null ? defaultLabel : 'Custom: $name';

/// Replica of the reset-folder snack body.
String _resetSnack(String defaultLabel) =>
    'Downloads will be saved to ${defaultLabel.replaceAll(' (default)', '')}';

/// Replica of the choose-folder snack body (SAF name or desktop path).
String _chooseSnack(String nameOrPath) =>
    'New downloads will be saved to "$nameOrPath"';

void main() {
  late String host;
  late String sources;

  setUpAll(() {
    host = _host();
    sources = _sources();
  });

  test('this pin does not import DownloadLocationController', () {
    final pin = File(
      'test/download_location_pin_test.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r"^import .+download_location_controller\.dart",
        multiLine: true,
      ).hasMatch(pin),
      isFalse,
    );
  });

  group('platform support (SAF vs path; macOS excluded)', () {
    test('supported is Android or Windows or Linux, never web', () {
      expect(
        sources,
        contains(
          '!kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isLinux)',
        ),
      );
      expect(
        _supported(
          isWeb: false,
          isAndroid: true,
          isWindows: false,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        _supported(
          isWeb: false,
          isAndroid: false,
          isWindows: true,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        _supported(
          isWeb: false,
          isAndroid: false,
          isWindows: false,
          isLinux: true,
        ),
        isTrue,
      );
      expect(
        _supported(
          isWeb: false,
          isAndroid: false,
          isWindows: false,
          isLinux: false,
        ),
        isFalse,
        reason: 'macOS / iOS / other are unsupported',
      );
      expect(
        _supported(
          isWeb: true,
          isAndroid: true,
          isWindows: true,
          isLinux: true,
        ),
        isFalse,
      );
    });

    test('SAF is Android-only; desktop uses a plain path', () {
      expect(sources, contains('!kIsWeb && Platform.isAndroid'));
      expect(_usesSaf(isWeb: false, isAndroid: true), isTrue);
      expect(_usesSaf(isWeb: false, isAndroid: false), isFalse);
      expect(_usesSaf(isWeb: true, isAndroid: true), isFalse);
    });

    test('sandbox comment still names macOS as excluded', () {
      expect(sources, contains('macOS is'));
      expect(sources, contains('deliberately excluded'));
      expect(sources, contains('security-scoped bookmarks'));
    });
  });

  group('default label + custom subtitle', () {
    test('SAF and Windows share Downloads/Debrify (default)', () {
      expect(sources, contains("return 'Downloads/Debrify (default)';"));
      expect(_defaultLabel(usesSaf: true, isWindows: false),
          'Downloads/Debrify (default)');
      expect(_defaultLabel(usesSaf: false, isWindows: true),
          'Downloads/Debrify (default)');
    });

    test('Linux default is App folder (default)', () {
      expect(sources, contains("return 'App folder (default)';"));
      expect(sources, contains("getDownloadsDirectory isn't used there"));
      expect(
        _defaultLabel(usesSaf: false, isWindows: false),
        'App folder (default)',
      );
    });

    test('null name uses the default label; else Custom: \$name', () {
      expect(sources, contains("'Custom: \$name'"));
      expect(
        _subtitle(name: null, defaultLabel: 'App folder (default)'),
        'App folder (default)',
      );
      expect(
        _subtitle(
          name: 'SD card',
          defaultLabel: 'Downloads/Debrify (default)',
        ),
        'Custom: SD card',
      );
    });
  });

  group('storage dispatch (SAF tree vs desktop path)', () {
    test('load reads display name on SAF and path on desktop', () {
      expect(sources, contains('DownloadDestinationPrefs.getDownloadTreeDisplayName()'));
      expect(sources, contains('DownloadDestinationPrefs.getDownloadDirPath()'));
      expect(
        sources,
        contains(
          RegExp(
            r'final String\? name = _?downloadLocationUsesSaf\n'
            r'\s+\? await DownloadDestinationPrefs.getDownloadTreeDisplayName\(\)\n'
            r'\s+: await DownloadDestinationPrefs.getDownloadDirPath\(\);',
          ),
        ),
      );
    });

    test('sheet current value is tree URI on SAF, path on desktop', () {
      expect(sources, contains('DownloadDestinationPrefs.getDownloadTreeUri()'));
      expect(
        sources,
        contains(
          RegExp(
            r'final String\? currentTree = _?downloadLocationUsesSaf\n'
            r'\s+\? await DownloadDestinationPrefs.getDownloadTreeUri\(\)\n'
            r'\s+: await DownloadDestinationPrefs.getDownloadDirPath\(\);',
          ),
        ),
      );
    });

    test('choose/reset persist through the matching StorageService API', () {
      expect(sources, contains('DownloadDestinationPrefs.setDownloadTreeUri('));
      expect(sources, contains('DownloadDestinationPrefs.setDownloadDirPath('));
      expect(sources, contains('DownloadDestinationPrefs.clearDownloadTreeUri()'));
      expect(sources, contains('DownloadDestinationPrefs.clearDownloadDirPath()'));
      expect(sources, contains('AndroidNativeDownloader.pickDownloadDirectory()'));
      expect(
        sources,
        contains('AndroidNativeDownloader.releaseDownloadDirectory('),
      );
    });

    test('danger-zone clear stays on the host, after the download-location block', () {
      expect(host, contains('Future<void> _clearDownloadData() async {'));
      expect(
        host.indexOf('Future<void> _clearDownloadData()'),
        greaterThan(host.indexOf('Download location')),
      );
    });
  });

  group('choose / reset snacks', () {
    test('choose quotes the SAF name or the desktop path', () {
      expect(
        sources,
        contains("'New downloads will be saved to \"\$name\"'"),
      );
      expect(
        sources,
        contains("'New downloads will be saved to \"\$dir\"'"),
      );
      expect(_chooseSnack('Movies'), 'New downloads will be saved to "Movies"');
      expect(
        _chooseSnack(r'D:\Debrify'),
        'New downloads will be saved to "D:\\Debrify"',
      );
    });

    test('reset snack strips (default) from the platform label', () {
      expect(
        sources,
        contains(
          RegExp(
            r"Downloads will be saved to \${_?defaultDownloadLocationLabel\.replaceAll\(' \(default\)', ''\)}",
          ),
        ),
      );
      expect(
        _resetSnack('Downloads/Debrify (default)'),
        'Downloads will be saved to Downloads/Debrify',
      );
      expect(
        _resetSnack('App folder (default)'),
        'Downloads will be saved to App folder',
      );
    });

    test('sheet choose-folder copy splits SAF vs another drive', () {
      expect(
        sources,
        contains(
          'Pick any folder, including an SD card. New downloads go there.',
        ),
      );
      expect(
        sources,
        contains(
          'Pick any folder, including another drive. New downloads go there.',
        ),
      );
    });

    test('desktop refuses UNC shares and missing Linux pickers', () {
      expect(sources, contains(r"dir.startsWith(r'\\')"));
      expect(sources, contains(r"Network shares aren\'t supported yet"));
      expect(
        sources,
        contains('a dialog tool like zenity may be missing'),
      );
      expect(sources, contains("That folder isn't writable"));
    });
  });
}
