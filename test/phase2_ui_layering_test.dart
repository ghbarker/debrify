import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_layering.dart' as layering;

// Architecture guard, not an origin-behavior pin. The four controllers are
// screen-owned UI sessions; this does not claim they are pure services.
void main() {
  test('six Phase2 corrected units have zero import-layering violations', () {
    const units = {
      'lib/screens/video_player/subtitle_track_controller.dart',
      'lib/screens/video_player/iptv_zap_controller.dart',
      'lib/screens/video_player/resume_controller.dart',
      'lib/screens/search/keyword_search_controller.dart',
      'lib/widgets/sources/source_binding_dialogs.dart',
      'lib/widgets/player/identify_title_sheet.dart',
    };
    for (final path in units) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    final violations = layering
        .checkRepo()
        .where((violation) => units.contains(violation.file))
        .map((violation) => violation.toString())
        .toList();
    expect(
      violations,
      isEmpty,
      reason: 'All six named units must be corrected',
    );
  });
}
