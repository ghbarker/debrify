import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart' as mk;

import '../../models/android_video_renderer_mode.dart';
import '../tvos_decode_remedy.dart';

/// Owns diagnostic debounce, matching polls and report deduplication.
/// Media generations, renderer recovery and native lifetimes remain in the host.
class DecoderDiagnostics {
  DecoderDiagnostics({
    required mk.PlatformPlayer? Function() readPlatform,
    required bool Function() isMounted,
    required int Function() generation,
    required AndroidVideoRendererMode Function() rendererMode,
    required TvosDecodeRemedy? Function() remedy,
    required void Function(String) emit,
  }) : _readPlatform = readPlatform,
       _isMounted = isMounted,
       _generation = generation,
       _rendererMode = rendererMode,
       _remedy = remedy,
       _emit = emit;

  final mk.PlatformPlayer? Function() _readPlatform;
  final bool Function() _isMounted;
  final int Function() _generation;
  final AndroidVideoRendererMode Function() _rendererMode;
  final TvosDecodeRemedy? Function() _remedy;
  final void Function(String) _emit;
  int _token = 0;
  mk.VideoParams? _params;
  Timer? _timer;
  String? _signature;

  void updateParams(mk.VideoParams params) {
    _params = params;
    schedule();
  }

  void invalidateParams() {
    _token++;
    _timer?.cancel();
    _timer = null;
    _params = null;
  }

  // Kept separate from cleanup: host renderer guards change between these steps.
  void invalidateToken() => _token++;

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void clearForMedia() {
    _timer?.cancel();
    _timer = null;
    _params = null;
    _signature = null;
  }

  void schedule() {
    final params = _params;
    if (params == null) return;
    _timer?.cancel();
    final generation = _generation();
    final token = ++_token;
    _timer = Timer(const Duration(milliseconds: 150), () {
      unawaited(
        _report(
          params: params,
          generation: generation,
          token: token,
        ),
      );
    });
  }

