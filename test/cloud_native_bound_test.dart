import 'package:debrify/services/cloud/alldebrid_cloud_provider.dart';
import 'package:debrify/services/cloud/cloud_playback_result.dart';
import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/cloud/rd_cloud_provider.dart';
import 'package:debrify/services/cloud/torbox_cloud_provider.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_provider.dart';

SeriesSource _bound({
  required String service,
  String id = 'dl-1',
  String kind = SeriesSource.cloudKindWebDownload,
  String hash = '',
}) => SeriesSource(
  torrentHash: hash,
  torrentName: 'Bound',
  debridService: service,
  debridTorrentId: id,
  cloudSourceKind: kind,
  boundAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CloudProviderRegistry.debugReset);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stored rd hits the debrid adapter; playback debrid does not', () async {
    final debrid = FakeCloudProvider(
      id: CloudProviderId.debrid,
      boundResult: const CloudPlaybackResult(
        title: 'Bound',
        playUrl: 'https://rd/file',
      ),
    );
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid]);

    final viaStored = await CloudProviderRegistry.instance.resolveNativeBound(
      _bound(service: 'rd'),
      contentType: 'movie',
    );
    expect(viaStored?.playUrl, 'https://rd/file');
    expect(debrid.boundCount, 1);

    final viaPlayback = await CloudProviderRegistry.instance.resolveNativeBound(
      _bound(service: 'debrid'),
      contentType: 'movie',
    );
    expect(viaPlayback, isNull);
    expect(debrid.boundCount, 1);
  });

  test('unknown stored id returns null instead of throwing', () async {
    expect(
      await CloudProviderRegistry.instance.resolveNativeBound(
        _bound(service: 'webdav'),
        contentType: 'movie',
      ),
      isNull,
    );
  });

  test('hash-backed bindings are not native-cloud replay', () async {
    final debrid = FakeCloudProvider(id: CloudProviderId.debrid);
    CloudProviderRegistry.instance = CloudProviderRegistry([debrid]);
    expect(
      await CloudProviderRegistry.instance.resolveNativeBound(
        _bound(service: 'rd', hash: 'abc123'),
        contentType: 'movie',
      ),
      isNull,
    );
    expect(debrid.boundCount, 0);
  });

  test('RD/TorBox/AllDebrid ignore folder bindings', () async {
    final folder = _bound(service: 'rd', kind: SeriesSource.cloudKindFolder);
    expect(
      await const RealDebridCloudProvider().resolveNativeBound(
        folder,
        contentType: 'movie',
      ),
      isNull,
    );
    expect(
      await const TorboxCloudProvider().resolveNativeBound(
        _bound(service: 'torbox', kind: SeriesSource.cloudKindFolder),
        contentType: 'movie',
      ),
      isNull,
    );
    expect(
      await const AllDebridCloudProvider().resolveNativeBound(
        _bound(service: 'alldebrid', kind: SeriesSource.cloudKindFolder),
        contentType: 'movie',
      ),
      isNull,
    );
  });

  test('RD web download with empty API key returns null', () async {
    expect(
      await const RealDebridCloudProvider().resolveNativeBound(
        _bound(service: 'rd'),
        contentType: 'movie',
      ),
      isNull,
    );
  });
}
