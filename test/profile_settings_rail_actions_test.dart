import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/profiles_settings_page.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String adminId;
  late String childId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'profile-rail-test-',
    );
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Boss',
      role: UserProfileRole.admin,
    )).id;
    childId = (await registry.createProfile(
      name: 'Kid',
      role: UserProfileRole.child,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('admin with manageProfiles may manage; child may not', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    final actions = ProfileSettingsRailActions(context);
    // Registry IO only completes inside runAsync (same as profiles_hub_test).
    expect(await tester.runAsync(actions.mayManageProfiles), isTrue);

    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: childId, dataGeneration: 1, sessionEpoch: 1),
    );
    expect(await tester.runAsync(actions.mayManageProfiles), isFalse);
  });

  testWidgets('profilesDenied speaks the refusal instead of hiding the row', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    ProfileSettingsRailActions(context).profilesDenied('add');
    await tester.pump();
    expect(find.text('Only an admin can add profiles.'), findsOneWidget);
  });

  testWidgets('addProfile refuses a child without opening the setup flow', (
    tester,
  ) async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: childId, dataGeneration: 1, sessionEpoch: 1),
    );
    var changed = false;
    final context = await pumpContext(tester);
    await tester.runAsync(
      () => ProfileSettingsRailActions(
        context,
        onChanged: () => changed = true,
      ).addProfile(),
    );
    await tester.pump();
    expect(changed, isFalse);
    expect(find.text('Only an admin can add profiles.'), findsOneWidget);
  });

  testWidgets('editActiveProfile refuses a child without opening the editor', (
    tester,
  ) async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: childId, dataGeneration: 1, sessionEpoch: 1),
    );
    var changed = false;
    final context = await pumpContext(tester);
    await tester.runAsync(
      () => ProfileSettingsRailActions(
        context,
        onChanged: () => changed = true,
      ).editActiveProfile(),
    );
    await tester.pump();
    expect(changed, isFalse);
    expect(find.text('Only an admin can edit profiles.'), findsOneWidget);
  });

  test('openHub still pushes ProfilesSettingsPage', () {
    final src = File(
      'lib/screens/settings/profiles_settings_page.dart',
    ).readAsStringSync();
    expect(
      src.contains(
        'await pushSettingsPage(context, const ProfilesSettingsPage());',
      ),
      isTrue,
    );
    expect(
      src.contains(
        "SnackBar(content: Text('Only an admin can \$action profiles.'))",
      ),
      isTrue,
    );
  });
}
