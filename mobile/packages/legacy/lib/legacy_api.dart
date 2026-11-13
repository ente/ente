import "package:ente_frb/legacy.dart";

abstract interface class LegacyApi {
  Future<LegacyInfo> info();

  Future<void> addContact({
    required String email,
    required int recoveryNoticeInDays,
  });

  Future<void> updateContact({
    required int userId,
    required int emergencyContactId,
    required LegacyContactState state,
  });

  Future<void> updateRecoveryNotice({
    required int emergencyContactId,
    required int recoveryNoticeInDays,
  });

  Future<void> startRecovery({
    required int userId,
    required int emergencyContactId,
  });

  Future<void> stopRecovery({
    required String recoveryId,
    required int userId,
    required int emergencyContactId,
  });

  Future<void> rejectRecovery({
    required String recoveryId,
    required int userId,
    required int emergencyContactId,
  });

  Future<void> approveRecovery({
    required String recoveryId,
    required int userId,
    required int emergencyContactId,
  });

  Future<void> changePassword({
    required String recoveryId,
    required String newPassword,
  });

  Future<List<LegacyKit>> kits();

  Future<LegacyKitCreateResult> createKit({
    required List<String> partNames,
    required int noticePeriodInHours,
  });

  Future<List<LegacyKitShare>> downloadKitShares({required String kitId});

  Future<void> updateKitRecoveryNotice({
    required String kitId,
    required int noticePeriodInHours,
  });

  Future<void> blockKitRecovery({required String kitId});

  Future<void> deleteKit({required String kitId});
}
