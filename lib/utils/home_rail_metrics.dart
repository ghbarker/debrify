import 'package:flutter/widgets.dart';

/// Poster width of a Home board rail card — the single source for every
/// surface that must look like a Home row (the board itself, collection
/// folder rails).
double homeRailPosterWidth(BuildContext context, {required bool isTelevision}) {
  if (!isTelevision) {
    return MediaQuery.sizeOf(context).width >= 900 ? 162.0 : 118.0;
  }
  return (MediaQuery.sizeOf(context).height * 0.17).clamp(92.0, 140.0);
}

/// Classic Home title cards: landscape uses 1.6 poster widths at 16:9.
Size classicRailCardSize(
  BuildContext context, {
  required bool isTelevision,
  required bool landscapeCards,
}) {
  final poster = homeRailPosterWidth(context, isTelevision: isTelevision);
  final width = landscapeCards ? poster * 1.6 : poster;
  return Size(width, width / (landscapeCards ? 16 / 9 : 2 / 3));
}
