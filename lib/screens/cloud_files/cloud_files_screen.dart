import 'package:flutter/material.dart';

import 'cloud_files_source.dart';

/// Shared cloud-files entry, parameterised by a [CloudFilesSource].
///
/// This PR routes **Real-Debrid** and **TorBox** onto this screen.
/// Premiumize, AllDebrid and PikPak stay on their own screens.
///
/// [host] is the provider-specific State (folder tree, web downloads,
/// playback). The source supplies destination id, titles, and sections.
class CloudFilesScreen extends StatelessWidget {
  const CloudFilesScreen({super.key, required this.source, required this.host});

  final CloudFilesSource source;
  final Widget host;

  @override
  Widget build(BuildContext context) => host;
}
