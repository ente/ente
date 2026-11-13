import "package:dio/dio.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/gateways/users/models/sessions.dart";
import "package:photos/gateways/users/models/set_recovery_key_request.dart";
import "package:photos/models/user_details.dart";

class UsersGateway {
  final Dio _enteDio;
  final Dio _publicDio;
  final EndpointConfig _endpointConfig;

  UsersGateway(this._enteDio, this._publicDio, this._endpointConfig);

  String get _endpoint => _endpointConfig.endpoint;

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

  Future<List<String>> getPublicKeys(List<String> emails) async {
    final response = await _enteDio.post(
      "/users/public-keys",
      data: {"emails": emails},
    );
    final values = response.data["publicKeys"] as List;
    if (values.length != emails.length) {
      throw StateError("Public-key batch response length mismatch");
    }
    return values.map((value) => value as String).toList();
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

  Future<void> setRecoveryKey(SetRecoveryKeyRequest request) async {
    await _enteDio.put("/users/recovery-key", data: request.toMap());
  }

  Future<bool> getTwoFactorStatus() async {
    final response = await _enteDio.get("/users/two-factor/status");
    return response.data["status"] as bool;
  }

  Future<void> disableTwoFactor() async {
    await _enteDio.post("/users/two-factor/disable");
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
