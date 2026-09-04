/// Frozen `tv_home_style` string values. Same set as
/// `StorageService.kTvHomeStyles` — do not rename. 'canvas' is the product
/// default; 'classic' is the original hero + scrolling rows.
const Set<String> kTvHomeStageStyleValues = {
  'canvas',
  'classic',
  'atrium',
  'mosaic',
  'promenade',
  'deck',
  'tonight',
  'spotlight',
};

/// Host methods that paint each TV Home stage. Copied from
/// `SearchScreenHost` (`_buildCanvasBoard` and friends). Classic is the
/// `LayoutBuilder` fall-through after the switch, not a `_build*Board`.
const List<String> kTvHomeStageBuilderNames = [
  '_buildCanvasBoard',
  '_buildAtriumBoard',
  '_buildMosaicBoard',
  '_buildPromenadeBoard',
  '_buildDeckBoard',
  '_buildTonightBoard',
  '_buildSpotlightBoard',
];

/// Which TV Home stage layout the board switch builds.
///
/// Copied from `SearchScreenHost` `switch (_homeStyleEffective)` (~16904).
/// Classic (and unknown / removed values such as `'shelf'`) fall through to
/// the hero/rows `LayoutBuilder`. `_buildDiscoverStage` is Discover chrome
/// and is not a case here.
///
/// Quirk: Spotlight with every shelf empty `break`s to classic — favourites
/// are not `StremioMeta`, so a stylish empty Spotlight is worse than classic.
String resolveTvHomeStageLayout({
  required String homeStyleEffective,
  required bool spotlightShelvesAllEmpty,
}) {
  switch (homeStyleEffective) {
    case 'canvas':
      return 'canvas';
    case 'atrium':
      return 'atrium';
    case 'mosaic':
      return 'mosaic';
    case 'promenade':
      return 'promenade';
    case 'deck':
      return 'deck';
    case 'tonight':
      return 'tonight';
    case 'spotlight':
      // The shared guard above lets dispatch through whenever ANY rail has
      // content — including favourites, which Spotlight still does not draw
      // (they are not `StremioMeta`). So test what this board will actually
      // render, not what the screen has: a stylish empty board is worse than
      // classic.
      if (spotlightShelvesAllEmpty) break;
      return 'spotlight';
  }
  return 'classic';
}
