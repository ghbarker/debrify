import 'package:flutter/material.dart';

import '../../widgets/cloud/cloud_theme.dart';

/// Deep-link splash shown while a provider host is still entering a torrent
/// folder tree. Copied verbatim from the RD and TorBox `build()` opening
/// branches (they were identical).
class CloudFilesOpeningSplash extends StatelessWidget {
  const CloudFilesOpeningSplash({
    super.key,
    this.title = 'Opening torrent...',
    this.body = 'Loading torrent files...',
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return CloudScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        title: Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(body),
          ],
        ),
      ),
    );
  }
}
