import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/metadata_provider_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.item, this.provider);
  final StremioMeta item;
  final MetadataProviderService provider;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with MetadataPresentationMixin<_Probe> {
  @override
  StremioMeta get originalMetadata => widget.item;
  @override
  MetadataProviderService get metadataProvider => widget.provider;
  @override
  Widget build(BuildContext context) => Text(
    metadataArtworkPending(MetadataCategory.backgrounds)
        ? 'pending'
        : presentedMetadata!.background ?? 'no artwork',
  );
}

void main() {
  const item = StremioMeta(
    id: 'tt1234567',
    type: 'movie',
    name: 'Synthetic',
    background: 'catalog artwork',
  );
  MetadataPreferences custom() => MetadataPreferences(
    features: {},
    providers: {MetadataCategory.backgrounds: 'addon:${'a' * 64}'},
    fallback: false,
  );
  ProfileScope scope(String id, int epoch) =>
      ProfileScope(profileId: id, dataGeneration: 1, sessionEpoch: epoch);
  late List<Completer<StremioMeta?>> replies;
  late MetadataProviderService provider;

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      MetadataPreferencesService.key: jsonEncode(custom().toJson()),
    });
    MetadataPreferencesService.revision.value++;
    replies = [];
    provider = MetadataProviderService(
      addonLoader: (_, _) {
        final reply = Completer<StremioMeta?>();
        replies.add(reply);
        return reply.future;
      },
    );
  });

  Future<void> mount(WidgetTester tester, {StremioMeta source = item}) =>
      tester.pumpWidget(MaterialApp(home: _Probe(source, provider)));
  Future<void> warm(WidgetTester tester) async {
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('pending'), findsOneWidget);
    replies.last.complete(
      StremioMeta.fromJson({
        ...item.toJson(),
        'background': 'provider artwork',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('provider artwork'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> completeLatest(WidgetTester tester, String art) async {
    replies.last.complete(
      StremioMeta.fromJson({...item.toJson(), 'background': art}),
    );
    await tester.pumpAndSettle();
    expect(find.text(art), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }

  for (final raw in ['not-json', '[]', 'null', '{"language":"fr-FR","features":[]}']) {
    testWidgets('snapshot decoding matches preference service for $raw', (tester) async {
      await (await ProfilePreferences.instance()).setString(MetadataPreferencesService.key, raw);
      await mount(tester);
      await tester.pumpAndSettle();
      final state = tester.state<_ProbeState>(find.byType(_Probe));
      expect(state.metadataPreferences.toJson(),
        (await MetadataPreferencesService.load()).toJson());
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('exact warm custom presentation paints on first remount frame', (
    tester,
  ) async {
    await warm(tester);
    await mount(tester);
    expect(find.text('provider artwork'), findsOneWidget);
    expect(find.text('pending'), findsNothing);
    expect(find.text('catalog artwork'), findsNothing);
    await tester.pumpAndSettle();
    expect(replies.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'custom provider cannot reuse presentation for changed identity',
    (tester) async {
      await warm(tester);
      final changed = StremioMeta.fromJson({
        ...item.toJson(),
        'imdb_id': 'tt7654321',
      });
      await mount(tester, source: changed);
      expect(find.text('pending'), findsOneWidget);
      expect(find.text('provider artwork'), findsNothing);
      expect(find.text('catalog artwork'), findsNothing);
      await tester.pumpAndSettle();
      expect(replies.length, 2);
      replies.last.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('catalog artwork'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'raw policy changes without notifier invalidate warm presentation',
    (tester) async {
      await warm(tester);
      final access = await ProfilePreferences.instance();
      await access.setString(
        MetadataPreferencesService.key,
        jsonEncode(custom().copyWith(language: 'fr-FR').toJson()),
      );
      await mount(tester);
      expect(find.text('pending'), findsOneWidget);
      expect(find.text('provider artwork'), findsNothing);
      await tester.pumpAndSettle();
      expect(replies.length, 2);
      await completeLatest(tester, 'French artwork');
    },
  );

  testWidgets(
    'provider configuration revision invalidates unchanged raw policy',
    (tester) async {
      await warm(tester);
      MetadataPreferencesService.revision.value++;
      await mount(tester);
      expect(find.text('pending'), findsOneWidget);
      expect(find.text('provider artwork'), findsNothing);
      await tester.pumpAndSettle();
      await completeLatest(tester, 'new configuration artwork');
    },
  );

  testWidgets(
    'selecting custom artwork cannot flash a previously current source',
    (tester) async {
      await MetadataPreferencesService.save(MetadataPreferences(features: {}));
      await mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('catalog artwork'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await (await ProfilePreferences.instance()).setString(
        MetadataPreferencesService.key,
        jsonEncode(custom().toJson()),
      );
      await mount(tester);
      expect(find.text('pending'), findsOneWidget);
      expect(find.text('catalog artwork'), findsNothing);
      await tester.pumpAndSettle();
      await completeLatest(tester, 'authorized custom artwork');
    },
  );

  testWidgets(
    'raw policy changes during provider work reject its late result',
    (tester) async {
      await mount(tester);
      await tester.pumpAndSettle();
      final old = replies.single;
      await (await ProfilePreferences.instance()).setString(
        MetadataPreferencesService.key,
        jsonEncode(custom().copyWith(language: 'fr-FR').toJson()),
      );
      old.complete(
        StremioMeta.fromJson({...item.toJson(), 'background': 'stale artwork'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('stale artwork'), findsNothing);
      expect(find.text('catalog artwork'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      expect(find.text('pending'), findsOneWidget);
      await tester.pumpAndSettle();
      await completeLatest(tester, 'current policy artwork');
    },
  );

  testWidgets('cleared preference cannot revive previous provider artwork', (
    tester,
  ) async {
    await warm(tester);
    await (await ProfilePreferences.instance()).remove(
      MetadataPreferencesService.key,
    );
    await mount(tester);
    expect(find.text('provider artwork'), findsNothing);
    expect(find.text('pending'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('catalog artwork'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'profile epoch change rejects warm presentation even for identical policy',
    (tester) async {
      final alpha = scope('alpha', 1);
      ProfileRuntime.initializeCommitted(alpha);
      await (await ProfilePreferences.instance()).setString(
        MetadataPreferencesService.key,
        jsonEncode(custom().toJson()),
      );
      await warm(tester);
      ProfileRuntime.publish(scope('alpha', 2));
      await mount(tester);
      expect(find.text('pending'), findsOneWidget);
      expect(find.text('provider artwork'), findsNothing);
      await tester.pumpAndSettle();
      await completeLatest(tester, 'new session artwork');
    },
  );

  testWidgets(
    'late old-profile provider completion cannot publish after switch',
    (tester) async {
      final alpha = scope('alpha', 1);
      final beta = scope('beta', 2);
      ProfileRuntime.initializeCommitted(alpha);
      final raw = jsonEncode(custom().toJson());
      final shared = await SharedPreferences.getInstance();
      await shared.setString(
        alpha.preferenceKey(MetadataPreferencesService.key),
        raw,
      );
      await shared.setString(
        beta.preferenceKey(MetadataPreferencesService.key),
        raw,
      );
      await mount(tester);
      await tester.pumpAndSettle();
      final old = replies.single;
      ProfileRuntime.publish(beta);
      await tester.pumpAndSettle();
      expect(find.text('pending'), findsOneWidget);
      expect(replies.length, 2);
      replies.last.complete(
        StremioMeta.fromJson({...item.toJson(), 'background': 'beta artwork'}),
      );
      await tester.pumpAndSettle();
      old.complete(
        StremioMeta.fromJson({...item.toJson(), 'background': 'alpha artwork'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('beta artwork'), findsOneWidget);
      expect(find.text('alpha artwork'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
