import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;
  late String cwRow;
  late String session;

  setUpAll(() {
    source = File('lib/screens/search_screen.dart').readAsStringSync();
    session = File('lib/screens/search/search_content_session.dart')
        .readAsStringSync();
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
    // the row widget (`wrap(...)`); the shared session now binds the host's
    // presentation wrapper, which delegates to the same settings helper.
    final hostUses = RegExp(
      r'builder: \(_\) => _withHomeExpandedCardSettings\(',
    ).allMatches(source);
    final cwUses = RegExp(
      r'builder: \(_\) => wrap\(',
    ).allMatches(cwRow);
    expect(hostUses.length + cwUses.length, 5);
    expect(
      source,
      matches(
        r'void initState\(\) \{\s*super\.initState\(\);\s*'
        r'_content\.surface = this;\s*_content\.presentation = this;',
      ),
    );
    expect(
      source,
      matches(
        r'@override\s*Widget wrapSeeAll\(Widget child\) => '
        r'_withHomeExpandedCardSettings\(child\);',
      ),
    );
    expect(
      session,
      matches(
        r'cwFlows = ContinueWatchingFlows\(\s*'
        r'controller: cw,\s*contextOf: \(\) => context,\s*'
        r'wrap: presentation\.wrapSeeAll,',
      ),
    );
  });
}
