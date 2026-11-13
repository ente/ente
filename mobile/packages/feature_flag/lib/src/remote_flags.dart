import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

class RemoteFlags {
  final bool enableStripe;
  final bool disableCFWorker;
  final bool mapEnabled;
  final bool faceSearchEnabled;
  final bool recoveryKeyVerified;
  final bool internalUser;
  final bool betaUser;
  final bool enableMobMultiPart;
  final int serverApiFlag;
  final String castUrl;
  final String embedUrl;
  final String customDomain;
  final String customDomainCNAME;

  RemoteFlags({
    required this.enableStripe,
    required this.disableCFWorker,
    required this.mapEnabled,
    required this.faceSearchEnabled,
    required this.recoveryKeyVerified,
    required this.internalUser,
    required this.betaUser,
    required this.enableMobMultiPart,
    required this.serverApiFlag,
    required this.castUrl,
    required this.embedUrl,
    required this.customDomain,
    required this.customDomainCNAME,
  });

  RemoteFlags copyWith({
    bool? enableStripe,
    bool? disableCFWorker,
    bool? mapEnabled,
    bool? faceSearchEnabled,
    bool? recoveryKeyVerified,
    bool? internalUser,
    bool? betaUser,
    bool? enableMobMultiPart,
    int? serverApiFlag,
    String? castUrl,
    String? customDomain,
    String? customDomainCNAME,
    String? embedUrl,
  }) {
    return RemoteFlags(
      enableStripe: enableStripe ?? this.enableStripe,
      disableCFWorker: disableCFWorker ?? this.disableCFWorker,
      mapEnabled: mapEnabled ?? this.mapEnabled,
      faceSearchEnabled: faceSearchEnabled ?? this.faceSearchEnabled,
      recoveryKeyVerified: recoveryKeyVerified ?? this.recoveryKeyVerified,
      internalUser: internalUser ?? this.internalUser,
      betaUser: betaUser ?? this.betaUser,
      enableMobMultiPart: enableMobMultiPart ?? this.enableMobMultiPart,
      serverApiFlag: serverApiFlag ?? this.serverApiFlag,
      castUrl: castUrl ?? this.castUrl,
      customDomain: customDomain ?? this.customDomain,
      customDomainCNAME: customDomainCNAME ?? this.customDomainCNAME,
      embedUrl: embedUrl ?? this.embedUrl,
    );
  }

  static RemoteFlags defaultValue = RemoteFlags(
    enableStripe: Platform.isAndroid,
    disableCFWorker: false,
    mapEnabled: false,
    faceSearchEnabled: false,
    recoveryKeyVerified: true,
    internalUser: kDebugMode,
    betaUser: kDebugMode,
    enableMobMultiPart: false,
    serverApiFlag: 0,
    castUrl: "https://cast.ente.com",
    customDomain: "",
    embedUrl: "https://embed.ente.com",
    customDomainCNAME: "my.ente.com",
  );

  String toJson() => json.encode(toMap());
  Map<String, dynamic> toMap() {
    return {
      'enableStripe': enableStripe,
      'disableCFWorker': disableCFWorker,
      'mapEnabled': mapEnabled,
      'faceSearchEnabled': faceSearchEnabled,
      'recoveryKeyVerified': recoveryKeyVerified,
      'internalUser': internalUser,
      'betaUser': betaUser,
      'enableMobMultiPart': enableMobMultiPart,
      'serverApiFlag': serverApiFlag,
      'castUrl': castUrl,
      'customDomain': customDomain,
      'customDomainCNAME': customDomainCNAME,
      'embedUrl': embedUrl,
    };
  }

  factory RemoteFlags.fromMap(Map<String, dynamic> map) {
    return RemoteFlags(
      enableStripe: map['enableStripe'] ?? defaultValue.enableStripe,
      disableCFWorker: map['disableCFWorker'] ?? defaultValue.disableCFWorker,
      mapEnabled: map['mapEnabled'] ?? defaultValue.mapEnabled,
      faceSearchEnabled:
          map['faceSearchEnabled'] ?? defaultValue.faceSearchEnabled,
      recoveryKeyVerified:
          map['recoveryKeyVerified'] ?? defaultValue.recoveryKeyVerified,
      internalUser: map['internalUser'] ?? defaultValue.internalUser,
      betaUser: map['betaUser'] ?? defaultValue.betaUser,
      enableMobMultiPart:
          map['enableMobMultiPart'] ?? defaultValue.enableMobMultiPart,
      serverApiFlag: _parseServerApiFlag(map) ?? defaultValue.serverApiFlag,
      castUrl: map['castUrl'] ?? defaultValue.castUrl,
      customDomain: map['customDomain'] ?? defaultValue.customDomain,
      customDomainCNAME:
          map['customDomainCNAME'] ?? defaultValue.customDomainCNAME,
      embedUrl: map['embedUrl'] ?? defaultValue.embedUrl,
    );
  }
}

int? _parseServerApiFlag(Map<String, dynamic> map) {
  final dynamic raw = map['serverApiFlag'];
  if (raw is num) {
    return raw.toInt();
  }
  return null;
}
