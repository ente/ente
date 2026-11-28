import 'package:ente_frb/account_deletion.dart';
import 'package:ente_frb/active_sessions.dart';
import 'package:flutter/widgets.dart';

abstract class AccountSettingsHost {
  Future<AccountDeletionSummary?> getDeletionSummary();

  Future<String> getDeleteChallenge();

  Future<void> deleteAccount({
    required String encryptedChallenge,
    required String reason,
    String? feedback,
  });

  Future<void> logoutLocally();

  Future<List<ActiveSession>> listActiveSessions();

  Future<void> revokeActiveSession(String id);

  Future<void> logoutThisDevice(BuildContext context);
}

class AccountSettings {
  AccountSettings._privateConstructor();

  static final AccountSettings instance = AccountSettings._privateConstructor();

  AccountSettingsHost? _host;

  void init({required AccountSettingsHost host}) {
    _host = host;
  }

  AccountSettingsHost get host {
    final host = _host;
    if (host == null) {
      throw StateError('AccountSettings.init must be called first');
    }
    return host;
  }
}
