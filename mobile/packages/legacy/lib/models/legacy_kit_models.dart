import "dart:convert";

import "package:ente_frb/legacy.dart";

export "package:ente_frb/legacy.dart";

extension LegacyKitDisplay on LegacyKit {
  String get displayName => parts.map((part) => part.name).join(" · ");

  bool get hasActiveRecoverySession => activeRecoverySession != null;
}

extension LegacyKitShareEncoding on LegacyKitShare {
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
