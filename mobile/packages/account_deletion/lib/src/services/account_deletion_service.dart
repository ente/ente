import 'package:dio/dio.dart';
import 'package:ente_account_deletion/src/models/account_deletion_summary.dart';

class AccountDeletionService {
  AccountDeletionService(this._enteDio);

  final Dio _enteDio;

  Future<String> getDeleteChallenge() async {
    final response = await _enteDio.get('/users/delete-challenge');
    final data = response.data as Map<String, dynamic>;
    final encryptedChallenge = data['encryptedChallenge'];
    if (encryptedChallenge is! String || encryptedChallenge.isEmpty) {
      throw StateError('Account deletion is not available');
    }
    return encryptedChallenge;
  }

  Future<void> deleteAccount({
    required String challenge,
    required String reasonCategory,
    String? feedback,
  }) async {
    final data = <String, dynamic>{
      'challenge': challenge,
      'reasonCategory': reasonCategory,
    };
    if (feedback != null && feedback.isNotEmpty) {
      data['feedback'] = feedback;
    }
    await _enteDio.delete('/users/delete', data: data);
  }

  Future<AccountDeletionSummary> getDeletionSummary() async {
    final response = await _enteDio.get('/users/deletion-summary');
    return AccountDeletionSummary.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
