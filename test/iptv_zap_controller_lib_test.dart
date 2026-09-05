import 'dart:async';

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
    expect(zap.session.iptvSourceId, 'src');
    expect(zap.effectiveChannels, [live]);

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
  test(
    'origin launch facade reads replaced session list and guide payload',
    () {
      final old = IptvChannel(name: 'Old', url: 'http://live/old');
      final live = IptvChannel(
        name: 'New',
        url: 'http://live/new',
        group: ' Sports ',
        contentType: 'live',
      );
      final session = _FakeZapSession(channels: [old]);
      final zap = IptvZapController(session);
      addTearDown(zap.disposeTimers);
      expect(zap.effectiveChannels, same(session.channels));

      final replacement = [live];
      session.channels = replacement;
      session.sourceId = 'new-source';
      session.sourceName = 'New source';
      session.categories = ['Sports', 'News'];
      session.contentType = 'series';
      expect(zap.effectiveChannels, same(replacement));
      expect(zap.currentChannel, same(live));
      zap.anchorGuideCategory(live);
      final context = zap.guideContext!;
      expect(context.sourceId, 'new-source');
      expect(context.sourceName, 'New source');
      expect(context.categories, ['Sports', 'News']);
      expect(context.selectedCategory, 'Sports');
      expect(context.contentType, 'series');
      // Selection comes from the real channel group, not the session's launch
      // selected-category field. No private helper or facade getter is invoked.
    },
  );

  test(
    'origin launch facade retains null source-name and content defaults',
    () {
      final live = IptvChannel(
        name: 'Uncategorized',
        url: 'http://live/default',
        contentType: 'live',
      );
      final session = _FakeZapSession(channels: [live]);
      final zap = IptvZapController(session);
      addTearDown(zap.disposeTimers);
      session.sourceId = null;
      session.sourceName = null;
      session.categories = null;
      session.contentType = null;
      zap.anchorGuideCategory(live);
      final context = zap.guideContext!;
      expect(context.sourceId, isNull);
      expect(context.sourceName, 'IPTV');
      expect(context.categories, isEmpty);
      expect(context.selectedCategory, isNull);
      expect(context.contentType, 'live');
    },
  );

  test(
    'origin guide switch reads current provider and source per call',
    () async {
      final live = IptvChannel(
        name: 'Sports live',
        url: 'http://live/sports',
        group: ' Sports ',
        contentType: 'live',
      );
      final session = _FakeZapSession(channels: [live]);
      var staleCalls = 0;
      session.browseProvider = (_) async {
        staleCalls++;
        return null;
      };
      final zap = IptvZapController(session);
      final release = Completer<Map<String, dynamic>?>();
      final entered = Completer<void>();
      final requests = <Map<String, dynamic>>[];
      final receivers = <String>[];
      session.sourceId = 'source-a';
      session.browseProvider = (request) {
        receivers.add('a');
        requests.add(Map<String, dynamic>.from(request));
        entered.complete();
        return release.future;
      };
      try {
        await zap.switchToGuideChannel([live], 0);
        await entered.future;
        expect(staleCalls, 0);
        expect(receivers, ['a']);
        expect(session.switched, [same(live)]);
        expect(requests.single, {
          'action': 'zapPage',
          'sourceId': 'source-a',
          'contentType': 'live',
          'category': 'Sports',
          'query': '',
          'anchorUrl': 'http://live/sports',
          'anchorName': 'Sports live',
          'offset': 0,
          'limit': 1500,
        });
        // The response is external IO only; the real controller constructs the
        // request and owns guide switching. No page-selection algorithm is copied.
        session.sourceId = 'source-b';
        session.browseProvider = (request) async {
          receivers.add('b');
          requests.add(Map<String, dynamic>.from(request));
          return null;
        };
        release.complete(null);
        await zap.switchToGuideChannel([live], 0);
        expect(receivers, ['a', 'b']);
        expect(requests.last, {...requests.first, 'sourceId': 'source-b'});
        expect(session.switched, [same(live), same(live)]);
        expect(staleCalls, 0);
        expect(zap.currentChannel, same(live));
        expect(zap.guideContext, isNull);
      } finally {
        if (!release.isCompleted) release.complete(null);
        await Future<void>.value();
        zap.disposeTimers();
      }
    },
  );
}

class _FakeZapSession implements IptvZapSession {
  _FakeZapSession({required this.channels, this.index = 0});

  List<IptvChannel> channels;
  int index;
  String? sourceId = 'src';
  String? sourceName = 'My IPTV';
  List<String>? categories = const ['News'];
  String? contentType = 'live';
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? browseProvider;
  final switched = <IptvChannel>[];

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
  String? get iptvSourceId => sourceId;

  @override
  String? get iptvSourceName => sourceName;

  @override
  List<String>? get iptvCategories => categories;

  @override
  String? get iptvSelectedCategory => 'News';

  @override
  String? get iptvContentType => contentType;

  @override
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  get iptvBrowseProvider => browseProvider;

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
  Future<void> onSwitch(
    IptvChannel channel, {
    bool quietRecovery = false,
  }) async {
    switched.add(channel);
  }

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
