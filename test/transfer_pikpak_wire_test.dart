import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/transfer/transfer_categories.dart';
import 'package:debrify/services/transfer/transfer_category.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Origin Send Setup to TV / Transfer Everything encoded `{email}` when the
/// typed password was empty. `_readPikpakWire` must not drop the item.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(ProfileRuntime.debugReset);

  test('empty password still sends email-only pikpak wire', () async {
    await StorageService.setPikPakEmail('user@example.com');
    final body = await TransferCategories.pikpak.readWire!(
      const TransferSendContext(pikpakPassword: ''),
    );
    expect(body, isA<Map>());
    expect(body, {'email': 'user@example.com'});
  });

  test('null password still sends email-only pikpak wire', () async {
    await StorageService.setPikPakEmail('user@example.com');
    final body = await TransferCategories.pikpak.readWire!(
      const TransferSendContext(),
    );
    expect(body, {'email': 'user@example.com'});
  });

  test('non-empty password is included', () async {
    await StorageService.setPikPakEmail('user@example.com');
    final body = await TransferCategories.pikpak.readWire!(
      const TransferSendContext(pikpakPassword: 'secret'),
    );
    expect(body, {'email': 'user@example.com', 'password': 'secret'});
  });

  test('missing email skips the wire payload', () async {
    final body = await TransferCategories.pikpak.readWire!(
      const TransferSendContext(pikpakPassword: 'secret'),
    );
    expect(body, isNull);
  });
}
