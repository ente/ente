import "package:ente_frb/active_sessions.dart";
import "package:flutter/widgets.dart";

abstract class ActiveSessionsHost {
  Future<List<ActiveSession>> listActiveSessions();

  Future<void> revokeActiveSession(String id);

  Future<void> logoutThisDevice(BuildContext context);
}
