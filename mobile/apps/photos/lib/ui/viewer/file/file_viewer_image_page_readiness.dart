import "package:flutter/foundation.dart";

typedef FileViewerImagePageReadinessRegistration =
    void Function(
      Object fileIdentity,
      ValueListenable<bool> readiness, {
      required bool isAttached,
    });
