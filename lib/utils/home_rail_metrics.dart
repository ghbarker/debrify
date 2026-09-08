import 'package:flutter/widgets.dart';

/// Poster width of a CLASSIC Home board rail card — the single source for
/// every surface that must look like a classic Home row (the classic board
/// itself, collection folder rails when the TV Home Layout isn't Canvas).
///
/// Canvas — the shipped TV default — sizes its shelf differently; see
/// [canvasRailCardSize] for its formula.
double homeRailPosterWidth(BuildContext context, {required bool isTelevision}) {
  if (!isTelevision) {
    return MediaQuery.sizeOf(context).width >= 900 ? 162.0 : 118.0;
  }
  return (MediaQuery.sizeOf(context).height * 0.17).clamp(92.0, 140.0);
}

/// Card (width, height) for a Canvas Home shelf card — the same formula
/// `CanvasStage.build` uses (`cardH = (boardH * 0.30).clamp(150, 220)`,
/// `cardW = cardH * aspect`), so a surface that must look like the Canvas
/// shelf (collection folder rails, when Canvas is the active TV Home Layout)
/// uses the identical numbers rather than classic's unrelated
/// [homeRailPosterWidth] formula.
///
/// Canvas measures its own stage height as the `LayoutBuilder` constraint of
/// the full-bleed hero Stack, which on a typical TV is effectively the
/// screen height; [context]'s screen height is the closest a differently
/// shaped screen (this one has its own header/chrome) can use as that
/// proxy.
({double width, double height}) canvasRailCardSize(
  BuildContext context, {
  required bool landscapeCards,
}) {
  final cardH = (MediaQuery.sizeOf(context).height * 0.30).clamp(150.0, 220.0);
  final aspect = landscapeCards ? 16 / 9 : 2 / 3;
  return (width: cardH * aspect, height: cardH);
}
