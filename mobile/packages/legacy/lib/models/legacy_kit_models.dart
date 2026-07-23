import "dart:convert";

import "package:ente_rust/ente_rust.dart" as rust;

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

  factory LegacyKitRecoverySession.fromRust(
    rust.LegacyKitRecoverySession session,
  ) {
    return LegacyKitRecoverySession(
      id: session.id,
      kitId: session.kitId,
      status: _statusFromRust(session.status),
      waitTill: session.waitTill,
      createdAt: session.createdAt,
    );
  }
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

  factory LegacyKitRecoveryInitiatorHint.fromRust(
    rust.LegacyKitRecoveryInitiatorHint hint,
  ) {
    return LegacyKitRecoveryInitiatorHint(
      usedPartIndexes: hint.usedPartIndexes,
      ip: hint.ip,
      userAgent: hint.userAgent,
    );
  }
}

class LegacyKitOwnerRecoverySessionDetails {
  final LegacyKitRecoverySession? session;
  final List<LegacyKitRecoveryInitiatorHint> initiators;

  const LegacyKitOwnerRecoverySessionDetails({
    required this.session,
    required this.initiators,
  });

  factory LegacyKitOwnerRecoverySessionDetails.fromRust(
    rust.LegacyKitOwnerRecoverySessionDetails details,
  ) {
    return LegacyKitOwnerRecoverySessionDetails(
      session: details.session == null
          ? null
          : LegacyKitRecoverySession.fromRust(details.session!),
      initiators: details.initiators
          .map(LegacyKitRecoveryInitiatorHint.fromRust)
          .toList(growable: false),
    );
  }
}

class LegacyKitPart {
  final int index;
  final String name;

  const LegacyKitPart({required this.index, required this.name});

  factory LegacyKitPart.fromRust(rust.LegacyKitPart part) {
    return LegacyKitPart(index: part.index, name: part.name);
  }
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

  factory LegacyKit.fromRust(rust.LegacyKit kit) {
    return LegacyKit(
      id: kit.id,
      noticePeriodInHours: kit.noticePeriodInHours,
      legacyUrl: kit.legacyUrl,
      parts: kit.metadata.parts
          .map(LegacyKitPart.fromRust)
          .toList(growable: false),
      createdAt: kit.createdAt,
      updatedAt: kit.updatedAt,
      activeRecoverySession: kit.activeRecoverySession == null
          ? null
          : LegacyKitRecoverySession.fromRust(kit.activeRecoverySession!),
    );
  }

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

  factory LegacyKitShare.fromRust(rust.LegacyKitShare share) {
    return LegacyKitShare(
      payloadVersion: share.payloadVersion,
      variant: _variantToCode(share.variant),
      kitId: share.kitId,
      shareIndex: share.shareIndex,
      share: share.share,
      checksum: share.checksum,
      partName: share.partName,
    );
  }

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

  factory LegacyKitCreateResult.fromRust(rust.LegacyKitCreateResult result) {
    return LegacyKitCreateResult(
      kit: LegacyKit.fromRust(result.kit),
      shares: result.shares
          .map(LegacyKitShare.fromRust)
          .toList(growable: false),
    );
  }
}

LegacyKitRecoveryStatus _statusFromRust(rust.LegacyKitRecoveryStatus status) {
  return switch (status) {
    rust.LegacyKitRecoveryStatus.waiting => LegacyKitRecoveryStatus.waiting,
    rust.LegacyKitRecoveryStatus.ready => LegacyKitRecoveryStatus.ready,
    rust.LegacyKitRecoveryStatus.blocked => LegacyKitRecoveryStatus.blocked,
    rust.LegacyKitRecoveryStatus.cancelled => LegacyKitRecoveryStatus.cancelled,
    rust.LegacyKitRecoveryStatus.recovered => LegacyKitRecoveryStatus.recovered,
  };
}

int _variantToCode(rust.LegacyKitVariant variant) {
  return switch (variant) {
    rust.LegacyKitVariant.twoOfThree => 1,
  };
}
