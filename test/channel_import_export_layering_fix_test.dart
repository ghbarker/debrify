import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv/import_results.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/screens/debrify_tv/dialogs/import_channels_dialog.dart';
import 'package:debrify/screens/debrify_tv/import_export_dialogs.dart';
import 'package:debrify/services/community/magnet_yaml_service.dart';
import 'package:debrify/services/community/community_channel_model.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/debrify_tv/channel_import_export.dart'
    show ChannelImportOrigin, parseYamlCompute;
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Executable M1-fix origin pin. The screen entry point initially exports the
// ORIGINAL service class. No moved file, copied algorithm, or source scan is
// used here. Keep this file unchanged in the move commit.
const _yaml = '''channel_name: News
avoid_nsfw: false
keywords:
  Science:
    torrents: []
''';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

DebrifyTvChannel _channel(String name, {List<String> keywords = const []}) {
  final now = DateTime.utc(2026, 9, 5);
  return DebrifyTvChannel(
    id: 'existing',
    name: name,
    keywords: keywords,
    avoidNsfw: true,
    channelNumber: 1,
    createdAt: now,
    updatedAt: now,
  );
}

class _Picker extends FilePicker {
  FilePickerResult? result;
  final List<String> calls = [];
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls.add('$type/$withData/$withReadStream');
    return result;
  }
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> implements ChannelImportExportHost {
  late final flow = ChannelImportExport(host: this);
  final events = <String>[];
  @override
  bool isBusy = false;
  @override
  String status = '';
  @override
  List<DebrifyTvChannel> channels = [];
  @override
  final Map<String, DebrifyTvChannelCacheEntry> channelCache = {};
  @override
  bool get importExportMounted => mounted;
  @override
  BuildContext get importExportContext => context;
  @override
  bool get isAndroidTv => false;
  bool confirm = false;
  @override
  void applyImportState(VoidCallback fn) {
    setState(fn);
    events.add('state:$isBusy:$status');
  }

  @override
  void showSnack(String message, {Color color = Colors.blueGrey}) =>
      events.add('snack:$message:$color');
  @override
  void showImportProgress(String title) => events.add('open:$title');
  @override
  void updateProgress(Iterable<String> messages, {bool replace = false}) =>
      events.add('progress:$replace:${messages.join('|')}');
  @override
  void closeProgressDialog() => events.add('close');
  @override
  Future<void> reloadImportedChannels() async => events.add('reload');
  @override
  Future<void> createImportedTextChannel(DebrifyTvChannel channel) async {
    channels.add(channel);
    events.add('create:${channel.name}');
  }

  @override
  Future<bool> confirmDeleteAll({required int channelCount}) async {
    events.add('confirm:$channelCount:$isBusy');
    return confirm;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Library'));
}

Future<_HostState> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_HostState>();
  await tester.pumpWidget(
    MaterialApp(
      builder: (_, child) =>
          AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
      home: _Host(key: key),
    ),
  );
  return key.currentState!;
}

// Pump the real widget routes and permit real SQLite/isolate work to finish.
// Bounded so a stranded progress dialog fails instead of hanging the suite.
Future<void> _until(WidgetTester tester, bool Function() ready) async {
  await tester.pump();
  for (var i = 0; i < 600 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: 'Flow did not reach the expected boundary');
}

Future<({Future<T> work})> _start<T>(
  WidgetTester tester,
  Future<T> Function() run,
) async {
  late Future<T> work;
  await tester.runAsync(() async {
    work = run();
  });
  return (work: work);
}

