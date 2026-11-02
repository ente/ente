import 'package:ente_frb/account_deletion.dart';

abstract class AccountDeletionHost {
  Future<AccountDeletionSummary?> getDeletionSummary();

  Future<String> getDeleteChallenge();

  Future<void> deleteAccount({
    required String encryptedChallenge,
    required String reason,
    String? feedback,
  });

  Future<void> logout();
}
