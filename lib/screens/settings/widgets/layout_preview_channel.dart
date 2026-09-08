import 'package:flutter/foundation.dart';

/// One layout the Appearance preview can show: a row and one of its options.
@immutable
class LayoutPreviewTarget {
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

/// How the inline Screen-layouts rows talk to the preview card.
///
/// The rows and the card are SIBLINGS in the category column (the column is
/// built by a pure function that the layouts re-run on every build), so an
/// inherited widget cannot join them and a per-build object would forget the
/// last-touched row every rebuild. One process-wide notifier does: the card
/// listens, the rows write.
///
/// Two slots. [pointed] is what the pointer or the D-pad highlight is on right
/// now — a candidate, shown but not applied. [resting] is the applied option
/// of the row the user touched last, so when nothing is pointed at the stage
/// still shows a layout rather than snapping back to the theme stage. Both
/// null: the card falls back to the theme stage.
class LayoutPreviewChannel extends ChangeNotifier {
  LayoutPreviewChannel();

  static final LayoutPreviewChannel instance = LayoutPreviewChannel();

  LayoutPreviewTarget? _pointed;
  LayoutPreviewTarget? _resting;

  LayoutPreviewTarget? get pointed => _pointed;
  LayoutPreviewTarget? get resting => _resting;

  /// What the stage should draw.
  LayoutPreviewTarget? get shown => _pointed ?? _resting;

  /// A Screen-layouts row currently has the pointer / D-pad highlight — the
  /// signal [AppearancePreviewDock] docks on. The Look strip needs no
  /// equivalent: it lives on the resting card itself, which already scrolls
  /// itself fully into view on focus (see `_reveal` in
  /// `AppearancePreviewCard`), so there is nothing for a second, pinned copy
  /// to add there.
  bool get active => _pointed != null;

  /// The pointer / highlight moved onto [target].
  void point(LayoutPreviewTarget target) {
    if (_pointed == target) return;
    _pointed = target;
    notifyListeners();
  }

  /// The pointer / highlight left [rowId]. A stale unpoint from a row the
  /// user has already moved past must not clear another row's candidate.
  void unpoint(String rowId) {
    if (_pointed == null || _pointed!.rowId != rowId) return;
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
    if (p != null &&
        p.rowId == applied.rowId &&
        p.optionId == applied.optionId &&
        !p.applied) {
      _pointed = applied;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Back to the theme stage. Tests, and a fresh settings screen.
  void reset() {
    if (_pointed == null && _resting == null) return;
    _pointed = null;
    _resting = null;
    notifyListeners();
  }
}
