import 'dart:io';

import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/magic_tv_provider.dart';
import 'package:debrify/utils/stremio_tv_debrid_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

Map<CloudProviderId, bool> _all(bool value) => MagicTvProvider.availability(
  realDebrid: value,
  torbox: value,
  pikpak: value,
  premiumize: value,
  allDebrid: value,
);

void main() {
  test('magic TV ids are not playback or stored ids', () {
    expect(CloudProviderId.debrid.magicTvId, 'real_debrid');
    expect(CloudProviderId.debrid.playbackId, 'debrid');
    expect(CloudProviderId.debrid.storedId, 'rd');
    expect(CloudProviderId.fromMagicTvId('real_debrid'), CloudProviderId.debrid);
    expect(CloudProviderId.fromMagicTvId('debrid'), isNull);
    expect(CloudProviderId.fromMagicTvId('rd'), isNull);
    expect(CloudProviderId.fromMagicTvId('realdebrid'), isNull);
    expect(CloudProviderId.fromPlaybackId('real_debrid'), isNull);
    expect(CloudProviderId.fromStoredId('real_debrid'), isNull);
    expect(CloudProviderId.fromMagicTvId('torbox'), CloudProviderId.torbox);
  });

  test('display is not displayName or overlayTitle for RD / TorBox', () {
    expect(MagicTvProvider.display('torbox'), 'Torbox');
    expect(MagicTvProvider.display('real_debrid'), 'Real Debrid');
    expect(MagicTvProvider.display('debrid'), 'Real Debrid');
    expect(MagicTvProvider.display('mystery'), 'Real Debrid');
    expect(CloudProviderId.torbox.displayName, 'TorBox');
    expect(CloudProviderId.debrid.displayName, 'Real-Debrid');
    expect(CloudProviderId.debrid.overlayTitle, 'Real-Debrid');
  });

  test('preferred wins when that provider is available', () {
    expect(
      MagicTvProvider.pickDefault(
        preferred: 'premiumize',
        available: _all(true),
      ),
      'premiumize',
    );
    expect(
      MagicTvProvider.pickDefault(preferred: 'pikpak', available: _all(true)),
      'pikpak',
    );
  });

  test('unavailable preferred walks playbackPrecedence', () {
    expect(
      MagicTvProvider.pickDefault(
        preferred: 'premiumize',
        available: MagicTvProvider.availability(
          realDebrid: true,
          torbox: true,
          pikpak: true,
          premiumize: false,
          allDebrid: true,
        ),
      ),
      'real_debrid',
    );
    expect(
      MagicTvProvider.pickDefault(
        preferred: null,
        available: MagicTvProvider.availability(
          realDebrid: false,
          torbox: false,
          pikpak: true,
          premiumize: true,
          allDebrid: true,
        ),
      ),
      'premiumize',
    );
    expect(
      MagicTvProvider.pickDefault(preferred: null, available: _all(false)),
      'real_debrid',
    );
  });

  test('playback default-provider id is not a Magic TV preferred', () {
    expect(
      MagicTvProvider.pickDefault(
        preferred: 'debrid',
        available: MagicTvProvider.availability(
          realDebrid: false,
          torbox: false,
          pikpak: true,
          premiumize: false,
          allDebrid: false,
        ),
      ),
      'pikpak',
    );
  });

  test('Stremio auto order is not Magic TV fallback', () {
    expect(CloudProviderId.playbackPrecedence, [
      CloudProviderId.debrid,
      CloudProviderId.torbox,
      CloudProviderId.premiumize,
      CloudProviderId.alldebrid,
      CloudProviderId.pikpak,
    ]);
    expect(StremioTvDebridFallback.autoOrder, [
      'realdebrid',
      'torbox',
      'pikpak',
      'premiumize',
      'alldebrid',
    ]);
  });

  test('Magic TV screen does not read Settings default torrent provider', () {
    final source = File('lib/screens/magic_tv_screen.dart').readAsStringSync();
    expect(source.contains('getDefaultTorrentProvider'), isFalse);
    expect(source.contains('MagicTvProvider.pickDefault'), isTrue);
    expect(source.contains('MagicTvProvider.display'), isTrue);
  });
}
