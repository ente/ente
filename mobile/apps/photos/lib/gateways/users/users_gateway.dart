import "package:dio/dio.dart";
import "package:photos/core/errors.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/gateways/users/models/key_attributes.dart";
import "package:photos/gateways/users/models/sessions.dart";
import "package:photos/gateways/users/models/set_recovery_key_request.dart";
import "package:photos/gateways/users/models/srp.dart";
import "package:photos/models/user_details.dart";

/// Gateway for user-related API endpoints.
///
/// Handles authentication, profile management, two-factor authentication,
/// SRP protocol, and other user account operations.
class UsersGateway {
  final Dio _enteDio;
  final Dio _publicDio;
  final EndpointConfig _endpointConfig;

  UsersGateway(this._enteDio, this._publicDio, this._endpointConfig);

  String get _endpoint => _endpointConfig.endpoint;

  // ============================================================
  // Authentication & Email Verification
  // ============================================================

  /// Send a one-time token (OTT) to the specified email.
  ///
  /// Parameters:
  /// - [email]: The email address to send the OTT to
  /// - [isChangeEmail]: Whether this is for changing email (purpose = "change")
  /// - [purpose]: Custom purpose string (used if not changing email)
  ///
  /// Endpoint: POST /users/ott
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

  /// Verify email with the one-time token.
  ///
  /// Returns authentication response data containing session IDs and tokens.
  ///
  /// Endpoint: POST /users/verify-email
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

  /// Change the user's email address.
  ///
  /// Endpoint: POST /users/change-email
  Future<void> changeEmail({required String email, required String ott}) async {
    await _enteDio.post(
      "/users/change-email",
      data: {"email": email, "ott": ott},
    );
  }

  // ============================================================
  // User Profile & Details
  // ============================================================

  /// Get the user's public key by email.
  ///
  /// Returns null if the email is not associated with an Ente account.
  ///
  /// Endpoint: GET /users/public-key
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

  /// Get detailed user information.
  ///
  /// Parameters:
  /// - [memoryCount]: Whether to include memory count in the response
  ///
  /// Endpoint: GET /users/details/v2
  Future<UserDetails> getUserDetails({bool memoryCount = true}) async {
    final response = await _enteDio.get(
      "/users/details/v2",
      queryParameters: {"memoryCount": memoryCount},
    );
    return UserDetails.fromMap(response.data);
  }

  /// Get all active sessions for the user.
  ///
  /// Endpoint: GET /users/sessions
  Future<Sessions> getActiveSessions() async {
    final response = await _enteDio.get("/users/sessions");
    return Sessions.fromMap(response.data);
  }

  /// Terminate a specific session.
  ///
  /// Endpoint: DELETE /users/session
  Future<void> terminateSession(String token) async {
    await _enteDio.delete("/users/session", queryParameters: {"token": token});
  }

  /// Log out the current session.
  ///
  /// Endpoint: POST /users/logout
  Future<void> logout() async {
    await _enteDio.post("/users/logout");
  }

  // ============================================================
  // Family Plan
  // ============================================================

  /// Leave the family plan.
  ///
  /// Endpoint: DELETE /family/leave
  Future<void> leaveFamilyPlan() async {
    await _enteDio.delete("/family/leave");
  }

  /// Create a family with the current user as the admin.
  ///
  /// Endpoint: POST /family/create
  Future<void> createFamily() async {
    await _enteDio.post("/family/create");
  }

  /// Invite a user to join the current user's family.
  ///
  /// Endpoint: POST /family/add-member
  Future<void> inviteFamilyMember({required String email}) async {
    await _enteDio.post("/family/add-member", data: {"email": email});
  }

  /// Remove an active family member.
  ///
  /// Endpoint: DELETE /family/remove-member/:id
  Future<void> removeFamilyMember(String id) async {
    await _enteDio.delete("/family/remove-member/$id");
  }

  /// Revoke a pending family invite.
  ///
  /// Endpoint: DELETE /family/revoke-invite/:id
  Future<void> revokeFamilyInvite(String id) async {
    await _enteDio.delete("/family/revoke-invite/$id");
  }

  /// Update a family member's storage limit.
  ///
  /// Endpoint: POST /family/modify-storage
  Future<void> updateFamilyMemberStorage({
    required String id,
    int? storageLimit,
  }) async {
    await _enteDio.post(
      "/family/modify-storage",
      data: {"id": id, "storageLimit": storageLimit},
    );
  }

  // ============================================================
  // Key Attributes & Recovery
  // ============================================================

  /// Set the user's key attributes.
  ///
  /// Endpoint: PUT /users/attributes
  Future<void> setKeyAttributes(KeyAttributes keyAttributes) async {
    await _enteDio.put(
      "/users/attributes",
      data: {"keyAttributes": keyAttributes.toMap()},
    );
  }

