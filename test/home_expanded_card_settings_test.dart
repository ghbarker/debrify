import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;
  late String cwRow;

  setUpAll(() {
    source = File('lib/screens/search_screen.dart').readAsStringSync();
    final row = File('lib/screens/search/continue_watching_row.dart').existsSync()
        ? File('lib/screens/search/continue_watching_row.dart')
        : File('lib/widgets/home/continue_watching_row.dart');
    cwRow = row.existsSync() ? row.readAsStringSync() : '';
  });

  test('every Home poster-browser route applies Discover card settings', () {
    final helperStart = source.indexOf(
      'Widget _withHomeExpandedCardSettings(Widget child)',
    );
    final catalogStart = source.indexOf(
      'void _openCatalogSeeAll(',
      helperStart,
    );
    expect(helperStart, isNonNegative);
    expect(catalogStart, isNonNegative);

    final helper = source.substring(helperStart, catalogStart);
    expect(helper, contains('showTypeTags: DiscoverPrefs.showTypeTags'));
    expect(helper, contains('showRatings: DiscoverPrefs.showRatings'));
    expect(helper, contains('showTitles: DiscoverPrefs.showTitles'));

    // Catalog rows, tracker-list rows, generic Continue Watching rows (also
    // used by Simkl/MDBList), Trakt Continue Watching, and collection folder
    // browsers each push a different screen. All five route builders must
    // opt into the helper. G1'-4 moved the two CW see-all builders onto
    // the row widget (`wrap(...)`); the host still binds
    // `wrap: _withHomeExpandedCardSettings`.
    final hostUses = RegExp(
      r'builder: \(_\) => _withHomeExpandedCardSettings\(',
    ).allMatches(source);
    final cwUses = RegExp(
      r'builder: \(_\) => wrap\(',
    ).allMatches(cwRow);
    expect(hostUses.length + cwUses.length, 5);
    expect(source, contains('wrap: _withHomeExpandedCardSettings'));
  });
}
