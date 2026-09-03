# Baseline flutter test failures

Measured 2026-09-03 on Linux (`flutter test test --reporter compact`) with
Flutter 3.44.8 **before** `libsqlite3` was installed: 3689 passed / 500 failed.
Those failures were `libsqlite3.so` missing (`IptvCatalogDb` / profile sqlite),
not the cloud port.

After `apt-get install libsqlite3-dev`, previously failing `test/iptv_catalog_db_test.dart`
and `test/backup_encryption_test.dart` pass. CI installs the same library.

**New failures outside sqlite/golden environment issues are regressions.**

The safety-net slice itself is gated by:

```
flutter test test/adversarial test/cloud_playback_characterization_test.dart test/download_cloud_credential_key_test.dart
```

Those files passed 32/32 on this machine without sqlite.