  /// Set the user's recovery key.
  ///
  /// Endpoint: PUT /users/recovery-key
  Future<void> setRecoveryKey(SetRecoveryKeyRequest request) async {
    await _enteDio.put("/users/recovery-key", data: request.toMap());
  }

  // ============================================================
  // SRP (Secure Remote Password) Protocol
  // ============================================================

  /// Get SRP attributes for the given email.
  ///
  /// Throws [SrpSetupNotCompleteError] if SRP is not set up for this user.
  ///
  /// Endpoint: GET /users/srp/attributes
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

  /// Set up SRP for the user.
  ///
  /// Returns the setup response containing setupID and srpB.
  ///
  /// Endpoint: POST /users/srp/setup
  Future<SetupSRPResponse> setupSrp(SetupSRPRequest request) async {
    final response = await _enteDio.post(
      "/users/srp/setup",
      data: request.toMap(),
    );
    return SetupSRPResponse.fromJson(response.data);
  }

  /// Complete the SRP setup.
  ///
  /// Endpoint: POST /users/srp/complete
  Future<void> completeSrp({
    required String setupID,
    required String srpM1,
  }) async {
    await _enteDio.post(
      "/users/srp/complete",
      data: {"setupID": setupID, "srpM1": srpM1},
    );
  }

  /// Update SRP with new key attributes.
  ///
  /// Endpoint: POST /users/srp/update
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

  /// Create an SRP session for login.
  ///
  /// Returns a map containing:
  /// - `sessionID`: The session ID for verification
  /// - `srpB`: Server's public value
  ///
  /// Endpoint: POST /users/srp/create-session
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

  /// Verify an SRP session.
  ///
  /// Returns authentication response data.
  ///
  /// Endpoint: POST /users/srp/verify-session
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

  // ============================================================
  // Two-Factor Authentication
  // ============================================================

  /// Get the two-factor authentication status.
  ///
  /// Endpoint: GET /users/two-factor/status
  Future<bool> getTwoFactorStatus() async {
    final response = await _enteDio.get("/users/two-factor/status");
    return response.data["status"] as bool;
  }

  /// Set up two-factor authentication.
  ///
  /// Returns a map containing:
  /// - `secretCode`: The TOTP secret code
  /// - `qrCode`: QR code data for authenticator apps
  ///
  /// Endpoint: POST /users/two-factor/setup
  Future<Map<String, dynamic>> setupTwoFactor() async {
    final response = await _enteDio.post("/users/two-factor/setup");
    return response.data as Map<String, dynamic>;
  }

  /// Enable two-factor authentication.
  ///
  /// Endpoint: POST /users/two-factor/enable
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

  /// Disable two-factor authentication.
  ///
  /// Endpoint: POST /users/two-factor/disable
  Future<void> disableTwoFactor() async {
    await _enteDio.post("/users/two-factor/disable");
  }

  /// Verify a two-factor authentication code during login.
  ///
  /// Returns authentication response data.
  ///
  /// Endpoint: POST /users/two-factor/verify
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

  /// Get two-factor recovery information.
  ///
  /// Returns a map containing:
  /// - `encryptedSecret`: The encrypted 2FA secret
  /// - `secretDecryptionNonce`: The nonce for decrypting the secret
  ///
  /// Endpoint: GET /users/two-factor/recover
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

  /// Remove two-factor authentication using recovery key.
  ///
  /// Returns authentication response data.
  ///
  /// Endpoint: POST /users/two-factor/remove
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

  /// Get token for passkey session during authentication.
  ///
  /// Throws [PassKeySessionExpiredError] if session expired (404/410).
  /// Throws [PassKeySessionNotVerifiedError] if session not verified (400).
  ///
  /// Endpoint: GET /users/two-factor/passkeys/get-token
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

  // ============================================================
  // Email MFA
  // ============================================================

  /// Update email MFA setting.
  ///
  /// Endpoint: PUT /users/email-mfa
  Future<void> updateEmailMFA({required bool isEnabled}) async {
    await _enteDio.put("/users/email-mfa", data: {"isEnabled": isEnabled});
  }

  // ============================================================
  // Payment & Billing
  // ============================================================

  /// Get the payment token for Stripe.
  ///
  /// Returns the payment token string, or null on failure.
  ///
  /// Endpoint: GET /users/payment-token
  Future<String?> getPaymentToken() async {
    final response = await _enteDio.get("/users/payment-token");
    return response.data["paymentToken"] as String?;
  }

  // ============================================================
  // Feedback
  // ============================================================

  /// Send anonymous feedback.
  ///
  /// Endpoint: POST /anonymous/feedback
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
