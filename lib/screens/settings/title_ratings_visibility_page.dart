import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/discover_prefs.dart';
import '../../services/main_page_bridge.dart';
import 'widgets/settings_widgets.dart';

/// Single shared toggle for poster title/rating visibility
/// (`poster_title_ratings_visible`) — replaces the old separate Home "Hide
/// Titles and Ratings" toggle and Discover's "Show titles"/"Show ratings"
/// toggles. Read by Home's own cards, Discover's poster grid, and Home row
/// expansions (which share Discover's card-detail scope).
class TitleRatingsVisibilityPage extends StatefulWidget {
  const TitleRatingsVisibilityPage({super.key});

  @override
  State<TitleRatingsVisibilityPage> createState() =>
      _TitleRatingsVisibilityPageState();
}

class _TitleRatingsVisibilityPageState
    extends State<TitleRatingsVisibilityPage> {
  // Sync-cached by DiscoverPrefs (warmed at app start), so no loading state.
  bool _visible = DiscoverPrefs.titleRatingsVisible;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('title_ratings_visibility_settings');
  }

  Future<void> _setVisible(bool value) async {
    setState(() => _visible = value);
    await DiscoverPrefs.setTitleRatingsVisible(value);
    MainPageBridge.notifyHomeSettingsChanged();
    MainPageBridge.discoverCardSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Title & Ratings Visibility',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.subtitles_rounded,
                  title: 'Title & Ratings Visibility',
                  subtitle: 'Show titles and ratings on posters',
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: '',
                  children: [
                    SettingsToggleTile(
                      icon: Icons.subtitles_rounded,
                      title: 'Show Titles & Ratings',
                      subtitle:
                          'Display title and rating text on posters across '
                          'Home, Home row expansions and Discover',
                      value: _visible,
                      onChanged: _setVisible,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
