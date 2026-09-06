import 'package:debrify/models/playlist_entry.dart' as owner;
import 'package:debrify/screens/video_player/models/playlist_entry.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old and neutral imports expose the same canonical declaration', () {
    const oldEntry = legacy.PlaylistEntry(url: 'url', title: 'title');
    const newEntry = owner.PlaylistEntry(url: 'url', title: 'title');

    expect(identical(oldEntry, newEntry), isTrue);
    expect(legacy.PlaylistEntry, owner.PlaylistEntry);
    expect(oldEntry, isA<owner.PlaylistEntry>());
    expect(newEntry, isA<legacy.PlaylistEntry>());

    final owner.PlaylistEntry copiedFromOld = oldEntry.copyWithTitle('old copy');
    final legacy.PlaylistEntry copiedFromNew = newEntry.copyWithTitle('new copy');
    expect(copiedFromOld.title, 'old copy');
    expect(copiedFromNew.title, 'new copy');
  });

  test('typed lists interchange both ways without casts or conversion', () {
    final oldList = <legacy.PlaylistEntry>[
      const legacy.PlaylistEntry(url: 'old', title: 'old'),
    ];
    final List<owner.PlaylistEntry> throughOwner = oldList;
    throughOwner.add(const owner.PlaylistEntry(url: 'new', title: 'new'));
    expect(identical(oldList, throughOwner), isTrue);
    expect(oldList.map((entry) => entry.url), ['old', 'new']);

    final newList = <owner.PlaylistEntry>[
      const owner.PlaylistEntry(url: 'neutral', title: 'neutral'),
    ];
    final List<legacy.PlaylistEntry> throughLegacy = newList;
    throughLegacy.add(const legacy.PlaylistEntry(url: 'legacy', title: 'legacy'));
    expect(identical(newList, throughLegacy), isTrue);
    expect(newList.map((entry) => entry.url), ['neutral', 'legacy']);
  });
}
