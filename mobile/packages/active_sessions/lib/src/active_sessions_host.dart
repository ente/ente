import "package:ente_active_sessions/src/active_session.dart";
import "package:flutter/widgets.dart";

abstract class ActiveSessionsHost {
  Future<List<ActiveSession>> listActiveSessions();

  Future<void> revokeActiveSession(String id);

  Future<void> logout(BuildContext context);
}