  Future<void> _report({
    required mk.VideoParams params,
    required int generation,
    required int token,
  }) async {
    final platform = _readPlatform();
    if (platform is! mk.NativePlayer) {
      _emitOnce(
        generation: generation,
        signature: 'web',
        fields:
            'phase=stable status=unavailable platform=web backend=web '
            'reason=no_native_decoder',
      );
      return;
    }

    var decoder = '';
    var codec = '';
    var output = '';
    var previousDecoder = '';
    var previousOutput = '';
    var stable = false;
    // Audio, read on the DEVICE side (AUDIO_FIDELITY_PLAN.md): what the AO
    // actually writes, not what the decoder produced — the gap between the
    // two is the downgrade being diagnosed.
    var aoName = '';
    var audioChannels = '';
    var previousAo = '';
    var previousAudioChannels = '';
    var audioCodec = '';
    var decodedChannels = '';
    var audioFormat = '';

    try {
      // VideoParams means a decoder has produced metadata, not necessarily
      // that the output surface has finished attaching. Require two matching
      // reads so an early `current-vo=null` is never presented as the verdict.
      // Audio joins the match condition but not the readiness one: a
      // video-only file has no AO to wait for, and empty-matches-empty.
      for (var attempt = 0; attempt < 12; attempt++) {
        if (!_isMounted() ||
            generation != _generation() ||
            token != _token) {
          return;
        }
        decoder = await platform.getProperty('hwdec-current');
        output = await platform.getProperty('current-vo');
        aoName = await platform.getProperty('current-ao');
        audioChannels = await platform.getProperty(
          'audio-out-params/channel-count',
        );
        final outputReady = output.isNotEmpty && output != 'null';
        final decoderReady = decoder.isNotEmpty;
        if (decoderReady &&
            outputReady &&
            decoder == previousDecoder &&
            output == previousOutput &&
            aoName == previousAo &&
            audioChannels == previousAudioChannels) {
          stable = true;
          break;
        }
        previousDecoder = decoder;
        previousOutput = output;
        previousAo = aoName;
        previousAudioChannels = audioChannels;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!_isMounted() ||
          generation != _generation() ||
          token != _token) {
        return;
      }
      codec = await platform.getProperty('video-codec');
      audioCodec = await platform.getProperty('audio-codec-name');
      decodedChannels = await platform.getProperty(
        'audio-params/channel-count',
      );
      audioFormat = await platform.getProperty('audio-out-params/format');
    } catch (_) {
      if (!_isMounted() || generation != _generation()) return;
      _emitOnce(
        generation: generation,
        signature: 'error',
        fields:
            'phase=error status=unavailable '
            'platform=${Platform.operatingSystem} reason=property_query_failed',
      );
      return;
    }

    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    final status = decoder == 'no'
        ? 'software'
        : decoder.isEmpty
        ? 'unavailable'
        : 'hardware';
    final normalizedOutput = output.isEmpty || output == 'null'
        ? 'unknown'
        : output;
    final requestedRenderer = Platform.isAndroid
        ? _rendererMode().storageKey
        : 'platform_default';
    // The remedy journey (tvOS): what the decoder produced originally, what
    // it produces now, and where the ladder settled. In the signature too —
    // a settle re-arms this probe, and dedupe on the old signature would
    // swallow exactly the report that proves the remedy ran.
    final remedy = _remedy();
    final remedyState = switch (remedy?.state) {
      null || TvosRemedyState.none => 'none',
      TvosRemedyState.nv12 => 'nv12',
      TvosRemedyState.software => 'software',
      TvosRemedyState.gaveUp => 'gave_up',
    };
    // confirmed/failed mean the remedy's own settling poll verified the
    // format by DIRECT read — the stream-captured params above can lag
    // behind a settle (no final event is guaranteed after reconfig).
    final remedyOutcome = remedy == null
        ? 'none'
        : remedy.applying
        ? 'pending'
        : switch (remedy.state) {
            TvosRemedyState.none => 'none',
            TvosRemedyState.nv12 || TvosRemedyState.software => 'confirmed',
            TvosRemedyState.gaveUp => 'failed',
          };
    final remedyFields = remedy == null
        ? ''
        : 'pixelformat=${params.pixelformat ?? 'unknown'} '
              'hw_pixelformat=${params.hwPixelformat ?? 'none'} '
              'detected_hw_pixelformat=${remedy.detectedHwPixelformat ?? 'none'} '
              'verified_hw_pixelformat=${remedy.verifiedHwPixelformat ?? 'none'} '
              'gamma=${params.gamma ?? 'unknown'} '
              'primaries=${params.primaries ?? 'unknown'} '
              'remedy=$remedyState remedy_outcome=$remedyOutcome ';
    final signature =
        '$decoder|$normalizedOutput|$codec|${width}x$height|'
        '$remedyState|$remedyOutcome';
    _emitOnce(
      generation: generation,
      signature: signature,
      fields:
          'phase=${stable ? 'stable' : 'partial'} status=$status '
          'platform=${Platform.operatingSystem} backend=libmpv '
          'codec=${codec.isEmpty ? 'unknown' : codec} '
          'decoder=${decoder.isEmpty ? 'unknown' : decoder} '
          'output=$normalizedOutput '
          '$remedyFields'
          'audio_codec=${audioCodec.isEmpty ? 'none' : audioCodec} '
          'decoded_channels=${decodedChannels.isEmpty ? 'none' : decodedChannels} '
          'audio_channels=${audioChannels.isEmpty ? 'none' : audioChannels} '
          'audio_format=${audioFormat.isEmpty ? 'none' : audioFormat} '
          'ao=${aoName.isEmpty ? 'none' : aoName} '
          'requested_renderer=$requestedRenderer '
          'resolution=${width}x$height',
    );
  }

  void _emitOnce({
    required int generation,
    required String signature,
    required String fields,
  }) {
    if (generation != _generation()) return;
    final taggedSignature = '$generation|$signature';
    if (_signature == taggedSignature) return;
    _signature = taggedSignature;
    _emit('generation=$generation $fields');
  }
}
