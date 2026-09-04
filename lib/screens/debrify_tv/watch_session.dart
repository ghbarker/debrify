import 'package:flutter/material.dart';

import '../../models/torrent.dart';

/// Snack + progress-dialog host for Debrify TV.
///
/// [WatchSession.updateProgress] owns the line-list quirks. Dialog close
/// and snacks stay on the screen (they need [State.mounted] / [BuildContext]).
/// Later M1 lanes (import/export, watch flows) take this instead of reaching
/// into the Magic TV host State.
abstract class ProgressSink {
  void updateProgress(Iterable<String> messages, {bool replace = false});
  void closeProgressDialog();
  void showSnack(String message, {Color color = Colors.blueGrey});
}

/// Mutable watch / queue / progress state extracted from
/// `lib/screens/magic_tv_screen.dart` (fields ~442–479 and ~568–571).
///
/// Field comments and the progress-update body are copied from origin.
/// The screen keeps queue / isBusy accessors so existing call sites are
/// unchanged (Leaves ≈ 0).
class WatchSession {
  /// Mixed queue: can contain Torrent items or RD-restricted link maps
  final List<dynamic> queue = [];
  bool isBusy = false;
  String status = '';
  List<Torrent>? pikpakCandidatePool;
  String?
  currentWatchingChannelId; // Track currently playing channel for switching

  // Progress UI state
  final ValueNotifier<List<String>> progress = ValueNotifier<List<String>>([]);
  BuildContext? progressSheetContext;
  bool progressOpen = false;

  void dispose() {
    progress.dispose();
  }

  /// Origin progress-update (~691–707).
  void updateProgress(Iterable<String> messages, {bool replace = false}) {
    final sanitized = messages
        .map((message) => message.trim())
        .where((message) => message.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) {
      return;
    }

    if (replace || progress.value.isEmpty) {
      progress.value = sanitized;
      return;
    }

    final copy = List<String>.from(progress.value)..addAll(sanitized);
    progress.value = copy;
  }
}
