import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../../../utils/media_kit_init.dart';

/// Synchronous terminal construction only; the host owns ordering and lifetime.
abstract class PlayerTerminalBackend {
  const PlayerTerminalBackend();

  @visibleForTesting
  static PlayerTerminalBackend? debugOverride;

  static PlayerTerminalBackend get current =>
      debugOverride ?? const _DefaultPlayerTerminalBackend();

  void ensureInitialized();

  mk.Player createPlayer({required mk.PlayerConfiguration configuration});

  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  });
}

class _DefaultPlayerTerminalBackend extends PlayerTerminalBackend {
  const _DefaultPlayerTerminalBackend();

  @override
  void ensureInitialized() => MediaKitInit.ensureInitialized();

  @override
  mk.Player createPlayer({required mk.PlayerConfiguration configuration}) =>
      mk.Player(configuration: configuration);

  @override
  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) => mkv.VideoController(player, configuration: configuration);
}
