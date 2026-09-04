import 'package:flutter/foundation.dart';

import 'transfer_category.dart';
import 'transfer_categories.dart';

/// Ordered registry of backup / remote-transfer categories.
///
/// Order is data: it is today's [BackupRestoreService.applyBackup] sequence
/// (IPTV providers before memberships; tracking preferences last).
class TransferCategoryRegistry {
  TransferCategoryRegistry(List<TransferCategory> categories)
    : _categories = List<TransferCategory>.of(categories);

  factory TransferCategoryRegistry.production() =>
      TransferCategoryRegistry(TransferCategories.builtins);

  static TransferCategoryRegistry instance =
      TransferCategoryRegistry.production();

  final List<TransferCategory> _categories;

  List<TransferCategory> get all =>
      List<TransferCategory>.unmodifiable(_categories);

  void register(TransferCategory category) {
    _categories.add(category);
  }

  @visibleForTesting
  static void debugReset() {
    instance = TransferCategoryRegistry.production();
  }

  TransferCategory? byKey(String key) {
    for (final category in _categories) {
      if (category.key == key) return category;
    }
    return null;
  }

  TransferCategory? byWireCommand(String command) {
    for (final category in _categories) {
      if (category.wireCommand == command) return category;
    }
    return null;
  }

  String? summarizeLabelForWire(String command) =>
      byWireCommand(command)?.summarizeLabel;

  /// Config commands whose remote items wrap in the v4 transfer envelope.
  /// [trackingPreferences] is intentionally absent — that packet still
  /// travels as a raw body even inside a transactional transfer.
  Set<String> get remoteBatchCommands => {
    for (final category in _categories)
      if (category.remoteBatch && category.wireCommand != null)
        category.wireCommand!,
  };

  /// Wire command → backup payload key, including categories that are
  /// buffered but not counted in [expectedPayloadKeys].
  Map<String, String> get wireCommandToPayloadKey => {
    for (final category in _categories)
      if (category.wireCommand != null)
        category.wireCommand!: category.payloadKey,
  };

  /// Subset used by `_profilePayloadContainsExpected`. Omits
  /// tracking preferences (today's map did not list them).
  Map<String, String> get expectedPayloadKeys => {
    for (final category in _categories)
      if (category.wireCommand != null && category.expectedInProfilePayload)
        category.wireCommand!: category.payloadKey,
  };

  Map<String, String> get rawStringPayloadToWire => {
    for (final category in _categories)
      if (category.wireEncoding == TransferWireEncoding.rawString &&
          category.wireCommand != null)
        category.payloadKey: category.wireCommand!,
  };

  Map<String, String> get encodedPayloadToWire => {
    for (final category in _categories)
      if (category.wireEncoding == TransferWireEncoding.json &&
          category.wireCommand != null)
        category.payloadKey: category.wireCommand!,
  };
}
