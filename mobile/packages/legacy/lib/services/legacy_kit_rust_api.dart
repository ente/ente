import "dart:typed_data";

import "package:ente_base/models/key_attributes.dart";
import "package:ente_contacts/contacts.dart" as contacts;
import "package:ente_legacy/models/legacy_kit_models.dart";

class LegacyKitActiveRecoverySessionException implements Exception {}

abstract class LegacyKitRustContext {
  Future<void> updateAuthToken(String authToken);

  Future<List<LegacyKit>> legacyKits();

  Future<LegacyKitCreateResult> legacyKitCreate({
    required KeyAttributes currentUserKeyAttrs,
    required List<String> partNames,
    required int noticePeriodInHours,
  });

  Future<List<LegacyKitShare>> legacyKitDownloadShares(String kitId);

  Future<LegacyKitOwnerRecoverySessionDetails> legacyKitRecoverySession(
    String kitId,
  );

  Future<void> legacyKitUpdateRecoveryNotice({
    required String kitId,
    required int noticePeriodInHours,
  });

  Future<void> legacyKitBlockRecovery(String kitId);

  Future<void> legacyKitDelete(String kitId);
}

abstract class LegacyKitRustApi {
  Future<LegacyKitRustContext> open(
    contacts.ContactsSession session,
    Uint8List accountKey,
  );
}
