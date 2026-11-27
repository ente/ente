import "package:ente_account_settings/src/active_sessions_host.dart";

class ActiveSessionsSettings {
  ActiveSessionsSettings._privateConstructor();

  static final ActiveSessionsSettings instance =
      ActiveSessionsSettings._privateConstructor();

  ActiveSessionsHost? _host;

  void init({required ActiveSessionsHost host}) {
    _host = host;
  }

  ActiveSessionsHost get host {
    final host = _host;
    if (host == null) {
      throw StateError("ActiveSessionsSettings.init must be called first");
    }
    return host;
  }
}
