import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/player_guide_style.dart';
import 'package:debrify/screens/video_player/iptv_zap_controller.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lib-call pin of `IptvZapController` **before** the V1-fix move.
///
/// Existing `iptv_zap_controller_pin_test.dart` only greps source.
/// This file imports and calls the unit (gate h).
void main() {
  test('IptvCatchupRequestGate begin strands the previous ticket', () {
    final gate = IptvCatchupRequestGate();
    final first = gate.begin();
    final second = gate.begin();
    expect(gate.isCurrent(first), isFalse);
    expect(gate.isCurrent(second), isTrue);
    expect(gate.cancel(), isTrue);
    expect(gate.isCurrent(second), isFalse);
    expect(gate.complete(second), isFalse);
    expect(gate.cancel(), isFalse);

    final third = gate.begin();
    expect(gate.complete(third), isTrue);
    expect(gate.isCurrent(third), isFalse);
  });

  test('IptvZapController launch list, identity, and info signature', () {
    final live = IptvChannel(
      name: 'BBC One',
      url: 'http://live/1',
      group: 'News',
      contentType: 'live',
      channelNumber: 1,
    );
    final session = _FakeZapSession(channels: [live], index: 0);
    final zap = IptvZapController(session);
    addTearDown(zap.disposeTimers);

    expect(zap.effectiveChannels, [live]);
    expect(zap.currentChannel, live);
    expect(zap.bannerOwnsIdentity, isTrue);
    expect(zap.canZap, isFalse);
    expect(zap.pagingActive, isFalse);
    expect(zap.widget.iptvSourceId, 'src');
    expect(zap.widget.iptvChannels, [live]);

    expect(
      zap.infoPanelSignature(
        debrifyTvOwnsIdentity: false,
        currentChannelName: null,
        launchChannelName: null,
        currentChannelNumber: null,
        showVideoTitle: false,
      ),
      '-',
    );

    zap.prepareBannerData(live);
    expect(zap.channel.value, live);
    expect(
      zap.infoPanelSignature(
        debrifyTvOwnsIdentity: false,
        currentChannelName: null,
        launchChannelName: null,
        currentChannelNumber: null,
        showVideoTitle: false,
      ),
      // peek miss → loading flag `L` until now/next lands.
      'classic|n|g||||L|',
    );
  });
}

class _FakeZapSession implements IptvZapSession {
  _FakeZapSession({required this.channels, this.index = 0});

  final List<IptvChannel> channels;
  int index;

  @override
  bool get isMounted => true;

  @override
  BuildContext get hostContext => throw UnimplementedError();

  @override
  List<IptvChannel>? get launchChannels => channels;

  @override
  int get currentIptvIndex => index;

  @override
  set currentIptvIndex(int value) => index = value;

  @override
  int get iptvSwitchTicket => 1;

  @override
  String? get iptvSourceId => 'src';

  @override
  String? get iptvSourceName => 'My IPTV';

  @override
  List<String>? get iptvCategories => const ['News'];

  @override
  String? get iptvSelectedCategory => 'News';

  @override
  String? get iptvContentType => 'live';

  @override
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  get iptvBrowseProvider => null;

  @override
  bool get controlsVisible => false;

  @override
  bool get showIptvChannelSheet => false;

  @override
  bool get showSourceSheet => false;

  @override
  bool get showChannelGuide => false;

  @override
  PlayerGuideStyle get playerGuideStyle => PlayerGuideStyle.classic;

  @override
  IptvStyleTokens? get playerGuideTokens => null;

  @override
  bool get recordingActiveNow => false;

  @override
  void runSetState(VoidCallback updates) => updates();

  @override
  Future<void> onSwitch(IptvChannel channel, {bool quietRecovery = false}) async {}

  @override
  void openIptvChannelSheet() {}

  @override
  void closeIptvChannelSheet() {}

  @override
  bool get iptvErrorsMuted => false;

  @override
  void noteTuneError(String error) {}

  @override
  bool tryLiveRecoveryOnError() => false;
}
