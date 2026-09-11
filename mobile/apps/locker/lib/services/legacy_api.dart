import "package:ente_frb/legacy.dart";
import "package:ente_legacy/legacy_api.dart";
import "package:locker/services/authenticated_session.dart";
import "package:locker/src/rust/third_party/ente_frb_lib/legacy/contact.dart"
    as contact;
import "package:locker/src/rust/third_party/ente_frb_lib/legacy/kit.dart"
    as kit;
import "package:locker/src/rust/third_party/ente_frb_lib/legacy/recovery.dart"
    as recovery;

class LockerLegacyApi implements LegacyApi {
  const LockerLegacyApi();

  @override
  Future<LegacyInfo> info() => contact.info(session: authenticatedSession());

  @override
  Future<void> addContact({
    required String email,
    required int recoveryNoticeInDays,
  }) => contact.addContact(
    session: authenticatedSession(),
    email: email,
    recoveryNoticeInDays: recoveryNoticeInDays,
  );

  @override
  Future<void> updateContact({
    required int userId,
    required int emergencyContactId,
    required LegacyContactState state,
  }) => contact.updateContact(
    session: authenticatedSession(),
    userId: userId,
    emergencyContactId: emergencyContactId,
    state: state,
  );

  @override
  Future<void> updateRecoveryNotice({
    required int emergencyContactId,
    required int recoveryNoticeInDays,
  }) => contact.updateRecoveryNotice(
    session: authenticatedSession(),
    emergencyContactId: emergencyContactId,
    recoveryNoticeInDays: recoveryNoticeInDays,
  );

  @override
  Future<void> startRecovery({
    required int userId,
    required int emergencyContactId,
  }) => recovery.startRecovery(
    session: authenticatedSession(),
    userId: userId,
    emergencyContactId: emergencyContactId,
  );

  @override
  Future<void> stopRecovery({
    required String recoveryId,
    required int userId,
    required int emergencyContactId,
  }) => recovery.stopRecovery(
    session: authenticatedSession(),
    recoveryId: recoveryId,
    userId: userId,
    emergencyContactId: emergencyContactId,
  );

  @override
  Future<void> rejectRecovery({
    required String recoveryId,
    required int userId,
    required int emergencyContactId,
  }) => recovery.rejectRecovery(
    session: authenticatedSession(),
    recoveryId: recoveryId,
    userId: userId,
    emergencyContactId: emergencyContactId,
  );

  @override
  Future<void> approveRecovery({
    required String recoveryId,
    required int userId,
    required int emergencyContactId,
  }) => recovery.approveRecovery(
    session: authenticatedSession(),
    recoveryId: recoveryId,
    userId: userId,
    emergencyContactId: emergencyContactId,
  );

  @override
  Future<void> changePassword({
    required String recoveryId,
    required String newPassword,
  }) => recovery.changePassword(
    session: authenticatedSession(),
    recoveryId: recoveryId,
    newPassword: newPassword,
  );

  @override
  Future<List<LegacyKit>> kits() => kit.kits(session: authenticatedSession());

  @override
  Future<LegacyKitCreateResult> createKit({
    required List<String> partNames,
    required int noticePeriodInHours,
  }) => kit.createKit(
    session: authenticatedSession(),
    partNames: partNames,
    noticePeriodInHours: noticePeriodInHours,
  );

  @override
  Future<List<LegacyKitShare>> downloadKitShares({required String kitId}) =>
      kit.downloadKitShares(session: authenticatedSession(), kitId: kitId);

  @override
  Future<void> updateKitRecoveryNotice({
    required String kitId,
    required int noticePeriodInHours,
  }) => kit.updateKitRecoveryNotice(
    session: authenticatedSession(),
    kitId: kitId,
    noticePeriodInHours: noticePeriodInHours,
  );

  @override
  Future<void> blockKitRecovery({required String kitId}) =>
      kit.blockKitRecovery(session: authenticatedSession(), kitId: kitId);

  @override
  Future<void> deleteKit({required String kitId}) =>
      kit.deleteKit(session: authenticatedSession(), kitId: kitId);
}
