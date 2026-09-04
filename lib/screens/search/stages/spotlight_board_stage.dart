part of '../../search_screen.dart';

/// SPOTLIGHT: full-bleed hero you can page through, shelves on a flat ground.
/// Empty shelves are a host-switch `break` to classic, not a loading stage.
///
/// Host owns `_homeStyleEffective`, rails, and focus. Layout only.
class _SpotlightBoardStage extends StatelessWidget {
  const _SpotlightBoardStage({required this.host});

  final _SearchScreenState host;

  @override
  Widget build(BuildContext context) => host._buildSpotlightBoard();
}

extension on _SearchScreenState {
  Widget _buildSpotlightBoard() {
    // Snapshot row descriptors with the shelf list: async inserts must not
    // make a callback page a different catalog than the shelf it came from.
    final rails = _canvasRails;
    return SpotlightBoard(
      key: _spotlightKey,
      hero: _spotlightHero,
      sections: _spotlightShelves,
      heroNode: _spotlightHeroNode,
      heroAddon: _spotlightHeroSection?.addon,
      dpad: widget.isTelevision,
      showCardTitlesAndRatings: !_hideHomeCardTitlesAndRatings,
      onHeroOpen: _openItem,
      onLoadMoreRow: (row) {
        if (row < 0 || row >= rails.length) return;
        final catalogRow = rails[row].sectionIndex;
        if (catalogRow != null) unawaited(_loadMoreRow(catalogRow));
      },
      onLoadMoreShelves: _loadMoreBoard,
      // The board owns the CADENCE; the resolve and the video stay here.
      //
      // Every other entry into `_scheduleHeroTrailer` is still excluded for
      // this style — init, section loads, focus changes, `_applyHero`, route
      // return, sidebar return — so the board's clock is the single owner and
      // the two cannot start a trailer under different titles.
      // NOT && !_heroTrailerSuppressed: suppression is enforced inside
      // _scheduleHeroTrailer. Folding it in here disarms the board's dwell
      // clock entirely — and the dwell is the only event that can LIFT the
      // suppression when the reel moves to a new title, so one post-playback
      // rebuild would have frozen trailers until the tab was recreated.
      trailersEnabled: _heroTrailerEnabled,
      onDwell: (item) => _scheduleHeroTrailer(item, fromSpotlight: true),
      onTrailerStop: _clearHeroTrailer,
      trailer: _heroTrailerRenderable
          ? _HeroTrailerLayer(
              trailer: _heroTrailer,
              isTelevision: widget.isTelevision,
              heroHeight: 540,
              // Full bleed on every form factor — a letterboxed 16:9 band
              // was tried on the phone and read as a TV set embedded in the
              // artwork (user call). The portrait cover-crop is the design;
              // it gets its sharpness from the 1080p resolve and the
              // medium-filter texture sampling instead.
              fullBleed: true,
              volume: _heroTrailerVolume,
              loading: _heroTrailerLoading,
              onPlayingChanged: _onHeroTrailerPlaying,
              takeover: _heroTrailerTakeover,
            )
          : null,
      // TV only: the glass stage the publish feeds exists behind the TV
      // sidebar rail. Off-TV there is no consumer, and writing the shared
      // notifiers from a phone Home would leave stale art for the next TV
      // session of a hot-restarted debug run.
      onAmbient: widget.isTelevision
          ? (art, tint) {
              if (!mounted) return;
              MainPageBridge.tvAmbientArt.value = art;
              MainPageBridge.tvHeroTint.value = tint;
            }
          : null,
    );
  }
}
