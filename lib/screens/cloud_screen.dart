import 'package:debrify/services/storage/provider_credential_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/analytics_service.dart';
import '../services/cloud/cloud_credentials.dart';
import '../services/cloud/cloud_provider_id.dart';
import '../services/cloud/cloud_provider_registry.dart';
import '../services/main_page_bridge.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_scope.dart';

/// Cloud hub tiles. Keys passed to [MainPageBridge.openCloudProvider] are
/// [CloudProviderId.playlistStoredProvider] (`realdebrid`, not playback
/// `debrid`). WebDAV is a frozen sentinel, not a [CloudProviderId].
///
/// Visibility is registry membership plus magnet-surface credentials
/// ([CloudCredentials.configured] / [CloudSurface.magnet]) plus the
/// hidden-from-nav flags. PikPak magnet is enabled-only, matching the
/// old hub `getPikPakEnabled` check — not settings `isAuthenticated`.
class CloudHubDispatch {
  CloudHubDispatch._();

  /// Frozen hub / [MainPageBridge.openCloudProvider] key for WebDAV.
  static const webDavKey = 'webdav';

  /// Old per-provider nav order: RD, TorBox, PikPak, Premiumize, AllDebrid.
  /// PikPak before Premiumize — not [CloudProviderId.playbackPrecedence].
  static const List<CloudProviderId> cloudOrder = [
    CloudProviderId.debrid,
    CloudProviderId.torbox,
    CloudProviderId.pikpak,
    CloudProviderId.premiumize,
    CloudProviderId.alldebrid,
  ];

  static String hubKey(CloudProviderId id) => id.playlistStoredProvider;

  /// Hub title. Not [CloudProviderId.displayName]: RD is `Real Debrid`
  /// (space), TorBox is [CloudProviderId.overlayTitle] `Torbox`.
  static String hubName(CloudProviderId id) {
    return switch (id) {
      CloudProviderId.debrid => 'Real Debrid',
      CloudProviderId.torbox => id.overlayTitle,
      CloudProviderId.pikpak ||
      CloudProviderId.premiumize ||
      CloudProviderId.alldebrid => id.displayName,
    };
  }

  static String hubSubtitle(CloudProviderId id) {
    return switch (id) {
      CloudProviderId.pikpak => 'Cloud storage',
      CloudProviderId.debrid ||
      CloudProviderId.torbox ||
      CloudProviderId.premiumize ||
      CloudProviderId.alldebrid => 'Debrid service',
    };
  }

  static IconData hubIcon(CloudProviderId id) {
    return switch (id) {
      CloudProviderId.debrid => Icons.cloud_download_rounded,
      CloudProviderId.torbox => Icons.flash_on_rounded,
      CloudProviderId.pikpak => Icons.cloud_circle_rounded,
      CloudProviderId.premiumize => Icons.workspace_premium_rounded,
      CloudProviderId.alldebrid => Icons.all_inclusive_rounded,
    };
  }

  /// Hub brand colours. Not [CloudProviderChrome.gradient] (those are
  /// playback purple/green).
  static Color hubColor(CloudProviderId id) {
    return switch (id) {
      CloudProviderId.debrid => const Color(0xFF60A5FA),
      CloudProviderId.torbox => const Color(0xFFFBBF24),
      CloudProviderId.pikpak => const Color(0xFF34D399),
      CloudProviderId.premiumize => const Color(0xFFFB923C),
      CloudProviderId.alldebrid => const Color(0xFFEF4444),
    };
  }

  static bool inRegistry(CloudProviderId id) =>
      CloudProviderRegistry.instance[id] != null;

  /// Magnet-surface credentials. Hidden-from-nav is applied by the caller.
  static Future<bool> magnetConfigured(CloudProviderId id) =>
      CloudCredentials.configured(id, CloudSurface.magnet);
}

