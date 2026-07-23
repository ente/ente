import 'dart:convert';

import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:logging/logging.dart';

class Code {
  static const defaultDigits = 6;
  static const steamDigits = 5;
  static const defaultPeriod = 30;

  int? generatedID;
  final String account;
  final String issuer;
  final int digits;
  final int period;
  final String secret;
  final Algorithm algorithm;
  final Type type;

  /// otpauth url in the code
  final String rawData;
  final int counter;
  bool? hasSynced;

  final CodeDisplay display;

  bool get isPinned => display.pinned;

  bool get isTrashed => display.trashed;
  String get note => display.note;

  final Object? err;
  bool get hasError => err != null;

  /// Stable identifier for UI selection state and other transient UI features.
  ///
  /// This key ensures selection consistency across sync operations and local changes:
  /// - Uses [generatedID] when available (after code is persisted to database)
  /// - Falls back to [rawData] for unpersisted codes (before first save)
  ///
  /// The fallback strategy ensures that:
  /// 1. Selections survive the transition from local-only to synced codes
  /// 2. Each persisted code has a unique, stable identifier
  /// 3. UI state reconciliation can map old keys to new keys during sync
  ///
  /// See [CodeDisplayStore.reconcileSelections] for selection state management.
  String get selectionKey => generatedID?.toString() ?? rawData;

  String get issuerAccount =>
      account.isNotEmpty ? '$issuer ($account)' : issuer;

  Code(
    this.account,
    this.issuer,
    this.digits,
    this.period,
    this.secret,
    this.algorithm,
    this.type,
    this.counter,
    this.rawData, {
    this.generatedID,
    required this.display,
    this.err,
  });

  factory Code.withError(Object error, String rawData) {
    return Code(
      "",
      "",
      0,
      0,
      "",
      Algorithm.sha1,
      Type.totp,
      0,
      rawData,
      err: error,
      display: CodeDisplay(),
    );
  }

  Code copyWith({
    String? account,
    String? issuer,
    int? digits,
    int? period,
    String? secret,
    Algorithm? algorithm,
    Type? type,
    int? counter,
    CodeDisplay? display,
  }) {
    final String updateAccount = account ?? this.account;
    final String updateIssuer = issuer ?? this.issuer;
    final int updatedDigits = digits ?? this.digits;
    final int updatePeriod = period ?? this.period;
    final String updatedSecret = secret ?? this.secret;
    final Algorithm updatedAlgo = algorithm ?? this.algorithm;
    final Type updatedType = type ?? this.type;
    final int updatedCounter = counter ?? this.counter;
    final CodeDisplay updatedDisplay = display ?? this.display;
    final String encodedIssuer = Uri.encodeQueryComponent(updateIssuer);

    return Code(
      updateAccount,
      updateIssuer,
      updatedDigits,
      updatePeriod,
      updatedSecret,
      updatedAlgo,
      updatedType,
      updatedCounter,
      "otpauth://${updatedType.name}/$updateIssuer:$updateAccount?algorithm=${updatedAlgo.name.toUpperCase()}"
      "&digits=$updatedDigits&issuer=$encodedIssuer"
      "&period=$updatePeriod&secret=$updatedSecret${updatedType == Type.hotp ? "&counter=$updatedCounter" : ""}",
      generatedID: generatedID,
      display: updatedDisplay,
    );
  }

  static Code fromAccountAndSecret(
    Type type,
    String account,
    String issuer,
    String secret,
    CodeDisplay? display,
    int digits, {
    Algorithm algorithm = Algorithm.sha1,
    int period = defaultPeriod,
  }) {
    final String encodedIssuer = Uri.encodeQueryComponent(issuer);
    return Code(
      account,
      issuer,
      digits,
      period,
      secret,
      algorithm,
      type,
      0,
      "otpauth://${type.name}/$issuer:$account?algorithm=${algorithm.name.toUpperCase()}&digits=$digits&issuer=$encodedIssuer&period=$period&secret=$secret",
      display: display ?? CodeDisplay(),
    );
  }

  static Code fromOTPAuthUrl(String rawData, {CodeDisplay? display}) {
    Uri uri = Uri.parse(rawData);
    final issuer = _getIssuer(uri);
    final account = _getAccount(uri, issuer);

    try {
      final code = Code(
        account,
        issuer,
        _getDigits(uri),
        _getPeriod(uri),
        getSanitizedSecret(uri.queryParameters['secret']!),
        _getAlgorithm(uri),
        _getType(uri),
        _getCounter(uri),
        rawData,
        display: display ?? CodeDisplay.fromUri(uri) ?? CodeDisplay(),
      );
      return code;
    } catch (e) {
      // if account name contains # without encoding,
      // rest of the url are treated as url fragment
      if (rawData.contains("#")) {
        return Code.fromOTPAuthUrl(
          rawData.replaceAll("#", '%23'),
          display: display,
        );
      } else {
        Logger(
          "Code",
        ).warning('Error while parsing code for issuer $issuer, $account', e);
        rethrow;
      }
    }
  }

