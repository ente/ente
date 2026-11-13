import "package:ente_frb/legacy.dart";

export "package:ente_frb/legacy.dart";

extension LegacyKitDisplay on LegacyKit {
  String get displayName => parts.map((part) => part.name).join(" · ");

  bool get hasActiveRecoverySession => activeRecoverySession != null;
}
