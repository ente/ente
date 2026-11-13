import 'package:ente_auth/core/configuration.dart';
import 'package:flutter/foundation.dart';

class FeatureFlagService {
  static bool isInternalUserOrDebugBuild() {
    if (kDebugMode) return true;

    final String? email = Configuration.instance.getEmail();
    final userID = Configuration.instance.getUserID();

    if (email == null || userID == null) {
      return false;
    }

    return email.endsWith("@ente.io") ||
        email.endsWith("@ente.com") ||
        (userID <= 6);
  }

  static bool isLocalBackupEnabled() {
    return true;
  }
}
