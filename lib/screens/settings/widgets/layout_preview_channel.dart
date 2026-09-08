import 'package:flutter/foundation.dart';

import '../../../theme/app_looks.dart';

/// One thing the pinned Appearance preview can show: a Look under the
/// pointer / D-pad highlight on the strip ([AppearanceLookCandidate]), or a
/// Screen-layouts row's option ([LayoutPreviewTarget]). Both flow through
/// [LayoutPreviewChannel]'s `pointed`/`resting` slots — a single source of
/// truth for "what does the header show" instead of a Look candidate held as
/// local State beside a second, parallel layout notifier.
@immutable
sealed class AppearancePreviewCandidate {
  const AppearancePreviewCandidate();
}

/// A Look under the pointer / D-pad highlight on the Appearance strip, or
/// the last one applied.
@immutable
class AppearanceLookCandidate extends AppearancePreviewCandidate {
  final AppLook look;

  /// True when [look] is what the app is actually running — the caption then
  /// says "Applied" rather than "Not applied yet".
  final bool applied;

  const AppearanceLookCandidate(this.look, {required this.applied});

  @override
  bool operator ==(Object other) =>
      other is AppearanceLookCandidate &&
      other.look.id == look.id &&
      other.applied == applied;

  @override
  int get hashCode => Object.hash(look.id, applied);

  @override
  String toString() =>
      'AppearanceLookCandidate(${look.id}${applied ? ' applied' : ''})';
}

/// One layout the Appearance preview can show: a row and one of its options.
@immutable
class LayoutPreviewTarget extends AppearancePreviewCandidate {
  /// The row's [SettingsPageSpec.id] — what the stage dispatches on.
  final String rowId;

  /// The row's title, for the caption eyebrow ("DETAILS PAGE").
  final String rowTitle;
  final String optionId;
  final String optionLabel;

  /// True when this is the option the app actually has, so the caption can
  /// say "Applied" rather than "Not applied yet".
  final bool applied;

  /// Secondary settings the picture honours (the dock's palette and size),
  /// from [SettingsLayoutOptions.variant]. Null for most rows.
  final String? variant;

  const LayoutPreviewTarget({
    required this.rowId,
    required this.rowTitle,
    required this.optionId,
    required this.optionLabel,
    required this.applied,
    this.variant,
  });

  LayoutPreviewTarget asApplied() => LayoutPreviewTarget(
    rowId: rowId,
    rowTitle: rowTitle,
    optionId: optionId,
    optionLabel: optionLabel,
    applied: true,
    variant: variant,
  );

  @override
  bool operator ==(Object other) =>
      other is LayoutPreviewTarget &&
      other.rowId == rowId &&
      other.optionId == optionId &&
      other.applied == applied &&
      other.rowTitle == rowTitle &&
      other.optionLabel == optionLabel &&
      other.variant == variant;

  @override
  int get hashCode => Object.hash(rowId, optionId, applied, variant);

  @override
  String toString() =>
      'LayoutPreviewTarget($rowId/$optionId${applied ? ' applied' : ''})';
}

/// How the Appearance strip and the inline Screen-layouts rows talk to the
/// ONE pinned preview.
///
/// The strip, the rows, and the preview are SIBLINGS in the category column
/// (built by a pure function re-run on every build), so an inherited widget
/// cannot join them and a per-build object would forget the last-touched
/// candidate every rebuild. One process-wide notifier does: the preview
/// listens, the strip and the rows write.
///
/// Two slots. [pointed] is what the pointer or the D-pad highlight is on
/// right now — a candidate, shown but not applied. [resting] is the last
/// thing actually applied (a Look chosen on the strip, or a Screen-layouts
/// option chosen on a row), so when nothing is pointed at the preview still
/// shows something rather than snapping back to a bare default. Both null:
/// the preview falls back to the theme actually running.
class LayoutPreviewChannel extends ChangeNotifier {
  LayoutPreviewChannel();

  static final LayoutPreviewChannel instance = LayoutPreviewChannel();

  AppearancePreviewCandidate? _pointed;
  AppearancePreviewCandidate? _resting;

  AppearancePreviewCandidate? get pointed => _pointed;
  AppearancePreviewCandidate? get resting => _resting;

  /// What the preview should draw.
  AppearancePreviewCandidate? get shown => _pointed ?? _resting;

  /// A Screen-layouts row or the Look strip currently has the pointer / D-pad
  /// highlight.
  bool get active => _pointed != null;

  /// The pointer / highlight moved onto [target].
  void point(LayoutPreviewTarget target) {
    if (_pointed == target) return;
    _pointed = target;
    notifyListeners();
  }

  /// The pointer / highlight left [rowId]. A stale unpoint from a row the
  /// user has already moved past must not clear another row's candidate —
  /// nor a Look candidate the strip owns.
  void unpoint(String rowId) {
    final p = _pointed;
    if (p is! LayoutPreviewTarget || p.rowId != rowId) return;
    _pointed = null;
    notifyListeners();
  }

  /// [target] is the applied option of the row the user is on; it becomes
  /// the fallback picture and, if the same option is currently pointed at,
  /// that candidate is promoted to applied.
  void rest(LayoutPreviewTarget target) {
    final applied = target.asApplied();
    var changed = false;
    if (_resting != applied) {
      _resting = applied;
      changed = true;
    }
    final p = _pointed;
    if (p is LayoutPreviewTarget &&
        p.rowId == applied.rowId &&
        p.optionId == applied.optionId &&
        !p.applied) {
      _pointed = applied;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// The pointer / D-pad highlight moved onto [look] on the strip.
  void pointLook(AppLook look, {required bool applied}) {
    final candidate = AppearanceLookCandidate(look, applied: applied);
    if (_pointed == candidate) return;
    _pointed = candidate;
    notifyListeners();
  }

  /// The pointer / highlight left the strip. A stale unpoint must not clear a
  /// layout row's candidate.
  void unpointLook() {
    if (_pointed is! AppearanceLookCandidate) return;
    _pointed = null;
    notifyListeners();
  }

  /// [look] is the one the user just chose on the strip; it becomes the
  /// fallback picture (replacing any earlier Screen-layouts resting choice —
  /// whichever the user touched last is what "resting" means) and, if it is
  /// currently pointed at as a not-yet-applied candidate, that candidate is
  /// promoted to applied.
  void restLook(AppLook look) {
    final applied = AppearanceLookCandidate(look, applied: true);
    var changed = false;
    if (_resting != applied) {
      _resting = applied;
      changed = true;
    }
    final p = _pointed;
    if (p is AppearanceLookCandidate && p.look.id == look.id && !p.applied) {
      _pointed = applied;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Back to the theme actually running. Tests, and a fresh settings screen.
  void reset() {
    if (_pointed == null && _resting == null) return;
    _pointed = null;
    _resting = null;
    notifyListeners();
  }
}
