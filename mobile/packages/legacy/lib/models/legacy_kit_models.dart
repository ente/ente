import "dart:convert";

enum LegacyKitRecoveryStatus { waiting, ready, blocked, cancelled, recovered }

class LegacyKitRecoverySession {
  final String id;
  final String kitId;
  final LegacyKitRecoveryStatus status;
  // Remaining microseconds until recovery becomes ready, matching the existing
  // legacy contact recovery API contract.
  final int waitTill;
  final int createdAt;

  const LegacyKitRecoverySession({
    required this.id,
    required this.kitId,
    required this.status,
    required this.waitTill,
    required this.createdAt,
  });
}

class LegacyKitRecoveryInitiatorHint {
  final List<int> usedPartIndexes;
  final String ip;
  final String userAgent;

  const LegacyKitRecoveryInitiatorHint({
    required this.usedPartIndexes,
    required this.ip,
    required this.userAgent,
  });
}

class LegacyKitOwnerRecoverySessionDetails {
  final LegacyKitRecoverySession? session;
  final List<LegacyKitRecoveryInitiatorHint> initiators;

  const LegacyKitOwnerRecoverySessionDetails({
    required this.session,
    required this.initiators,
  });
}

class LegacyKitPart {
  final int index;
  final String name;

  const LegacyKitPart({required this.index, required this.name});
}

class LegacyKit {
  final String id;
  final int noticePeriodInHours;
  final String legacyUrl;
  final List<LegacyKitPart> parts;
  final int createdAt;
  final int updatedAt;
  final LegacyKitRecoverySession? activeRecoverySession;

  const LegacyKit({
    required this.id,
    required this.noticePeriodInHours,
    required this.legacyUrl,
    required this.parts,
    required this.createdAt,
    required this.updatedAt,
    required this.activeRecoverySession,
  });

  String get displayName => parts.map((part) => part.name).join(" · ");

  bool get hasActiveRecoverySession => activeRecoverySession != null;
}

class LegacyKitShare {
  final int payloadVersion;
  final int variant;
  final String kitId;
  final int shareIndex;
  final String share;
  final String checksum;
  final String partName;

  const LegacyKitShare({
    required this.payloadVersion,
    required this.variant,
    required this.kitId,
    required this.shareIndex,
    required this.share,
    required this.checksum,
    required this.partName,
  });

  String toQrPayload() {
    return jsonEncode({
      "pv": payloadVersion,
      "kv": variant,
      "k": _withoutWhitespace(kitId),
      "i": shareIndex,
      "s": _withoutWhitespace(share),
      "c": _withoutWhitespace(checksum),
      "n": partName,
    });
  }

  String toCopyCode() {
    return base64Url.encode(utf8.encode(toQrPayload())).replaceAll("=", "");
  }

  String _withoutWhitespace(String value) {
    return value.replaceAll(RegExp(r"\s+"), "");
  }
}

class LegacyKitCreateResult {
  final LegacyKit kit;
  final List<LegacyKitShare> shares;

  const LegacyKitCreateResult({required this.kit, required this.shares});
}
