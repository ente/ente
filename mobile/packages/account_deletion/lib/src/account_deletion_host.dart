abstract class AccountDeletionHost {
  /// Decrypts the account deletion challenge using the host's keypair and
  /// returns the decoded challenge that is sent back to the server.
  String decryptDeleteChallenge(String encryptedChallenge);

  Future<void> logout();
}
