import 'package:flutter/material.dart';

import 'cloud_files_source.dart';

/// Shared cloud-files entry, parameterised by a [CloudFilesSource].
///
/// Real-Debrid, TorBox, Premiumize, AllDebrid and PikPak route through
/// this screen. Selection bars stay on the hosts (shape-manifest floor).
///
/// [host] is the provider-specific State (folder tree, web downloads,
/// transfers, playback). The source supplies destination id, titles, and
/// sections.
class CloudFilesScreen extends StatelessWidget {
  const CloudFilesScreen({super.key, required this.source, required this.host});

  final CloudFilesSource source;
  final Widget host;

  @override
  Widget build(BuildContext context) => host;
}
