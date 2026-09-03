import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download credential keys match CloudProviderId', () {
    for (final id in CloudProviderId.values) {
      expect(
        DownloadService.credentialKeyForCloudProvider(id.playbackId),
        id.credentialKey,
      );
    }
    expect(DownloadService.credentialKeyForCloudProvider('realdebrid'),
        'real_debrid_api_key');
    expect(DownloadService.credentialKeyForCloudProvider('nope'), isNull);
  });
}
