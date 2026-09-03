import 'dart:io';

import 'package:debrify/services/cloud/cloud_provider_id.dart';
import 'package:debrify/services/cloud/cloud_provider_registry.dart';
import 'package:debrify/services/local_bound_source_service.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancelled picker sentinel is not a real provider id', () {
    expect(CloudProviderId.tryParse('__cancelled__'), isNull);
    expect(
      () => CloudProviderRegistry.instance.require('__cancelled__'),
      throwsA(isA<Exception>()),
    );
  });

  test('unconfigured unknown provider is not configured', () async {
    expect(await CloudProviderRegistry.instance.isConfigured(''), isFalse);
    expect(
      await CloudProviderRegistry.instance.isConfigured('webdav'),
      isFalse,
    );
  });

  test('local binding availability matches mobile platform gate', () {
    final mobile = Platform.isAndroid || Platform.isIOS;
    expect(LocalBoundSourceService.isLocalBindingDisabled, mobile);
    expect(TorrentPlaybackService.localBindingAvailable, isNot(mobile));
  });
}
