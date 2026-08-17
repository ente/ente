import "package:dio/dio.dart";
import "package:photos/emergency/model.dart";
import "package:photos/gateways/users/models/key_attributes.dart";
import "package:photos/gateways/users/models/srp.dart";

class EmergencyGateway {
  final Dio _enteDio;

  EmergencyGateway(this._enteDio);

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

  Future<EmergencyInfo> getInfo() async {
    final response = await _enteDio.get("/emergency-contacts/info");
    return EmergencyInfo.fromJson(response.data);
  }

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

  Future<void> startRecovery({
    required int? userID,
    required int? emergencyContactID,
  }) async {
    await _enteDio.post(
      "/emergency-contacts/start-recovery",
      data: {"userID": userID, "emergencyContactID": emergencyContactID},
    );
  }

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