/// Consolidated "Cloud" hub. Replaces the six separate provider nav tabs
/// (Real Debrid / Torbox / PikPak / Premiumize / AllDebrid / WebDAV) with a
/// single tab that lists the providers the user has enabled. Tapping one opens
/// that provider's existing screen as a pushed route (via
/// [MainPageBridge.openCloudProvider]), so all the provider logic is reused
/// unchanged and Back returns here.
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key, this.isTelevision = false});

  final bool isTelevision;

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudProviderInfo {
  const _CloudProviderInfo(
    this.key,
    this.name,
    this.subtitle,
    this.icon,
    this.color,
  );

  final String key;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _CloudScreenState extends State<CloudScreen> {
  /// Canonical provider order (mirrors the old per-provider nav order).
  static final List<_CloudProviderInfo> _allProviders = [
    for (final id in CloudHubDispatch.cloudOrder)
      _CloudProviderInfo(
        CloudHubDispatch.hubKey(id),
        CloudHubDispatch.hubName(id),
        CloudHubDispatch.hubSubtitle(id),
        CloudHubDispatch.hubIcon(id),
        CloudHubDispatch.hubColor(id),
      ),
    const _CloudProviderInfo(
      CloudHubDispatch.webDavKey,
      'WebDAV',
      'File server',
      Icons.cloud_sync_rounded,
      Color(0xFF22D3EE),
    ),
  ];

  /// Provider keys currently available (enabled & not hidden). Recomputed on
  /// load and whenever an integration setting changes.
  List<_CloudProviderInfo> _providers = [];
  bool _loading = true;

  /// One focus node per visible tile (Android TV DPAD navigation).
  final List<FocusNode> _nodes = [];

  /// The sidebar requested content focus before the async provider load
  /// finished (nodes didn't exist yet) — re-arm once tiles are built.
  bool _tvFocusPending = false;

  static const int _tabIndex = 16;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('cloud');
    MainPageBridge.addIntegrationListener(_onIntegrationsChanged);
    if (widget.isTelevision) {
      MainPageBridge.registerTvContentFocusHandler(_tabIndex, _focusFirstTile);
    }
    _load();
  }

  @override
  void dispose() {
    MainPageBridge.removeIntegrationListener(_onIntegrationsChanged);
    if (widget.isTelevision) {
      MainPageBridge.unregisterTvContentFocusHandler(
        _tabIndex,
        _focusFirstTile,
      );
    }
    _disposeNodes();
    super.dispose();
  }

  void _disposeNodes() {
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
  }

  void _onIntegrationsChanged() => _load();

  Future<void> _load() async {
    final available = await _computeAvailableProviders();
    if (!mounted) return;
    setState(() {
      _providers = available;
      _syncNodes(available.length);
      _loading = false;
    });
    // If the sidebar handed us focus mid-load (before tiles existed), honor it
    // now that the tiles are built.
    if (_tvFocusPending && widget.isTelevision) _focusFirstTile();
  }

  /// Grow/shrink [_nodes] to match the visible tile count.
  void _syncNodes(int count) {
    while (_nodes.length < count) {
      _nodes.add(FocusNode(debugLabel: 'cloud_tile_${_nodes.length}'));
    }
    while (_nodes.length > count) {
      _nodes.removeLast().dispose();
    }
  }

  /// Which providers are enabled & not hidden — mirrors main.dart's
  /// `_computeVisibleNavIndices` per-provider conditions exactly.
  Future<List<_CloudProviderInfo>> _computeAvailableProviders() async {
    final hidden = <CloudProviderId, bool>{
      CloudProviderId.debrid: await ProviderCredentialPrefs.getRealDebridHiddenFromNav(),
      CloudProviderId.torbox: await ProviderCredentialPrefs.getTorboxHiddenFromNav(),
      CloudProviderId.pikpak: await ProviderCredentialPrefs.getPikPakHiddenFromNav(),
      CloudProviderId.premiumize:
          await ProviderCredentialPrefs.getPremiumizeHiddenFromNav(),
      CloudProviderId.alldebrid:
          await ProviderCredentialPrefs.getAllDebridHiddenFromNav(),
    };

    final keys = <String>{};
    for (final id in CloudHubDispatch.cloudOrder) {
      if (!CloudHubDispatch.inRegistry(id)) continue;
      if (hidden[id] == true) continue;
      if (!await CloudHubDispatch.magnetConfigured(id)) continue;
      keys.add(CloudHubDispatch.hubKey(id));
    }

    final webDavEnabled = await ProviderCredentialPrefs.getWebDavEnabled();
    final webDavServers = await ProviderCredentialPrefs.getWebDavServers(
      forSettings: false,
    );
    final wdHidden = await ProviderCredentialPrefs.getWebDavHiddenFromNav();
    if (webDavEnabled && webDavServers.isNotEmpty && !wdHidden) {
      keys.add(CloudHubDispatch.webDavKey);
    }

    return [
      for (final p in _allProviders)
        if (keys.contains(p.key)) p,
    ];
  }

  void _focusFirstTile() {
    if (!mounted) return;
    if (_nodes.isEmpty) {
      // Tiles not built yet (still loading) — re-arm; _load() retries when ready.
      _tvFocusPending = true;
      return;
    }
    _tvFocusPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nodes.isNotEmpty) _nodes.first.requestFocus();
    });
  }

  void _openProvider(String key) => MainPageBridge.openCloudProvider?.call(key);

  KeyEventResult _onTileKey(FocusNode node, KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _nodes[index - 1].requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index < _nodes.length - 1) {
        _nodes[index + 1].requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      // Left edge → hand focus back to the TV sidebar. Off-TV there's no
      // sidebar to focus, so let the event fall through (don't swallow it).
      final focusSidebar = MainPageBridge.focusTvSidebar;
      if (focusSidebar == null) return KeyEventResult.ignored;
      focusSidebar();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _openProvider(_providers[index].key);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: app.cloud.bg,
      // Same soft purple bloom over deep indigo the Search tab uses.
      body: Container(
        decoration: BoxDecoration(gradient: app.cloud.hubWash),
        child: SafeArea(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: app.cloud.accent),
                )
              : _providers.isEmpty
              ? _emptyState(app)
              : _providerList(app),
        ),
      ),
    );
  }

  Widget _emptyState(AppTheme app) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    app.fade(app.cloud.accent, 0.22),
                    app.fade(app.cloud.accent, 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: app.fade(app.cloud.accent, 0.35)),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: app.cloud.accent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No cloud providers connected',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect Real Debrid, Torbox, Premiumize, AllDebrid, PikPak, or '
              'WebDAV in Settings to manage your cloud files here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: app.fade(app.core.tx, 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerList(AppTheme app) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: Text(
                'Cloud',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
              child: Text(
                'Choose a provider to manage its files',
                style: TextStyle(
                  fontSize: 14.5,
                  color: app.fade(app.core.tx, 0.5),
                ),
              ),
            ),
            for (var i = 0; i < _providers.length; i++) ...[
              _providerTile(_providers[i], i, app),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _providerTile(_CloudProviderInfo p, int index, AppTheme app) {
    return Focus(
      focusNode: index < _nodes.length ? _nodes[index] : null,
      onKeyEvent: (node, event) => _onTileKey(node, event, index),
      // Rebuild the tile when its focus state changes so the highlight tracks
      // DPAD focus (Focus.of(context).hasFocus alone doesn't trigger a rebuild).
      onFocusChange: (_) {
        if (mounted) setState(() {});
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              // The parent Focus owns keyboard/DPAD focus; keep InkWell out of
              // focus traversal so it doesn't create a competing focus node.
              canRequestFocus: false,
              borderRadius: app.shape.br(18),
              hoverColor: app.fade(app.core.tx, 0.03),
              onTap: () => _openProvider(p.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: focused
                        ? [
                            app.fade(app.cloud.accent, 0.22),
                            app.fade(app.cloud.accent, 0.07),
                          ]
                        : [
                            app.fade(app.core.tx, 0.055),
                            app.fade(app.core.tx, 0.02),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: app.shape.br(18),
                  border: Border.all(
                    color: focused
                        ? app.cloud.accent
                        : app.fade(app.core.tx, 0.08),
                    width: focused ? 1.6 : 1,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: app.fade(app.cloud.accent, 0.30),
                            blurRadius: 22,
                            spreadRadius: -6,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    // Soft gradient icon tile in the provider's brand colour.
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.color.withValues(alpha: 0.30),
                            p.color.withValues(alpha: 0.12),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: app.shape.br(14),
                        border: Border.all(
                          color: p.color.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(
                        p.icon,
                        color: app.fade(app.core.tx, 0.92),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: app.fade(app.core.tx, 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: app.fade(app.core.tx, focused ? 0.7 : 0.32),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
