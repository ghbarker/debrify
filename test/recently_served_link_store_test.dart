import 'package:debrify/services/torrent_playback/recently_served_link_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The failover chain's demotion memory: record on serve, clear on decoder
/// acceptance, window-scoped, bounded, per title/episode.
void main() {
  late DateTime now;
  late RecentlyServedLinkStore store;
  const window = Duration(minutes: 10);

  setUp(() {
    now = DateTime(2026, 9, 7, 12);
    store = RecentlyServedLinkStore(maxEntries: 3, clock: () => now);
  });

  test('identityFor prefers the IMDb id and scopes by episode', () {
    expect(
      RecentlyServedLinkStore.identityFor(imdbId: 'tt1', title: 'X'),
      'tt1',
    );
    expect(
      RecentlyServedLinkStore.identityFor(title: ' Some Show '),
      'some show',
    );
    expect(
      RecentlyServedLinkStore.identityFor(imdbId: 'tt1', season: 1, episode: 2),
      'tt1|s1e2',
    );
    expect(
      RecentlyServedLinkStore.identityFor(imdbId: 'tt1', season: 1),
      'tt1|s1e-',
    );
    expect(
      RecentlyServedLinkStore.identityFor(imdbId: 'tt1', season: 1, episode: 2),
      isNot(
        RecentlyServedLinkStore.identityFor(
          imdbId: 'tt1',
          season: 1,
          episode: 3,
        ),
      ),
    );
  });

  test('a served link is demoted inside the window, not after it', () {
    store.record('tt1', 'a');
    expect(store.wasServedWithin('tt1', 'a', window), isTrue);
    now = now.add(const Duration(minutes: 10));
    expect(
      store.wasServedWithin('tt1', 'a', window),
      isTrue,
      reason: 'inclusive',
    );
    now = now.add(const Duration(seconds: 1));
    expect(store.wasServedWithin('tt1', 'a', window), isFalse);
  });

  test('a link the decoder accepted is never demoted', () {
    store.record('tt1', 'a');
    store.record('tt1', 'b');
    store.markPlayed('tt1', 'b');
    final view = store.viewFor('tt1', window);
    expect(view.isDemoted('a'), isTrue);
    expect(view.isDemoted('b'), isFalse);
    expect(store.length, 1);
  });

  test('identities are isolated (another title, another episode)', () {
    store.record('tt1|s1e1', 'a');
    expect(store.viewFor('tt1|s1e1', window).isDemoted('a'), isTrue);
    expect(store.viewFor('tt1|s1e2', window).isDemoted('a'), isFalse);
    expect(store.viewFor('tt2', window).isDemoted('a'), isFalse);
  });

  test('a zero window turns demotion off without touching records', () {
    store.record('tt1', 'a');
    expect(store.wasServedWithin('tt1', 'a', Duration.zero), isFalse);
    expect(store.viewFor('tt1', Duration.zero).isDemoted('a'), isFalse);
    expect(store.length, 1);
  });

  test('re-recording refreshes the timestamp', () {
    store.record('tt1', 'a');
    now = now.add(const Duration(minutes: 9));
    store.record('tt1', 'a');
    now = now.add(const Duration(minutes: 9));
    expect(store.wasServedWithin('tt1', 'a', window), isTrue);
  });

  test('the store is bounded and evicts the oldest record first', () {
    store.record('tt1', 'a');
    store.record('tt1', 'b');
    store.record('tt1', 'c');
    store.record('tt1', 'd'); // evicts a
    expect(store.length, 3);
    expect(store.wasServedWithin('tt1', 'a', window), isFalse);
    expect(store.wasServedWithin('tt1', 'b', window), isTrue);
    // Touching b makes it newest; the next insert evicts c, not b.
    store.record('tt1', 'b');
    store.record('tt1', 'e');
    expect(store.wasServedWithin('tt1', 'c', window), isFalse);
    expect(store.wasServedWithin('tt1', 'b', window), isTrue);
  });

  test('markPlayed of an unknown link and clear are harmless', () {
    store.markPlayed('tt1', 'nope');
    store.record('tt1', 'a');
    store.clear();
    expect(store.length, 0);
    expect(store.wasServedWithin('tt1', 'a', window), isFalse);
  });

  test('the shared instance exists with the default bound', () {
    expect(RecentlyServedLinkStore.instance.maxEntries, 1000);
  });
}
