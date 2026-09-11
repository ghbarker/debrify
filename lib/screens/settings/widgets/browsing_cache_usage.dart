import 'dart:async';

import 'package:flutter/material.dart';

import 'settings_widgets.dart';

/// Reads usage only while Settings is open; cache inventory never delays Home.
class BrowsingCacheUsage extends StatefulWidget {
  const BrowsingCacheUsage({
    super.key,
    required this.titleBytes,
    required this.artworkBytes,
    required this.clearTitles,
    required this.clearArtwork,
  });

  final Future<int> Function() titleBytes;
  final Future<int> Function() artworkBytes;
  final Future<void> Function() clearTitles;
  final Future<void> Function() clearArtwork;

  @override
  State<BrowsingCacheUsage> createState() => _BrowsingCacheUsageState();
}

class _BrowsingCacheUsageState extends State<BrowsingCacheUsage> {
  final _nodes = [FocusNode(), FocusNode()];
  final _bytes = <int?>[null, null];
  final _busy = [false, false];
  final _errors = <String?>[null, null];
  final _revision = [0, 0];

  @override
  void initState() {
    super.initState();
    unawaited(_read(0));
    unawaited(_read(1));
  }

  Future<void> _read(int index) async {
    final revision = ++_revision[index];
    try {
      final bytes = await (index == 0
          ? widget.titleBytes
          : widget.artworkBytes)();
      if (!mounted || revision != _revision[index]) return;
      setState(() {
        _bytes[index] = bytes;
        _errors[index] = null;
      });
    } catch (_) {
      if (!mounted || revision != _revision[index]) return;
      setState(() => _errors[index] = 'Storage usage unavailable');
    }
  }

  Future<void> _clear(int index) async {
    if (_busy[index]) return;
    ++_revision[index];
    setState(() {
      _busy[index] = true;
      _errors[index] = null;
    });
    try {
      await (index == 0 ? widget.clearTitles : widget.clearArtwork)();
      if (!mounted) return;
      await _read(index);
    } catch (_) {
      if (mounted) {
        setState(() => _errors[index] = 'Could not clear. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy[index] = false);
    }
  }

  String _subtitle(int index) {
    if (_busy[index]) return 'Clearing…';
    if (_errors[index] != null) return _errors[index]!;
    final bytes = _bytes[index];
    if (bytes == null) return 'Checking storage…';
    final size = bytes < 1024 * 1024
        ? '${(bytes / 1024).ceil()} KB'
        : bytes < 1024 * 1024 * 1024
        ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    return '$size on this device. Downloads again when needed.';
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Cached storage',
    children: [
      for (var i = 0; i < 2; i++)
        SettingsTile(
          icon: Icons.delete_outline_rounded,
          title: i == 0 ? 'Clear cached title lists' : 'Clear cached artwork',
          subtitle: _subtitle(i),
          focusNode: _nodes[i],
          onTap: () => _clear(i),
        ),
    ],
  );
}
