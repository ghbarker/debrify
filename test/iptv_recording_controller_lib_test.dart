import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/playback/iptv_recording_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Lib-call pin of `IptvRecordingController` **before** any V1-fix split.
///
/// Existing `iptv_recording_controller_pin_test.dart` only greps source.
/// This file imports and calls the unit (gate h).
void main() {
  test('new controller starts idle; dispose releases notifiers', () {
    final session = _FakeRecordingSession();
    final rec = IptvRecordingController(session);

    expect(rec.isTeeRecording, isFalse);
    expect(rec.engineFlagOn, isFalse);
    expect(rec.recordingActiveNow, isFalse);
    expect(rec.canRecord, isFalse);
    expect(rec.supported.value, isFalse);
    expect(rec.active.value, isFalse);

    rec.dispose();
  });

  test('canRecord requires support and a live banner identity', () {
    final session = _FakeRecordingSession(ownsIdentity: true);
    final rec = IptvRecordingController(session);
    addTearDown(rec.dispose);
    expect(rec.canRecord, isFalse);
  });
}

class _FakeRecordingSession implements IptvRecordingSession {
  _FakeRecordingSession({this.ownsIdentity = false});

  final bool ownsIdentity;

  @override
  mk.Player get player => throw UnimplementedError();

  @override
  bool get playerCreated => false;

  @override
  bool get isMounted => true;

  @override
  IptvChannel? get currentIptvChannel => null;

  @override
  bool get iptvZapBannerOwnsIdentity => ownsIdentity;

  @override
  String? get currentStreamUrl => null;

  @override
  String? get iptvSourceId => 'src';

  @override
  List<Map<String, dynamic>>? get iptvSources => const [];

  @override
  void runSetState(VoidCallback updates) => updates();

  @override
  void showSnackBar(String message) {}

  @override
  Future<bool> ensureCapacity() async => true;
}
