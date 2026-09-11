import 'dart:async';

import 'package:flutter/material.dart';
import 'package:synchronized/synchronized.dart';

import '../../services/browsing_cache_preferences.dart';
import '../../services/catalog_disk_cache.dart';
import '../../services/debrify_image_cache.dart';
import 'widgets/browsing_cache_usage.dart';
import 'widgets/settings_widgets.dart';

class BrowsingCachePage extends StatefulWidget {
  const BrowsingCachePage({super.key});

  @override
  State<BrowsingCachePage> createState() => _BrowsingCachePageState();
}

class _BrowsingCachePageState extends State<BrowsingCachePage> {
  // Saves outlive a route: reopening the page must join the same action queue.
  static final _saves = Lock();
  final _nodes = List.generate(5, (_) => FocusNode());
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await BrowsingCachePreferences.initialize();
    if (!mounted) return;
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes.first.requestFocus();
    });
  }

  Future<void> _save(
    BrowsingCacheOptions Function(BrowsingCacheOptions) change,
  ) => _saves.synchronized(() async {
    try {
      // Resolve each action after earlier saves finish so rapid input neither
      // disappears nor overwrites another row with an outdated snapshot.
      await BrowsingCachePreferences.update(
        change(BrowsingCachePreferences.current),
      );
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Please try again.');
    }
  });

  Future<void> _chooseSize(bool artwork) async {
    final options = BrowsingCachePreferences.current;
    final selected = await pushSettingsPage<int>(
      context,
      _CacheSizePage(
        artwork: artwork,
        selected: artwork ? options.artworkSizeMb : options.titleSizeMb,
      ),
    );
    if (!mounted || selected == null) return;
    await _save(
      (current) => artwork
          ? current.copyWith(artworkSizeMb: selected)
          : current.copyWith(titleSizeMb: selected),
    );
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    int index,
    Future<void> Function() action,
  ) => SettingsTile(
    icon: value
        ? Icons.check_box_rounded
        : Icons.check_box_outline_blank_rounded,
    title: title,
    subtitle: subtitle,
    trailing: Text(value ? 'On' : 'Off'),
    focusNode: _nodes[index],
    onTap: action,
  );

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Faster browsing',
    body: !_ready
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
                child: ValueListenableBuilder<BrowsingCacheOptions>(
                  valueListenable: BrowsingCachePreferences.notifier,
                  builder: (context, options, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SettingsPageHeader(
                        icon: Icons.speed_rounded,
                        title: 'Faster browsing',
                        subtitle:
                            'Keep useful titles and artwork on this device. '
                            'These choices are not transferred to your other devices.',
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_error!),
                          ),
                        ),
                      const SizedBox(height: 20),
                      SettingsSection(
                        title: 'Title lists',
                        children: [
                          _toggle(
                            'Remember title lists',
                            'Save add-on lists for your next visit.',
                            options.rememberTitles,
                            0,
                            () => _save(
                              (current) => current.copyWith(
                                rememberTitles: !current.rememberTitles,
                              ),
                            ),
                          ),
                          SettingsTile(
                            icon: Icons.storage_rounded,
                            title: 'Title storage',
                            subtitle: '${options.titleSizeMb} MB',
                            enabled: options.rememberTitles,
                            focusNode: _nodes[1],
                            onTap: () => _chooseSize(false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SettingsSection(
                        title: 'Artwork',
                        children: [
                          _toggle(
                            'Custom artwork cache',
                            'Limit shared artwork and channel logos. Off uses the standard cache.',
                            options.expandedArtwork,
                            2,
                            () => _save(
                              (current) => current.copyWith(
                                expandedArtwork: !current.expandedArtwork,
                              ),
                            ),
                          ),
                          SettingsTile(
                            icon: Icons.photo_library_outlined,
                            title: 'Artwork storage',
                            subtitle: _sizeLabel(options.artworkSizeMb),
                            enabled: options.expandedArtwork,
                            focusNode: _nodes[3],
                            onTap: () => _chooseSize(true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SettingsSection(
                        title: 'Movies',
                        children: [
                          _toggle(
                            'Prepare movie streams',
                            'Look for sources when you open a movie. Playback starts only when you press Play.',
                            options.prefetchMovieStreams,
                            4,
                            () => _save(
                              (current) => current.copyWith(
                                prefetchMovieStreams:
                                    !current.prefetchMovieStreams,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      BrowsingCacheUsage(
                        refreshKey: options,
                        titleBytes: CatalogDiskCache.instance.sizeBytes,
                        artworkBytes: DebrifyImageCache.sizeBytes,
                        clearTitles: CatalogDiskCache.instance.clear,
                        clearArtwork: DebrifyImageCache.clear,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}

String _sizeLabel(int mb) => mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';

class _CacheSizePage extends StatefulWidget {
  const _CacheSizePage({required this.artwork, required this.selected});
  final bool artwork;
  final int selected;
  @override
  State<_CacheSizePage> createState() => _CacheSizePageState();
}

class _CacheSizePageState extends State<_CacheSizePage> {
  late final _sizes = widget.artwork
      ? BrowsingCacheOptions.artworkSizesMb
      : BrowsingCacheOptions.titleSizesMb;
  late final _nodes = [for (final _ in _sizes) FocusNode()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nodes[_sizes.indexOf(widget.selected).clamp(0, _sizes.length - 1)]
            .requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: widget.artwork ? 'Artwork storage' : 'Title storage',
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
          child: SettingsSection(
            title: 'Older cached items are replaced when space is needed.',
            children: [
              for (var i = 0; i < _sizes.length; i++)
                SettingsTile(
                  icon: _sizes[i] == widget.selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  title: _sizeLabel(_sizes[i]),
                  subtitle: '',
                  focusNode: _nodes[i],
                  onTap: () async {
                    Navigator.of(context).pop(_sizes[i]);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
