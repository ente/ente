abstract class AccountDeletionHost {
  String decryptDeleteChallenge(String encryptedChallenge);

  Future<void> logout();
}
