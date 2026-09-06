import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_collection_inventory.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';

const c = HomeCollection(
  id: 'one',
  title: 'One',
  folders: [HomeCollectionFolder(id: 'f', title: 'Folder')],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferenceBudget.debugReset();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfilePreferenceBudget.debugReset);
  test('invalid sync order identities cannot enter storage', () async {
    final store = HomeCollectionsStore();
    for (final id in ['', 'bad\u0000id']) {
      await expectLater(
        store.importCollections([HomeCollection(id: id, title: 'Bad')]),
        throwsFormatException,
      );
    }
    expect(await store.getCollections(), isEmpty);
  });
  test('explicit save applies order and retains deletion records', () async {
    final store = HomeCollectionsStore();
    const two = HomeCollection(id: 'two', title: 'Two');
    const removed = HomeCollection(id: 'removed', title: 'Removed');
    await store.importCollections([c, two, removed]);
    await store.saveCollections([two, c]);
    expect((await store.getCollections()).map((item) => item.id), [
      'two',
      'one',
    ]);
    final prefs = await SharedPreferences.getInstance();
    final inventory = HomeCollectionInventory.decode(
      prefs.getString(HomeCollectionsStore.prefsKey),
    );
    expect(inventory.records.containsKey('removed'), true);
    expect(inventory.records['removed'], isNull);
  });
  test(
    'legacy preferences upgrade on mutation with explicit deletions',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: jsonEncode([c.toJson()]),
      });
      final store = HomeCollectionsStore();
      expect((await store.getCollections()).single.id, 'one');
      await store.clear();
      final raw = (await SharedPreferences.getInstance()).getString(
        HomeCollectionsStore.prefsKey,
      );
      expect(raw, isNotNull);
      final inventory = HomeCollectionInventory.decode(raw);
      expect(inventory.records.containsKey('one'), true);
      expect(inventory.records['one'], null);
      expect(await HomeCollectionsStore().getCollections(), isEmpty);
    },
  );
  test('reimport can deliberately restore a deleted collection', () async {
    final store = HomeCollectionsStore();
    await store.importCollections([c]);
    await store.remove('one');
    await store.importCollections([c]);
    expect((await store.getCollections()).single.title, 'One');
  });
  test(
    'reimport updates contents without resetting disabled state or order',
    () async {
      final store = HomeCollectionsStore();
      await store.importCollections([
        c,
        const HomeCollection(id: 'two', title: 'Two'),
      ]);
      await store.setEnabled('one', false);
      await store.importCollections([
        const HomeCollection(id: 'one', title: 'Updated'),
      ]);
      final list = await store.getCollections();
      expect(list.map((c) => c.id), ['one', 'two']);
      expect(list.first.title, 'Updated');
      expect(list.first.enabled, false);
    },
  );
  test(
    'backup array exports active records and restores their visibility',
    () async {
      final store = HomeCollectionsStore();
      await store.importCollections([
        c.copyWith(enabled: false),
        const HomeCollection(id: 'two', title: 'Two'),
      ]);
      await store.remove('two');
      final backup = await store.exportJson();
      expect(backup, hasLength(1));
      SharedPreferences.setMockInitialValues({});
      final report = await store.applyBackup(backup);
      expect(report.imported, 1);
      expect(report.failed, 0);
      expect((await store.getCollections()).single.enabled, false);
    },
  );
  test(
    'invalid persisted data cannot be silently overwritten or exported empty',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: 'broken',
      });
      final store = HomeCollectionsStore();
      await expectLater(store.importCollections([c]), throwsFormatException);
      await expectLater(store.exportJson(), throwsFormatException);
      expect(
        (await SharedPreferences.getInstance()).getString(
          HomeCollectionsStore.prefsKey,
        ),
        'broken',
      );
    },
  );
  test(
    'oversized sync identities are refused without changing inventory',
    () async {
      final store = HomeCollectionsStore();
      await store.importCollections([c]);
      await expectLater(
        store.importCollections([
          HomeCollection(id: 'x' * 1024, title: 'Too long'),
        ]),
        throwsFormatException,
      );
      expect((await store.getCollections()).map((c) => c.id), ['one']);
    },
  );
  test('failed layout write surfaces a failure', () async {
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    SharedPreferences.setMockInitialValues({'full': 'x' * (512 * 1024)});
    await expectLater(
      HomeCollectionsStore().setFolderLayout(CollectionFolderLayout.tabs),
      throwsStateError,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        HomeCollectionsStore.folderLayoutKey,
      ),
      null,
    );
  });
  test(
    'signature reflects content edits with identical counts and timestamps',
    () {
      expect(
        HomeCollectionsStore.signatureOf([c]),
        isNot(
          HomeCollectionsStore.signatureOf([
            const HomeCollection(
              id: 'one',
              title: 'Changed',
              folders: [HomeCollectionFolder(id: 'f', title: 'Folder')],
            ),
          ]),
        ),
      );
    },
  );
}
