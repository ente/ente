import 'package:dio/dio.dart';
import 'package:ente_account_deletion/src/account_deletion_host.dart';
import 'package:ente_account_deletion/src/services/account_deletion_service.dart';

class AccountDeletionSettings {
  AccountDeletionSettings._privateConstructor();

  static final AccountDeletionSettings instance =
      AccountDeletionSettings._privateConstructor();

  AccountDeletionHost? _host;
  AccountDeletionService? _service;

  void init({required AccountDeletionHost host, required Dio enteDio}) {
    _host = host;
    _service = AccountDeletionService(enteDio);
  }

  AccountDeletionHost get host {
    final host = _host;
    if (host == null) {
      throw StateError('AccountDeletionSettings.init must be called first');
    }
    return host;
  }

  AccountDeletionService get service {
    final service = _service;
    if (service == null) {
      throw StateError('AccountDeletionSettings.init must be called first');
    }
    return service;
  }
}
