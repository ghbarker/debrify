import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/series_source_service.dart';
import '../../widgets/sources/source_binding_dialogs.dart';
import '../alldebrid/alldebrid_files_screen.dart';
import '../debrid_downloads_screen.dart';
import '../pikpak/pikpak_files_screen.dart';
import '../premiumize/premiumize_files_screen.dart';
import '../torbox/torbox_downloads_screen.dart';

/// Cloud source routes owned by the search screen. Constructor arguments and
/// save callbacks are preserved from SourceBindingDialogs.showAdd.
class SourceBindingRoutes {
  SourceBindingRoutes._();

  static const cloud = SourceBindingCloudRoutes(
    onRealDebrid: realDebrid,
    onTorbox: torbox,
    onPremiumize: premiumize,
    onAllDebrid: allDebrid,
    onPikPak: pikpak,
  );

  static Future<void> realDebrid(
    NavigatorState navigator,
    StremioMeta item,
    Future<void> Function(SeriesSource) saveSource,
  ) => navigator.push(
    MaterialPageRoute(
      builder: (_) => DebridDownloadsScreen(
        isPushedRoute: true,
        initialSearchQuery: item.name,
        selectSourceMode: true,
        onSourceSelected: saveSource,
      ),
    ),
  );

  static Future<void> torbox(
    NavigatorState navigator,
    StremioMeta item,
    Future<void> Function(SeriesSource) saveSource,
  ) => navigator.push(
    MaterialPageRoute(
      builder: (_) => TorboxDownloadsScreen(
        isPushedRoute: true,
        initialSearchQuery: item.name,
        selectSourceMode: true,
        onSourceSelected: saveSource,
      ),
    ),
  );

  static Future<void> premiumize(
    NavigatorState navigator,
    StremioMeta item,
    Future<void> Function(SeriesSource) saveSource,
  ) => navigator.push(
    MaterialPageRoute(
      builder: (_) => PremiumizeFilesScreen(
        isPushedRoute: true,
        initialSearchQuery: item.name,
        selectSourceMode: true,
        onSourceSelected: saveSource,
      ),
    ),
  );

  static Future<void> allDebrid(
    NavigatorState navigator,
    StremioMeta item,
    Future<void> Function(SeriesSource) saveSource,
  ) => navigator.push(
    MaterialPageRoute(
      builder: (_) => AllDebridFilesScreen(
        isPushedRoute: true,
        initialSearchQuery: item.name,
        selectSourceMode: true,
        onSourceSelected: saveSource,
      ),
    ),
  );

  static Future<void> pikpak(
    NavigatorState navigator,
    StremioMeta item,
    Future<void> Function(SeriesSource) saveSource,
  ) => navigator.push(
    MaterialPageRoute(
      builder: (_) => PikPakFilesScreen(
        isPushedRoute: true,
        selectSourceMode: true,
        onSourceSelected: saveSource,
      ),
    ),
  );
}
