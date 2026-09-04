import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
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
      CloudUnlockPlan.choose(both, playerScreen: false).provider,
      CloudProviderId.torbox,
    );
    expect(
      CloudUnlockPlan.choose(both, playerScreen: true).provider,
      CloudProviderId.torbox,
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
    expect(player.provider, CloudProviderId.premiumize);

    final launcher = CloudUnlockPlan.choose(entry, playerScreen: false);
    expect(launcher.incompletePremiumize, isFalse);
    expect(launcher.provider, CloudProviderId.debrid);
  });

  test('empty restrictedLink is RD on player, none on launcher', () {
    const entry = PlaylistEntry(url: '', title: 'a', restrictedLink: '');
    expect(
      CloudUnlockPlan.choose(entry, playerScreen: true).provider,
      CloudProviderId.debrid,
    );
    expect(
      CloudUnlockPlan.choose(entry, playerScreen: false).provider,
      isNull,
    );
  });

  test('playlist realdebrid is not tryParse-upgraded to RD', () {
    const entry = PlaylistEntry(
      url: '',
      title: 'a',
      provider: 'realdebrid',
    );
    expect(
      CloudUnlockPlan.choose(entry, playerScreen: true).provider,
      isNull,
    );
    expect(CloudProviderId.fromPlaybackId('realdebrid'), isNull);
    expect(CloudProviderId.tryParse('realdebrid'), CloudProviderId.debrid);
  });

  test('player wrap brand is Real Debrid / Torbox, not displayName', () {
    expect(CloudProviderId.debrid.playerWrapBrand, 'Real Debrid');
    expect(CloudProviderId.debrid.displayName, 'Real-Debrid');
    expect(CloudProviderId.torbox.playerWrapBrand, 'Torbox');
    expect(CloudProviderId.torbox.displayName, 'TorBox');
  });
}
