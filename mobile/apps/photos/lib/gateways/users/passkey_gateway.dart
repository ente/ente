import "package:dio/dio.dart";

class PasskeyGateway {
  final Dio _enteDio;

  PasskeyGateway(this._enteDio);

  Future<Map<String, dynamic>> getAccountsToken() async {
    final response = await _enteDio.get("/users/accounts-token");
    return response.data as Map<String, dynamic>;
  }

  Future<bool> isPasskeyRecoveryEnabled() async {
    final response = await _enteDio.get("/users/two-factor/recovery-status");
    return response.data["isPasskeyRecoveryEnabled"] as bool;
  }

  Future<void> configurePasskeyRecovery({
    required String secret,
    required String userSecretCipher,
    required String userSecretNonce,
  }) async {
    await _enteDio.post(
      "/users/two-factor/passkeys/configure-recovery",
      data: {
        "secret": secret,
        "userSecretCipher": userSecretCipher,
        "userSecretNonce": userSecretNonce,
      },
    );
  }
}
