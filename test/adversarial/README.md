# Cloud / playback adversarial suite

Run with:

```
flutter test test/adversarial/
```

These tests try to break the cloud-provider port the same way
`test/profiles/isolation_suite/` tries to break profile isolation.

| File | Shape | Answers |
| --- | --- | --- |
| `parser_fuzz_test.dart` | seeded garbage | Do title / M3U / magnet parsers throw? |
| `provider_matrix_test.dart` | fake every provider | Missing config, empty files, cache miss, 429 |
| `playback_invariants_test.dart` | behavioural | Cancel sentinel, unknown provider, local bind gate |
| `storage_key_sweep_test.dart` | enumerate-then-assert | Cloud credential writes stay profile-scoped |

Every assertion should be mutation-tested: reintroduce the bug and confirm the
guard fails. A guard that cannot fail is worse than no guard.
