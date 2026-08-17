import "package:dio/dio.dart";
import "package:photos/core/errors.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/gateways/users/models/key_attributes.dart";
import "package:photos/gateways/users/models/sessions.dart";
import "package:photos/gateways/users/models/set_recovery_key_request.dart";
import "package:photos/gateways/users/models/srp.dart";
import "package:photos/models/user_details.dart";

class UsersGateway {
  final Dio _enteDio;
  final Dio _publicDio;
  final EndpointConfig _endpointConfig;

  UsersGateway(this._enteDio, this._publicDio, this._endpointConfig);

  String get _endpoint => _endpointConfig.endpoint;

  Future<void> sendOtt({
    required String email,
    bool isChangeEmail = false,
    String? purpose,
    required bool isMobile,
  }) async {
    await _publicDio.post(
      "$_endpoint/users/ott",
      data: {
        "email": email,
        "purpose": isChangeEmail ? "change" : purpose ?? "",
        "mobile": isMobile,
      },
    );
  }

  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String ott,
    String? source,
  }) async {
    final data = <String, dynamic>{"email": email, "ott": ott};
    if (source != null && source.isNotEmpty) {
      data["source"] = source;
    }
    final response = await _publicDio.post(
      "$_endpoint/users/verify-email",
      data: data,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> changeEmail({required String email, required String ott}) async {
    await _enteDio.post(
      "/users/change-email",
      data: {"email": email, "ott": ott},
    );
  }

  Future<String?> getPublicKey(String email) async {
    try {
      final response = await _enteDio.get(
        "/users/public-key",
        queryParameters: {"email": email},
      );
      return response.data["publicKey"] as String?;
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<UserDetails> getUserDetails({bool memoryCount = true}) async {
    final response = await _enteDio.get(
      "/users/details/v2",
      queryParameters: {"memoryCount": memoryCount},
    );
    return UserDetails.fromMap(response.data);
  }

  Future<Sessions> getActiveSessions() async {
    final response = await _enteDio.get("/users/sessions");
    return Sessions.fromMap(response.data);
  }

  Future<void> terminateSession(String token) async {
    await _enteDio.delete("/users/session", queryParameters: {"token": token});
  }

  Future<void> logout() async {
    await _enteDio.post("/users/logout");
  }

  Future<void> leaveFamilyPlan() async {
    await _enteDio.delete("/family/leave");
  }

  Future<void> createFamily() async {
    await _enteDio.post("/family/create");
  }

  Future<void> inviteFamilyMember({required String email}) async {
    await _enteDio.post("/family/add-member", data: {"email": email});
  }

  Future<void> removeFamilyMember(String id) async {
    await _enteDio.delete("/family/remove-member/$id");
  }

  Future<void> revokeFamilyInvite(String id) async {
    await _enteDio.delete("/family/revoke-invite/$id");
  }

  Future<void> updateFamilyMemberStorage({
    required String id,
    int? storageLimit,
  }) async {
    await _enteDio.post(
      "/family/modify-storage",
      data: {"id": id, "storageLimit": storageLimit},
    );
  }

  Future<void> setKeyAttributes(KeyAttributes keyAttributes) async {
    await _enteDio.put(
      "/users/attributes",
      data: {"keyAttributes": keyAttributes.toMap()},
    );
  }

  Future<void> setRecoveryKey(SetRecoveryKeyRequest request) async {
    await _enteDio.put("/users/recovery-key", data: request.toMap());
  }

  Future<SrpAttributes> getSrpAttributes(String email) async {
    try {
      final response = await _publicDio.get(
        "$_endpoint/users/srp/attributes",
        queryParameters: {"email": email},
      );
      return SrpAttributes.fromMap(response.data);
    } on DioException catch (e) {
      if (e.response != null && e.response!.statusCode == 404) {
        throw SrpSetupNotCompleteError();
      }
      rethrow;
    }
  }

  Future<SetupSRPResponse> setupSrp(SetupSRPRequest request) async {
    final response = await _enteDio.post(
      "/users/srp/setup",
      data: request.toMap(),
    );
    return SetupSRPResponse.fromJson(response.data);
  }

  Future<void> completeSrp({
    required String setupID,
    required String srpM1,
  }) async {
    await _enteDio.post(
      "/users/srp/complete",
      data: {"setupID": setupID, "srpM1": srpM1},
    );
  }

  Future<void> updateSrp({
    required String setupID,
    required String srpM1,
    required Map<String, dynamic> updatedKeyAttr,
    required bool logOutOtherDevices,
  }) async {
    await _enteDio.post(
      "/users/srp/update",
      data: {
        "setupID": setupID,
        "srpM1": srpM1,
        "updatedKeyAttr": updatedKeyAttr,
        "logOutOtherDevices": logOutOtherDevices,
      },
    );
  }

  Future<Map<String, dynamic>> createSrpSession({
    required String srpUserID,
    required String srpA,
  }) async {
    final response = await _publicDio.post(
      "$_endpoint/users/srp/create-session",
      data: {"srpUserID": srpUserID, "srpA": srpA},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifySrpSession({
    required String sessionID,
    required String srpUserID,
    required String srpM1,
  }) async {
    final response = await _publicDio.post(
      "$_endpoint/users/srp/verify-session",
      data: {"sessionID": sessionID, "srpUserID": srpUserID, "srpM1": srpM1},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<bool> getTwoFactorStatus() async {
    final response = await _enteDio.get("/users/two-factor/status");
    return response.data["status"] as bool;
  }

  Future<Map<String, dynamic>> setupTwoFactor() async {
    final response = await _enteDio.post("/users/two-factor/setup");
    return response.data as Map<String, dynamic>;
  }

  Future<void> enableTwoFactor({
    required String code,
    required String encryptedTwoFactorSecret,
    required String twoFactorSecretDecryptionNonce,
  }) async {
    await _enteDio.post(
      "/users/two-factor/enable",
      data: {
        "code": code,
        "encryptedTwoFactorSecret": encryptedTwoFactorSecret,
        "twoFactorSecretDecryptionNonce": twoFactorSecretDecryptionNonce,
      },
    );
  }

  Future<void> disableTwoFactor() async {
    await _enteDio.post("/users/two-factor/disable");
  }

  Future<Map<String, dynamic>> verifyTwoFactor({
    required String sessionID,
    required String code,
  }) async {
    final response = await _publicDio.post(
      "$_endpoint/users/two-factor/verify",
      data: {"sessionID": sessionID, "code": code},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> recoverTwoFactor({
    required String sessionID,
    required String twoFactorType,
  }) async {
    final response = await _publicDio.get(
      "$_endpoint/users/two-factor/recover",
      queryParameters: {"sessionID": sessionID, "twoFactorType": twoFactorType},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> removeTwoFactor({
    required String sessionID,
    required String secret,
    required String twoFactorType,
  }) async {
    final response = await _publicDio.post(
      "$_endpoint/users/two-factor/remove",
      data: {
        "sessionID": sessionID,
        "secret": secret,
        "twoFactorType": twoFactorType,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTokenForPasskeySession(
    String sessionID,
  ) async {
    try {
      final response = await _publicDio.get(
        "$_endpoint/users/two-factor/passkeys/get-token",
        queryParameters: {"sessionID": sessionID},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 404 || e.response!.statusCode == 410) {
          throw PassKeySessionExpiredError();
        }
        if (e.response!.statusCode == 400) {
          throw PassKeySessionNotVerifiedError();
        }
      }
      rethrow;
    }
  }

  Future<void> updateEmailMFA({required bool isEnabled}) async {
    await _enteDio.put("/users/email-mfa", data: {"isEnabled": isEnabled});
  }

  Future<String?> getPaymentToken() async {
    final response = await _enteDio.get("/users/payment-token");
    return response.data["paymentToken"] as String?;
  }

  Future<void> sendFeedback({
    required String feedback,
    required String type,
  }) async {
    await _publicDio.post(
      "$_endpoint/anonymous/feedback",
      data: {"feedback": feedback, "type": type},
    );
  }
}
