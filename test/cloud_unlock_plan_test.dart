import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_unlock_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launcher and player share TorBox-before-PikPak-before-Premiumize-before-RD', () {
    const both = PlaylistEntry(
      url: '',
      title: 'a',
      restrictedLink: 'https://rd/restrict',
      torboxTorrentId: 1,
      torboxFileId: 2,
    );
    expect(
      CloudUnlockPlan.choose(both, playerScreen: false).playbackId,
      'torbox',
    );
    expect(
      CloudUnlockPlan.choose(both, playerScreen: true).playbackId,
      'torbox',
    );
  });

  test('incomplete Premiumize: player flags throw, launcher falls through', () {
    const entry = PlaylistEntry(
      url: '',
      title: 'a',
      provider: 'premiumize',
      premiumizeHash: '',
      restrictedLink: 'https://rd/restrict',
    );
    final player = CloudUnlockPlan.choose(entry, playerScreen: true);
    expect(player.incompletePremiumize, isTrue);
    expect(player.lane, CloudUnlockLane.premiumize);

    final launcher = CloudUnlockPlan.choose(entry, playerScreen: false);
    expect(launcher.incompletePremiumize, isFalse);
    expect(launcher.playbackId, 'debrid');
  });

  test('empty restrictedLink is RD on player, none on launcher', () {
    const entry = PlaylistEntry(url: '', title: 'a', restrictedLink: '');
    expect(
      CloudUnlockPlan.choose(entry, playerScreen: true).playbackId,
      'debrid',
    );
    expect(
      CloudUnlockPlan.choose(entry, playerScreen: false).lane,
      isNull,
    );
  });
}