Future<T> _finish<T>(WidgetTester tester, Future<T> work) async {
  var done = false;
  final tracked = work.whenComplete(() => done = true);
  await _until(tester, () => done);
  return tracked;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Picker picker;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async {
    root = await Directory('.dart_tool').absolute.createTemp('m1-origin-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    DownloadService.instance.debugOverrideGeneratedFileDirectory(root);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await DebrifyTvDatabase.instance.debugResetScopeState();
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() async {
    await DebrifyTvDatabase.instance.debugResetScopeState();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    DownloadService.instance.debugOverrideGeneratedFileDirectory(null);
    await root.delete(recursive: true);
  });

  testWidgets('origin mode cancel clears busy; device cancel leaves it set', (
    tester,
  ) async {
    final host = await _mount(tester);
    var pending = host.flow.handleImportChannels();
    await tester.pumpAndSettle();
    expect(host.isBusy, isTrue);
    expect(find.byType(ImportChannelsDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _finish(tester, pending);
    expect(host.isBusy, isFalse);
    pending = host.flow.handleImportChannels();
    await tester.pumpAndSettle();
    await tester.tap(find.text('From storage'));
    await _finish(tester, pending);
    expect(picker.calls, ['FileType.any/true/true']);
    expect(host.isBusy, isTrue); // Preserve the existing picker-cancel quirk.
    await host.flow.handleImportChannels();
    expect(picker.calls, hasLength(1));
  });

  testWidgets('origin device imports stream bytes and clears progress', (
    tester,
  ) async {
    final host = await _mount(tester);
    picker.result = FilePickerResult([
      PlatformFile(
        name: 'News.txt',
        size: 20,
        readStream: Stream.fromIterable([
          utf8.encode('Science, SCIENCE\nSpace'),
        ]),
      ),
    ]);
    final pending = host.flow.handleImportChannels();
    await tester.pumpAndSettle();
    await tester.tap(find.text('From storage'));
    await _finish(tester, pending);
    expect(host.channels.single.keywords, ['Science', 'Space']);
    expect(host.channels.single.name, 'News');
    expect(host.isBusy, isFalse);
    expect(host.status, '');
    expect(host.events.last, 'close');
  });

  testWidgets(
    'origin picked bytes prefer nonempty data over stream and reject absent data',
    (tester) async {
      final flow = (await _mount(tester)).flow;
      expect(
        await flow.readPickedFileBytes(
          PlatformFile(
            name: 'a',
            size: 2,
            bytes: _bytes('ok'),
            readStream: Stream.value([1]),
          ),
        ),
        _bytes('ok'),
      );
      await expectLater(
        flow.readPickedFileBytes(PlatformFile(name: 'a', size: 0)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Unable to access file bytes.',
          ),
        ),
      );
    },
  );

  testWidgets(
    'origin text dispatch pins collision, limits, malformed input and snack order',
    (tester) async {
      final host = await _mount(tester);
      host.channels = [_channel('NEWS')];
      expect(
        await host.flow.importChannelBytes(
          sourceName: 'News.txt',
          bytes: _bytes(' Science,science, Space\nSCIENCE '),
          origin: ChannelImportOrigin.url,
        ),
        isTrue,
      );
      final imported = host.channels.last;
      expect(imported.name, 'News (2)');
      expect(imported.keywords, ['Science', 'Space']);
      expect(imported.avoidNsfw, isTrue);
      expect(imported.channelNumber, 0);
      expect(host.events.first, 'create:News (2)');
      for (final content in [
        '',
        'x' * 121,
        List.generate(501, (i) => 'k$i').join(','),
      ]) {
        expect(
          await host.flow.safeImportChannelBytes(
            sourceName: 'bad.txt',
            bytes: _bytes(content),
            origin: ChannelImportOrigin.device,
          ),
          isFalse,
        );
      }
      expect(host.events.any((e) => e.contains('No keywords found')), isTrue);
      expect(host.events.any((e) => e.contains('Keyword exceeds 120')), isTrue);
      expect(
        host.events.any((e) => e.contains('500 keywords or fewer')),
        isTrue,
      );
      expect(
        await host.flow.safeImportChannelBytes(
          sourceName: 'bad.bin',
          bytes: _bytes('keywords: unknown'),
          origin: ChannelImportOrigin.device,
        ),
        isFalse,
      );
      expect(host.events.last, contains('Unsupported file type.'));
      final corrupt = (await _start(
        tester,
        () => host.flow.safeImportChannelBytes(
          sourceName: 'bad.zip',
          bytes: Uint8List.fromList([0x50, 0x4b]),
          origin: ChannelImportOrigin.device,
        ),
      )).work;
      await _until(
        tester,
        () => find.text('Zip import failed').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Close'));
      expect(await _finish(tester, corrupt), isFalse);
      expect(host.events.last, contains('No YAML files found'));
    },
  );

  for (final kind in ['yaml', 'zip', 'debrify']) {
    testWidgets('origin $kind executes parser, persistence and summary route', (
      tester,
    ) async {
      final host = await _mount(tester);
      final data = kind == 'zip'
          ? Uint8List.fromList(
              ZipEncoder().encode(
                Archive()..addFile(
                  ArchiveFile('News.yaml', _bytes(_yaml).length, _bytes(_yaml)),
                ),
              ),
            )
          : _bytes(
              kind == 'yaml'
                  ? _yaml
                  : MagnetYamlService.encode(
                      yamlContent: _yaml,
                      channelName: 'News',
                    ),
            );
      var done = false;
      final pending = (await _start(
        tester,
        () => host.flow.importChannelBytes(
          sourceName: 'News.$kind',
          bytes: data,
          origin: ChannelImportOrigin.url,
        ),
      )).work.whenComplete(() => done = true);
      await _until(
        tester,
        () => find.text('Zip import complete').evaluate().isNotEmpty || done,
      );
      expect(find.text('Zip import complete'), findsOneWidget);
      expect(host.channels.single.name, 'News');
      expect(
        host.channels.single.keywords,
        isEmpty,
      ); // Rail shell intentionally empty.
      expect(host.channelCache.values.single.normalizedKeywords, ['science']);
      expect(host.events, contains('reload'));
      await tester.tap(find.text('Close'));
      expect(await _finish(tester, pending), isTrue);
      expect(host.events.last, contains('Imported 1 channel: "News"'));
      final rows = await tester.runAsync(
        DebrifyTvRepository.instance.fetchAllChannels,
      );
      expect(rows!.single.name, 'News');
      expect(rows.single.keywords, ['Science']);
    });
  }

  testWidgets(
    'origin persistence keeps collision suffix, maximum and partial failure',
    (tester) async {
      final host = await _mount(tester);
      host.channels = [_channel('News')];
      final parsed = parseYamlCompute({
        'sourceName': 'news.yaml',
        'content': _yaml,
      });
      final oversized = DebrifyTvZipImportedChannel(
        sourceName: 'big.yaml',
        channelName: 'Big',
        avoidNsfw: true,
        displayKeywords: const [],
        normalizedKeywords: List.generate(1001, (i) => 'k$i'),
        keywordStats: const {},
        torrents: const [],
      );
      final result = await _finish(
        tester,
        host.flow.persistImportedZipChannels([oversized, parsed]),
      );
      expect(
        result.failures.single.reason,
        'Channel has 1001 keywords; maximum supported is 1000.',
      );
      expect(result.successes.single.channelName, 'News (2)');
      expect(host.channels.last.keywords, isEmpty);
      final empty = await host.flow.persistImportedZipChannels([]);
      expect(empty.successes, isEmpty);
      expect(empty.failures, isEmpty);
    },
  );

  testWidgets('origin URL and community cancellation release busy', (
    tester,
  ) async {
    final host = await _mount(tester);
    host.isBusy = true;
    var pending = host.flow.handleImportChannelsFromUrl();
    await tester.pumpAndSettle();
    expect(find.text('Paste a channel link'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _finish(tester, pending);
    expect(host.isBusy, isFalse);
    host.isBusy = true;
    pending = host.flow.handleImportChannelsFromCommunity();
    await tester.pump();
    Navigator.of(host.context).pop();
    await _finish(tester, pending);
    expect(host.isBusy, isFalse);
  });

  testWidgets('origin direct invalid link cleanup and summary empty/failure', (
    tester,
  ) async {
    final host = await _mount(tester);
    await host.flow.importDebrifyLinkDirectly('not a link');
    expect(host.isBusy, isFalse);
    expect(host.status, '');
    expect(host.events.last, 'close');
    await expectLater(
      host.flow.importDebrifyBytes('bad', _bytes('bad')),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Not a valid Debrify link.',
        ),
      ),
    );
    await host.flow.showZipImportSummary(
      const DebrifyTvZipImportResult(channels: [], failures: []),
      const ZipImportPersistenceResult(successes: [], failures: []),
    );
    expect(
      host.events.last,
      contains('No channels found in the selected zip.'),
    );
    final pending = host.flow.showZipImportSummary(
      const DebrifyTvZipImportResult(
        channels: [],
        failures: [
          DebrifyTvZipImportFailure(entryName: 'bad.yaml', reason: 'bad YAML'),
        ],
      ),
      const ZipImportPersistenceResult(successes: [], failures: []),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zip import failed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await _finish(tester, pending);
    expect(host.events.last, contains('Zip import failed: bad YAML'));
  });

  testWidgets('origin YAML reads database, share copies link and clears busy', (
    tester,
  ) async {
    final host = await _mount(tester);
    final result = await _finish(
      tester,
      host.flow.persistImportedZipChannels([
        parseYamlCompute({'sourceName': 'news.yaml', 'content': _yaml}),
      ]),
    );
    expect(result.successes, hasLength(1));
    final shell = host.channels.single;
    final channel = DebrifyTvChannel(
      id: shell.id,
      name: shell.name,
      keywords: ['Science', 'Empty'],
      avoidNsfw: false,
      channelNumber: 0,
      createdAt: shell.createdAt,
      updatedAt: shell.updatedAt,
    );
    final yaml = await _finish(tester, host.flow.generateChannelYaml(channel));
    expect(
      yaml,
      'channel_name: "News"\navoid_nsfw: false\n\nkeywords:\n  Science:\n    torrents: []\n  Empty:\n    torrents: []\n',
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final pending = host.flow.handleShareChannelAsMagnet(channel);
    await _until(tester, () => find.text('Copy link').evaluate().isNotEmpty);
    expect(host.isBusy, isTrue);
    await tester.tap(find.text('Copy link'));
    await _finish(tester, pending);
    expect(MagnetYamlService.decode(copied!).yamlContent, yaml);
    expect(host.isBusy, isFalse);
    expect(host.status, '');
  });

  testWidgets(
    'origin export empty and progress success/error close their routes',
    (tester) async {
      final host = await _mount(tester);
      await _finish(tester, host.flow.handleExportChannels());
      expect(
        host.events.any((e) => e.contains('There are no channels to export.')),
        isTrue,
      );
      expect(host.isBusy, isFalse);
      final release = Completer<int>();
      final pending = host.flow.runChannelExportProgress<int>((stage) {
        stage('Pinned stage');
        return release.future;
      });
      await tester.pump();
      expect(find.text('Pinned stage'), findsOneWidget);
      release.complete(42);
      expect(await _finish(tester, pending), 42);
      await tester.pumpAndSettle();
      expect(find.text('Pinned stage'), findsNothing);
      final error = host.flow.runChannelExportProgress<int>(
        (_) async => throw StateError('export failed'),
      );
      final assertion = expectLater(error, throwsStateError);
      await _finish(tester, assertion);
    },
  );

  testWidgets(
    'origin delete empty, cancel then confirmed clears persisted data',
    (tester) async {
      final host = await _mount(tester);
      await host.flow.handleDeleteAllChannels();
      expect(host.events.single, contains('No channels to delete.'));
      await _finish(
        tester,
        host.flow.persistImportedZipChannels([
          parseYamlCompute({'sourceName': 'news.yaml', 'content': _yaml}),
        ]),
      );
      await _finish(tester, host.flow.handleDeleteAllChannels());
      expect(host.channels, hasLength(1));
      expect(host.isBusy, isFalse);
      expect(host.events, contains('confirm:1:true'));
      host.confirm = true;
      await _finish(tester, host.flow.handleDeleteAllChannels());
      expect(host.channels, isEmpty);
      expect(host.channelCache, isEmpty);
      expect(host.isBusy, isFalse);
      expect(
        await tester.runAsync(DebrifyTvRepository.instance.fetchAllChannels),
        isEmpty,
      );
      expect(
        await tester.runAsync(DebrifyTvCacheService.loadAllEntries),
        isEmpty,
      );
    },
  );

  testWidgets('origin URL download reports progress and creates text channel', (
    tester,
  ) async {
    final host = await _mount(tester);
    final requests = <String>[];
    final pending = (await _start(
      tester,
      () => http.runWithClient(
        host.flow.handleImportChannelsFromUrl,
        () => MockClient((request) async {
          requests.add('${request.method} ${request.url}');
          return http.Response('Space, SPACE, Science', 200);
        }),
      ),
    )).work;
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(EditableText),
      'https://example.test/News.txt',
    );
    await tester.tap(find.text('Import'));
    await _finish(tester, pending);
    expect(requests, ['GET https://example.test/News.txt']);
    expect(host.channels.single.keywords, ['Space', 'Science']);
    expect(host.events, contains('progress:true:Downloading… 100%'));
    expect(host.events.last, 'close');
    expect(host.isBusy, isFalse);
  });

  testWidgets(
    'origin community mixed results suppress per-channel summaries and cap errors',
    (tester) async {
      final host = await _mount(tester);
      final link = MagnetYamlService.encode(
        yamlContent: _yaml,
        channelName: 'News',
      );
      final selected = List.generate(
        7,
        (i) => CommunityChannel(
          id: '$i',
          name: 'Channel $i',
          description: '',
          category: '',
          url: 'https://example.test/$i',
          updated: '',
        ),
      );
      final pending = (await _start(
        tester,
        () => http.runWithClient(
          host.flow.handleImportChannelsFromCommunity,
          () => MockClient(
            (request) async => http.Response(
              request.url.path.endsWith('manifest.json')
                  ? '{"channels":[]}'
                  : request.url.path == '/0'
                  ? link
                  : '',
              200,
            ),
          ),
        ),
      )).work;
      await tester.pump();
      Navigator.of(host.context).pop(selected);
      await _finish(tester, pending);
      expect(host.channels, hasLength(1));
      expect(find.text('Zip import complete'), findsNothing);
      expect(host.events.where((e) => e.startsWith('open:')).toList(), [
        'open:Importing community channels...',
      ]);
      final summary = host.events.singleWhere(
        (e) => e.startsWith('progress:true:Import complete!'),
      );
      expect(
        summary,
        contains(
          'Successfully imported 1 channel(s)|Failed to import 6 channel(s)',
        ),
      );
      expect(summary, contains('Channel 5:'));
      expect(summary, isNot(contains('Channel 6:')));
      expect(
        host.events.any(
          (e) => e.contains('Imported 1 channel, 6 failed:${Colors.orange}'),
        ),
        isTrue,
      );
      expect(host.events.last, 'close');
      expect(host.isBusy, isFalse);
    },
  );

  testWidgets('origin export rereads selection and saves a real portable ZIP', (
    tester,
  ) async {
    final host = await _mount(tester);
    await _finish(
      tester,
      host.flow.persistImportedZipChannels([
        parseYamlCompute({'sourceName': 'news.yaml', 'content': _yaml}),
      ]),
    );
    final pending = (await _start(tester, host.flow.handleExportChannels)).work;
    await _until(
      tester,
      () => find.text('Export 1 channel').evaluate().isNotEmpty,
    );
    await tester.runAsync(
      () => DebrifyTvDatabase.instance.runScoped((db) async {
        await db.update('tv_channels', {'name': 'Edited while choosing'});
      }),
    );
    await tester.tap(find.text('Export 1 channel'));
    await _until(
      tester,
      () => find.text('Channel archive saved').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('OK'));
    await _finish(tester, pending);
    final exported = root.listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('.zip'),
    );
    final archive = DebrifyTvZipImporter.parseZip(exported.readAsBytesSync());
    expect(archive.channels.single.channelName, 'Edited while choosing');
    expect(archive.channels.single.normalizedKeywords, ['science']);
    expect(
      host.events.any(
        (e) => e.contains('Exported 1 channel with 0 saved hashes.'),
      ),
      isTrue,
    );
    expect(host.isBusy, isFalse);
    expect(host.status, '');
  });

  testWidgets(
    'origin YAML serializes database torrent metadata with legacy quoting',
    (tester) async {
      final host = await _mount(tester);
      await _finish(
        tester,
        host.flow.persistImportedZipChannels([
          parseYamlCompute({'sourceName': 'news.yaml', 'content': _yaml}),
        ]),
      );
      final channel = host.channels.single.copyWith(
        keywords: ['SCIENCE', 'Empty'],
        avoidNsfw: true,
      );
      final entry = DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channel.id,
        normalizedKeywords: ['science'],
        fetchedAt: 1,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        keywordStats: const {},
        torrents: [
          CachedTorrent(
            rowid: 0,
            infohash: 'hash-one',
            name: 'A "quote"\\line\nnext',
            sizeBytes: 42,
            createdUnix: 3,
            seeders: 4,
            leechers: 5,
            completed: 6,
            scrapedDate: 7,
            sources: ['source"raw'],
            keywords: ['science'],
          ),
        ],
      );
      await tester.runAsync(() => DebrifyTvCacheService.saveEntry(entry));
      host.channelCache.clear(); // Must read persisted data, not host cache.
      final yaml = await _finish(
        tester,
        host.flow.generateChannelYaml(channel),
      );
      expect(
        yaml,
        'channel_name: "News"\navoid_nsfw: true\n\nkeywords:\n'
        '  SCIENCE:\n    torrents:\n      - infohash: hash-one\n'
        '        name: "A \\"quote\\"\\\\line\\nnext"\n'
        '        size_bytes: 42\n        created_unix: 3\n        seeders: 4\n'
        '        leechers: 5\n        completed: 6\n        scraped_date: 7\n'
        '        sources: ["source"raw"]\n  Empty:\n    torrents: []\n',
      );
    },
  );

  testWidgets(
    'origin unmounted guards avoid dialogs and preserve pending busy state',
    (tester) async {
      final host = await _mount(tester);
      host.isBusy = true;
      await tester.pumpWidget(const SizedBox());
      expect(await host.flow.selectImportMode(), isNull);
      expect(await host.flow.promptCommunityChannelsDialog(), isNull);
      await host.flow.handleImportChannelsFromUrl();
      await host.flow.handleExportChannels();
      await host.flow.handleShareChannelAsMagnet(_channel('News'));
      await host.flow.importDebrifyLinkDirectly('invalid');
      await expectLater(
        host.flow.runChannelExportProgress((_) async => 1),
        throwsStateError,
      );
      expect(host.isBusy, isTrue);
      expect(host.events, isEmpty);
    },
  );
}
