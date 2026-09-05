import '../../services/cloud/cloud_provider_id.dart';
import '../../utils/debrify_tv_filters.dart';

/// One owner for channel/quick playback preferences and the shared filter value.
/// Host aliases preserve existing read/write sites; mutation does not notify or persist.
class ChannelPlaybackSettingsState {
  static const int randomStartPercentDefault = 20;

  bool startRandom = true;
  int randomStartPercent = randomStartPercentDefault;
  bool hideSeekbar = true;
  bool showChannelName = true;
  bool showVideoTitle = true;
  bool hideOptions = false;
  bool hideBackButton = false;
  String provider = CloudProviderId.debrid.magicTvId;
  bool quickStartRandom = true;
  int quickRandomStartPercent = randomStartPercentDefault;
  bool quickHideSeekbar = true;
  bool quickShowChannelName = true;
  bool quickShowVideoTitle = true;
  bool quickHideOptions = false;
  bool quickHideBackButton = false;
  bool quickAvoidNsfw = true;
  String quickProvider = CloudProviderId.debrid.magicTvId;
  DebrifyTvFilters tvFilters = const DebrifyTvFilters.empty();
}
