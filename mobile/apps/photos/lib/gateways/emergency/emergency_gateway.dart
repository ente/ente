import "package:dio/dio.dart";
import "package:photos/emergency/model.dart";
import "package:photos/gateways/users/models/key_attributes.dart";
import "package:photos/gateways/users/models/srp.dart";

/// Gateway for emergency contact related API endpoints.
class EmergencyGateway {
  final Dio _enteDio;

  EmergencyGateway(this._enteDio);

  /// Adds an emergency contact.
  ///
  /// [email] is the email address of the contact to add.
  /// [encryptedKey] is the base64 encoded encrypted recovery key.
  Future<void> addContact({
    required String email,
    required String encryptedKey,
    int? recoveryNoticeInDays,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/add",
      data: {
        "email": email,
        "encryptedKey": encryptedKey,
        "recoveryNoticeInDays": ?recoveryNoticeInDays,
      },
    );
  }

  /// Gets emergency contact information for the current user.
  Future<EmergencyInfo> getInfo() async {
    final response = await _enteDio.get("/emergency-contacts/info");
    return EmergencyInfo.fromJson(response.data);
  }

  /// Updates the state of an emergency contact.
  ///
  /// [userID] is the ID of the user who owns the contact.
  /// [emergencyContactID] is the ID of the emergency contact.
  /// [state] is the new state string value.
  Future<void> updateState({
    required int? userID,
    required int? emergencyContactID,
    required String state,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/update",
      data: {
        "userID": userID,
        "emergencyContactID": emergencyContactID,
        "state": state,
      },
    );
  }

  /// Updates the recovery notice period for an emergency contact.
  Future<void> updateRecoveryNotice({
    required int? emergencyContactID,
    required int recoveryNoticeInDays,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/update-recovery-notice",
      data: {
        "emergencyContactID": emergencyContactID,
        "recoveryNoticeInDays": recoveryNoticeInDays,
      },
    );
  }

  /// Starts a recovery session for the given contact.
  ///
  /// [userID] is the ID of the user to recover.
  /// [emergencyContactID] is the ID of the emergency contact initiating recovery.
  Future<void> startRecovery({
    required int? userID,
    required int? emergencyContactID,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/start-recovery",
      data: {"userID": userID, "emergencyContactID": emergencyContactID},
    );
  }

  /// Stops an ongoing recovery session.
  ///
  /// [userID] is the ID of the user being recovered.
  /// [emergencyContactID] is the ID of the emergency contact.
  /// [sessionID] is the ID of the recovery session.
  Future<void> stopRecovery({
    required int? userID,
    required int? emergencyContactID,
    required String sessionID,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/stop-recovery",
      data: {
        "userID": userID,
        "emergencyContactID": emergencyContactID,
        "id": sessionID,
      },
    );
  }

  /// Rejects a recovery session.
  ///
  /// [userID] is the ID of the user being recovered.
  /// [emergencyContactID] is the ID of the emergency contact.
  /// [sessionID] is the ID of the recovery session to reject.
  Future<void> rejectRecovery({
    required int? userID,
    required int? emergencyContactID,
    required String sessionID,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/reject-recovery",
      data: {
        "userID": userID,
        "emergencyContactID": emergencyContactID,
        "id": sessionID,
      },
    );
  }

  /// Approves a recovery session.
  ///
  /// [userID] is the ID of the user being recovered.
  /// [emergencyContactID] is the ID of the emergency contact.
  /// [sessionID] is the ID of the recovery session to approve.
  Future<void> approveRecovery({
    required int? userID,
    required int? emergencyContactID,
    required String sessionID,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/approve-recovery",
      data: {
        "userID": userID,
        "emergencyContactID": emergencyContactID,
        "id": sessionID,
      },
    );
  }

  /// Gets recovery information for a session.
  ///
  /// [sessionID] is the ID of the recovery session.
  /// Returns a tuple of (encryptedKey, keyAttributes).
  Future<(String, KeyAttributes)> getRecoveryInfo(String sessionID) async {
    final response = await _enteDio.get(
      "/emergency-contacts/recovery-info/$sessionID",
    );
    final String encryptedKey = response.data["encryptedKey"]!;
    final KeyAttributes keyAttributes = KeyAttributes.fromMap(
      response.data['userKeyAttr'],
    );
    return (encryptedKey, keyAttributes);
  }

  /// Initializes a password change for another user during recovery.
  ///
  /// [recoveryID] is the ID of the recovery session.
  /// [setupSRPRequest] is the SRP setup request data.
  /// Returns the SRP setup response.
  Future<SetupSRPResponse> initPasswordChange({
    required String recoveryID,
    required SetupSRPRequest setupSRPRequest,
  }) async {
    final response = await _enteDio.post(
      "/emergency-contacts/init-change-password",
      data: {
        "recoveryID": recoveryID,
        "setupSRPRequest": setupSRPRequest.toMap(),
      },
    );
    return SetupSRPResponse.fromJson(response.data);
  }

  /// Completes a password change for another user during recovery.
  ///
  /// [recoveryID] is the ID of the recovery session.
  /// [setupID] is the ID from the init password change response.
  /// [srpM1] is the SRP client evidence message.
  /// [updatedKeyAttr] is the updated key attributes map.
  Future<void> changePassword({
    required String recoveryID,
    required String setupID,
    required String srpM1,
    required Map<String, dynamic> updatedKeyAttr,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/change-password",
      data: {
        "recoveryID": recoveryID,
        'updateSrpAndKeysRequest': {
          'setupID': setupID,
          'srpM1': srpM1,
          'updatedKeyAttr': updatedKeyAttr,
        },
      },
    );
  }
}
