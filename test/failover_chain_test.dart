import 'package:debrify/models/failover_chain_policy.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/torrent_playback/failover_chain.dart';
import 'package:debrify/utils/source_quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference cases for the click-time failover chain (the resolver server's
/// order, reproduced in the app): clicked first, same-provider siblings by
/// nearest resolution (below before above), later providers only, caps,
/// recently-served links last, disabled = legacy linear walk.
Torrent row(
  String name, {
  String? url,
  StreamType type = StreamType.torrent,
  String infohash = '',
  String? label,
  bool realHash = true,
}) => Torrent(
  rowid: 0,
  infohash: infohash.isEmpty && type == StreamType.torrent
      ? name.hashCode.toRadixString(16).padLeft(40, '0')
      : infohash,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'stremio:test',
  streamType: type,
  directUrl: url,
  hasRealInfoHash: realHash,
  streamLabel: label,
);

/// Direct row hosted by [provider] (Torrentio-style URL path).
Torrent direct(String name, String provider, {String? label}) => row(
  name,
  type: StreamType.directUrl,
  url: 'https://addon.example/$provider/${name.replaceAll(' ', '_')}.mkv',
  label: label,
);

class _Served extends RecentlyServedLinks {
  _Served(this.keys);
  final Set<String> keys;
  @override
  bool isDemoted(String linkKey) => keys.contains(linkKey);
}

final enabled = FailoverChainPolicy.defaults.copyWith(enabled: true);

List<String> names(List<Torrent> c, List<int> chain) => [
  for (final i in chain) c[i].name,
];

