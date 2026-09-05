import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/search/keyword_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lib-call pin of `KeywordSearchController` **before** the V1-fix move.
///
/// Existing `keyword_search_pin_test.dart` mostly greps source / re-implements
/// ladders. This file imports and calls the unit (gate h).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Torrent torrent({
    required String hash,
    required String name,
    int seeders = 0,
    String source = 'tb',
    StreamType type = StreamType.torrent,
    String? url,
    bool realHash = true,
  }) => Torrent(
    rowid: 0,
    infohash: hash,
    name: name,
    sizeBytes: 0,
    createdUnix: 0,
    seeders: seeders,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    source: source,
    streamType: type,
    directUrl: url,
    hasRealInfoHash: realHash,
  );

  test('row key, source bucket, sort, and error ladders', () {
    final kw = KeywordSearchController();
    addTearDown(kw.dispose);

    expect(KeywordSearchController.kwRowKey(torrent(hash: 'AbC', name: 'A')), 'h:abc');
    expect(
      KeywordSearchController.kwRowKey(
        torrent(
          hash: '',
          name: 'Direct',
          realHash: false,
          type: StreamType.directUrl,
          url: 'https://x',
        ),
      ),
      'n:Direct|https://x',
    );
    expect(KeywordSearchController.kwSourceOf(torrent(hash: 'a', name: 'A', source: '')), 'unknown');
    expect(kw.naturalAscFor('name'), isTrue);
    expect(kw.naturalAscFor('seeders'), isFalse);

    final zed = torrent(hash: 'aa', name: 'Zed 1080p', seeders: 1);
    final aye = torrent(hash: 'bb', name: 'Aye 720p', seeders: 9, source: 'pm');
    kw.kwSort = 'name';
    kw.kwSortAsc = true;
    expect(
      kw.sortKeyword([zed, aye]).map((t) => t.displayTitle).toList(),
      ['Aye 720p', 'Zed 1080p'],
    );

    expect(
      kw.friendlyKeywordError('Failed host lookup'),
      'Network error. Please check your connection.',
    );
    expect(
      kw.friendlyKeywordError('TimeoutException after 0:00:20'),
      'Search timed out. Please try again.',
    );
  });

  test('computeProviders ticks new sources; recompute filters the tab', () {
    final kw = KeywordSearchController();
    addTearDown(kw.dispose);

    final tb = torrent(hash: 'aa', name: 'Zed', source: 'tb');
    final pm = torrent(hash: 'bb', name: 'Aye', source: 'pm');
    kw.kwAll = [tb, pm];
    kw.computeProviders([tb, pm]);
    expect(kw.kwSelectedTorrent, {'tb', 'pm'});
    expect(kw.kwHasProviderFilter, isTrue);

    kw.kwSourceTab = 'pm';
    kw.recompute();
    expect(kw.kwResults.single.infohash, 'bb');
  });

  test('pending count is a set difference; snapshot skips mid-stream', () {
    final kw = KeywordSearchController();
    addTearDown(kw.dispose);

    final a = torrent(hash: 'a', name: 'A');
    final b = torrent(hash: 'b', name: 'B');
    final c = torrent(hash: 'c', name: 'C');
    kw.kwAll = [a, b];
    kw.kwPending = [a, b, c];
    expect(kw.kwPendingNewCount, 1);

    kw.kwQuery = 'foo';
    kw.kwResults = [a];
    kw.kwSearching = true;
    // Toolbar visibility is query/error/loader — not the searching strip.
    expect(kw.kwToolbarVisible, isTrue);
    kw.kwLoading = true;
    expect(kw.kwToolbarVisible, isFalse);
    kw.kwLoading = false;
    expect(kw.kwToolbarVisible, isTrue);
  });
}
