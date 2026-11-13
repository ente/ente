import 'package:ente_account_deletion/src/account_deletion_host.dart';

class AccountDeletionSettings {
  AccountDeletionSettings._privateConstructor();

  static final AccountDeletionSettings instance =
      AccountDeletionSettings._privateConstructor();

  AccountDeletionHost? _host;

  void init({required AccountDeletionHost host}) {
    _host = host;
  }

  AccountDeletionHost get host {
    final host = _host;
    if (host == null) {
      throw StateError('AccountDeletionSettings.init must be called first');
    }
    return host;
  }
}