void main() {
  group('sourceResolutionForName (reference regex)', () {
    test('explicit p-resolutions win, with or without a space', () {
      expect(sourceResolutionForName('Movie.2160p.WEB'), 2160);
      expect(sourceResolutionForName('Movie 1440 p'), 1440);
      expect(sourceResolutionForName('movie.1080P.bluray'), 1080);
      expect(sourceResolutionForName('720p'), 720);
      expect(sourceResolutionForName('576p PAL'), 576);
      expect(sourceResolutionForName('480p'), 480);
    });
    test('4K / UHD are the fallback and must be standalone tokens', () {
      expect(sourceResolutionForName('Movie 4K HDR'), 2160);
      expect(sourceResolutionForName('Movie.UHD.BluRay'), 2160);
      expect(sourceResolutionForName('Movie 1080p DS4K'), 1080);
      expect(sourceResolutionForName('Movie DS4K'), 0);
      expect(sourceResolutionForName('Movie.HDTV'), 0);
      expect(sourceResolutionForName(''), 0);
    });
  });

  group('matchRank', () {
    test('equal, then below by distance, then above by distance', () {
      expect(FailoverChain.matchRank(target: 1080, candidate: 1080), (0, 0));
      expect(FailoverChain.matchRank(target: 1080, candidate: 720), (1, 360));
      expect(FailoverChain.matchRank(target: 1080, candidate: 480), (1, 600));
      expect(FailoverChain.matchRank(target: 1080, candidate: 2160), (2, 1080));
    });
  });

  group('providerOf', () {
    test('torrent rows take the session resolver (any spelling)', () {
      final t = row('x 1080p');
      expect(FailoverChain.providerOf(t, resolverProvider: 'debrid'), 'debrid');
      expect(FailoverChain.providerOf(t, resolverProvider: 'rd'), 'debrid');
      expect(FailoverChain.providerOf(t, resolverProvider: 'TorBox'), 'torbox');
      expect(FailoverChain.providerOf(t), FailoverChain.unknownProvider);
    });
    test('direct rows are inferred from the URL, then the label', () {
      expect(FailoverChain.providerOf(direct('a', 'realdebrid')), 'debrid');
      expect(FailoverChain.providerOf(direct('a', 'torbox')), 'torbox');
      expect(FailoverChain.providerOf(direct('a', 'premiumize')), 'premiumize');
      expect(FailoverChain.providerOf(direct('a', 'alldebrid')), 'alldebrid');
      expect(FailoverChain.providerOf(direct('a', 'pikpak')), 'pikpak');
      expect(
        FailoverChain.providerOf(
          row('a', type: StreamType.directUrl, url: 'https://cdn.example/a'),
        ),
        FailoverChain.directProvider,
      );
      expect(
        FailoverChain.providerOf(
          row(
            'a',
            type: StreamType.directUrl,
            url: 'https://cdn.example/a',
            label: 'Torrentio 4K [RD+]',
          ),
        ),
        'debrid',
      );
      expect(
        FailoverChain.providerOf(
          row(
            'a',
            type: StreamType.directUrl,
            url: 'https://cdn.example/a',
            label: 'Comet TB',
          ),
        ),
        'torbox',
      );
      // "3rd" is not an RD tag.
      expect(
        FailoverChain.providerOf(
          row(
            'a',
            type: StreamType.directUrl,
            url: 'https://cdn.example/a',
            label: '3rd season',
          ),
        ),
        FailoverChain.directProvider,
      );
    });
  });

  group('linkKeyOf', () {
    test('direct rows key by URL, torrents by infohash', () {
      expect(
        FailoverChain.linkKeyOf(direct('a', 'torbox')),
        'https://addon.example/torbox/a.mkv',
      );
      expect(
        FailoverChain.linkKeyOf(row('a', infohash: 'ABC')),
        'infohash:abc',
      );
      expect(
        FailoverChain.linkKeyOf(row('a', infohash: 'abc', realHash: false)),
        isNull,
      );
    });
  });

  group('resolutionOf', () {
    test('falls back to the addon label when the name has no resolution', () {
      expect(FailoverChain.resolutionOf(row('movie.mkv', label: '4K')), 2160);
      expect(FailoverChain.resolutionOf(row('movie 720p', label: '4K')), 720);
    });
  });

  group('build — disabled', () {
    test('returns the legacy linear walk from the clicked row', () {
      final c = [row('a'), row('b'), row('c'), row('d')];
      expect(
        FailoverChain.build(
          candidates: c,
          clickedIndex: 1,
          policy: FailoverChainPolicy.defaults,
        ),
        [1, 2, 3],
      );
      expect(
        FailoverChain.build(
          candidates: c,
          clickedIndex: 0,
          policy: FailoverChainPolicy.defaults,
          recentlyServed: _Served({FailoverChain.linkKeyOf(c[0])!}),
        ),
        [0, 1, 2, 3],
        reason: 'disabled ignores demotion and caps',
      );
    });
    test('empty input yields an empty chain', () {
      expect(
        FailoverChain.build(
          candidates: const [],
          clickedIndex: 0,
          policy: enabled,
        ),
        isEmpty,
      );
    });
  });

  group('build — siblings', () {
    // All torrent rows, one resolver: every row is a same-provider sibling.
    final c = [
      row('a 2160p'),
      row('b 480p'),
      row('c 1080p'), // clicked
      row('d 720p'),
      row('e 1080p'),
      row('f 1440p'),
    ];

    test('clicked first, then equal, nearest below, then nearest above', () {
      final chain = FailoverChain.build(
        candidates: c,
        clickedIndex: 2,
        policy: enabled.copyWith(maxSiblings: 10),
        resolverProvider: 'debrid',
      );
      expect(names(c, chain), [
        'c 1080p',
        'e 1080p', // equal
        'd 720p', // below, distance 360
        'b 480p', // below, distance 600
        'f 1440p', // above, distance 360
        'a 2160p', // above, distance 1080
      ]);
    });

    test('maxSiblings caps the sibling run', () {
      expect(
        names(
          c,
          FailoverChain.build(
            candidates: c,
            clickedIndex: 2,
            policy: enabled.copyWith(maxSiblings: 2),
            resolverProvider: 'debrid',
          ),
        ),
        ['c 1080p', 'e 1080p', 'd 720p'],
      );
      expect(
        FailoverChain.build(
          candidates: c,
          clickedIndex: 2,
          policy: enabled.copyWith(maxSiblings: 0),
          resolverProvider: 'debrid',
        ),
        [2],
      );
    });

    test('exactOnly keeps only equal-resolution siblings', () {
      expect(
        names(
          c,
          FailoverChain.build(
            candidates: c,
            clickedIndex: 2,
            policy: enabled.copyWith(
              resolutionMatch: FailoverResolutionMatch.exactOnly,
              maxSiblings: 10,
            ),
            resolverProvider: 'debrid',
          ),
        ),
        ['c 1080p', 'e 1080p'],
      );
    });

    test('ignore keeps the incoming order inside the provider', () {
      expect(
        names(
          c,
          FailoverChain.build(
            candidates: c,
            clickedIndex: 2,
            policy: enabled.copyWith(
              resolutionMatch: FailoverResolutionMatch.ignore,
              maxSiblings: 10,
            ),
            resolverProvider: 'debrid',
          ),
        ),
        ['c 1080p', 'a 2160p', 'b 480p', 'd 720p', 'e 1080p', 'f 1440p'],
      );
    });

    test('unknown resolution (0) ranks as far below', () {
      final u = [row('x 1080p'), row('y'), row('z 720p')];
      expect(
        names(
          u,
          FailoverChain.build(
            candidates: u,
            clickedIndex: 0,
            policy: enabled,
            resolverProvider: 'debrid',
          ),
        ),
        ['x 1080p', 'z 720p', 'y'],
      );
    });
  });

  group('build — later providers', () {
    // Order: debrid, torbox, premiumize, alldebrid, pikpak. Click a TorBox
    // 1080p direct row: RD rows are EARLIER (excluded), PM/AD/PP are later.
    final c = [
      direct('rd 1080p', 'realdebrid'),
      direct('tb 2160p', 'torbox'),
      direct('tb 1080p', 'torbox'), // clicked
      direct('pm 720p', 'premiumize'),
      direct('pm 1080p', 'premiumize'),
      direct('pm 2160p', 'premiumize'),
      direct('ad 480p', 'alldebrid'),
      direct('pp 1080p', 'pikpak'),
      direct('rd 720p', 'realdebrid'),
    ];

    test('siblings, then each later provider best-match first, caps apply', () {
      final chain = FailoverChain.build(
        candidates: c,
        clickedIndex: 2,
        policy: enabled.copyWith(maxSiblings: 3, maxPerLaterProvider: 2),
      );
      expect(names(c, chain), [
        'tb 1080p',
        'tb 2160p', // sibling
        'pm 1080p', // premiumize: equal first
        'pm 720p', // then nearest below (cap 2 → 2160p dropped)
        'ad 480p',
        'pp 1080p',
      ]);
    });

    test('maxPerLaterProvider: 0 stops at the clicked provider', () {
      expect(
        names(
          c,
          FailoverChain.build(
            candidates: c,
            clickedIndex: 2,
            policy: enabled.copyWith(maxPerLaterProvider: 0),
          ),
        ),
        ['tb 1080p', 'tb 2160p'],
      );
    });

    test('the user-defined provider order decides who is "later"', () {
      final reordered = enabled.copyWith(
        providerOrder: const ['pikpak', 'alldebrid', 'premiumize', 'torbox'],
        maxPerLaterProvider: 1,
      );
      // torbox is now last among listed → only unlisted rows could follow,
      // and RD is listed (appended by normalization) after torbox.
      expect(reordered.providerOrder.last, 'debrid');
      expect(
        names(
          c,
          FailoverChain.build(
            candidates: c,
            clickedIndex: 2,
            policy: reordered,
          ),
        ),
        ['tb 1080p', 'tb 2160p', 'rd 1080p'],
      );
    });

    test('a click on the first provider walks every later one in order', () {
      final chain = FailoverChain.build(
        candidates: c,
        clickedIndex: 0,
        policy: enabled.copyWith(maxPerLaterProvider: 1),
      );
      expect(names(c, chain), [
        'rd 1080p',
        'rd 720p',
        'tb 1080p',
        'pm 1080p',
        'ad 480p',
        'pp 1080p',
      ]);
    });

    test('exactOnly filters later providers too', () {
      expect(
        names(
          c,
          FailoverChain.build(
            candidates: c,
            clickedIndex: 2,
            policy: enabled.copyWith(
              resolutionMatch: FailoverResolutionMatch.exactOnly,
            ),
          ),
        ),
        ['tb 1080p', 'pm 1080p', 'pp 1080p'],
      );
    });
  });

  group('build — mixed transports and unlisted providers', () {
    test('torrent rows share the resolver; plain direct rows come last', () {
      final c = [
        row('t1 1080p'), // clicked, resolver = debrid
        row(
          'cdn 1080p',
          type: StreamType.directUrl,
          url: 'https://cdn.example/x',
        ),
        direct('tb 1080p', 'torbox'),
        row('t2 720p'),
        row('ext', type: StreamType.externalUrl, url: 'https://ext.example'),
      ];
      final chain = FailoverChain.build(
        candidates: c,
        clickedIndex: 0,
        policy: enabled,
        resolverProvider: 'debrid',
      );
      expect(names(c, chain), ['t1 1080p', 't2 720p', 'tb 1080p', 'cdn 1080p']);
    });

    test('an unlisted click has siblings only — nothing is "later"', () {
      final c = [
        row('cdn a 1080p', type: StreamType.directUrl, url: 'https://c/a'),
        direct('tb 1080p', 'torbox'),
        row('cdn b 720p', type: StreamType.directUrl, url: 'https://c/b'),
      ];
      expect(
        names(
          c,
          FailoverChain.build(candidates: c, clickedIndex: 0, policy: enabled),
        ),
        ['cdn a 1080p', 'cdn b 720p'],
      );
    });

    test('rows without acquisition data or URL are skipped', () {
      final c = [
        row('a 1080p'),
        row('no-hash 1080p', realHash: false, infohash: ''),
        row('empty direct', type: StreamType.directUrl, url: ''),
        row('b 1080p'),
      ];
      expect(
        FailoverChain.build(
          candidates: c,
          clickedIndex: 0,
          policy: enabled,
          resolverProvider: 'debrid',
        ),
        [0, 3],
      );
    });

    test('an out-of-range clicked index clamps', () {
      final c = [row('a'), row('b')];
      expect(
        FailoverChain.build(candidates: c, clickedIndex: 9, policy: enabled),
        [1, 0],
      );
    });
  });

  group('build — demotion', () {
    final c = [
      direct('tb 1080p', 'torbox'), // clicked
      direct('tb 720p', 'torbox'),
      direct('tb 2160p', 'torbox'),
      direct('pm 1080p', 'premiumize'),
    ];

    test('recently served links move to the end, order otherwise intact', () {
      final chain = FailoverChain.build(
        candidates: c,
        clickedIndex: 0,
        policy: enabled,
        recentlyServed: _Served({FailoverChain.linkKeyOf(c[1])!}),
      );
      expect(names(c, chain), ['tb 1080p', 'tb 2160p', 'pm 1080p', 'tb 720p']);
    });

    test(
      'the clicked row itself is demoted when it evidently did not play',
      () {
        final chain = FailoverChain.build(
          candidates: c,
          clickedIndex: 0,
          policy: enabled,
          recentlyServed: _Served({
            FailoverChain.linkKeyOf(c[0])!,
            FailoverChain.linkKeyOf(c[1])!,
          }),
        );
        expect(names(c, chain), [
          'tb 2160p',
          'pm 1080p',
          'tb 1080p',
          'tb 720p',
        ]);
      },
    );

    test('demotion is off when the window is zero', () {
      final chain = FailoverChain.build(
        candidates: c,
        clickedIndex: 0,
        policy: enabled.copyWith(demotionWindowMinutes: 0),
        recentlyServed: _Served({FailoverChain.linkKeyOf(c[1])!}),
      );
      expect(names(c, chain), ['tb 1080p', 'tb 720p', 'tb 2160p', 'pm 1080p']);
    });

    test('demotion never re-adds rows the caps removed', () {
      final chain = FailoverChain.build(
        candidates: c,
        clickedIndex: 0,
        policy: enabled.copyWith(maxSiblings: 1),
        recentlyServed: _Served({FailoverChain.linkKeyOf(c[1])!}),
      );
      expect(names(c, chain), ['tb 1080p', 'pm 1080p', 'tb 720p']);
    });
  });
}