  static String _getAccount(Uri uri, String issuer) {
    try {
      String path = Uri.decodeComponent(uri.path);
      if (path.startsWith("/")) {
        path = path.substring(1, path.length);
      }
      // Parse account name from documented auth URI
      // otpauth://totp/ACCOUNT?secret=SUPERSECRET&issuer=SERVICE
      if (uri.queryParameters.containsKey("issuer") && !path.contains(":")) {
        return path;
      }
      // handle case where issuer name contains colon
      if (path.startsWith('$issuer:')) {
        return path.substring(issuer.length + 1);
      }
      return path.substring(
        path.indexOf(':') + 1,
      ); // return data after first colon
    } catch (e, s) {
      Logger('_getAccount').severe('Error while parsing account', e, s);
      return "";
    }
  }

  static Code fromExportJson(Map rawJson) {
    Code resultCode = Code.fromOTPAuthUrl(
      rawJson['rawData'],
      display: CodeDisplay.fromJson(rawJson['display']),
    );
    return resultCode;
  }

  String toOTPAuthUrlFormat() {
    final uri = Uri.parse(rawData.replaceAll("#", '%23'));
    final query = {...uri.queryParameters};
    query["codeDisplay"] = jsonEncode(display.toJson());

    final newUri = uri.replace(queryParameters: query);
    return jsonEncode(newUri.toString());
  }

  static String _getIssuer(Uri uri) {
    try {
      if (uri.queryParameters.containsKey("issuer")) {
        String issuerName = uri.queryParameters['issuer']!;
        // Handle issuer name with period
        // See https://github.com/ente/ente/pull/77
        if (issuerName.contains("period=")) {
          return issuerName.substring(0, issuerName.indexOf("period="));
        }
        return issuerName;
      }
      final String path = Uri.decodeComponent(uri.path);
      return path.split(':')[0].substring(1);
    } catch (e) {
      return "";
    }
  }

  static int _getDigits(Uri uri) {
    try {
      return int.parse(uri.queryParameters['digits']!);
    } catch (e) {
      if (uri.host == "steam") {
        return steamDigits;
      }
      return defaultDigits;
    }
  }

  static int _getPeriod(Uri uri) {
    try {
      return int.parse(uri.queryParameters['period']!);
    } catch (e) {
      return defaultPeriod;
    }
  }

  static int _getCounter(Uri uri) {
    try {
      final bool hasCounterKey = uri.queryParameters.containsKey('counter');
      if (!hasCounterKey) {
        return 0;
      }
      return int.parse(uri.queryParameters['counter']!);
    } catch (e) {
      return defaultPeriod;
    }
  }

  static Algorithm _getAlgorithm(Uri uri) {
    try {
      final algorithm = uri.queryParameters['algorithm']
          .toString()
          .toLowerCase();
      if (algorithm == "sha256" || "algorithm.sha256" == algorithm) {
        return Algorithm.sha256;
      } else if (algorithm == "sha512" || "algorithm.sha512" == algorithm) {
        return Algorithm.sha512;
      }
    } catch (e) {
      // nothing
    }
    return Algorithm.sha1;
  }

  static Type _getType(Uri uri) {
    if (uri.host == "totp") {
      return Type.totp;
    } else if (uri.host == "steam") {
      return Type.steam;
    } else if (uri.host == "hotp") {
      return Type.hotp;
    }
    throw UnsupportedError("Unsupported format with host ${uri.host}");
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Code &&
        other.account == account &&
        other.issuer == issuer &&
        other.digits == digits &&
        other.period == period &&
        other.secret == secret &&
        other.counter == counter &&
        other.type == type &&
        other.rawData == rawData;
  }

  @override
  int get hashCode {
    return account.hashCode ^
        issuer.hashCode ^
        digits.hashCode ^
        period.hashCode ^
        secret.hashCode ^
        type.hashCode ^
        counter.hashCode ^
        rawData.hashCode;
  }
}

enum Type {
  totp,
  hotp,
  steam;

  bool get isTOTPCompatible => this == totp || this == steam;

  bool get canShareCodes => this == totp || this == steam;
}

enum Algorithm { sha1, sha256, sha512 }
