import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/utils/totp_util.dart';

class CodeSnapshot {
  const CodeSnapshot._(this.data, this.omittedCount);

  final Uint8List data;
  final int omittedCount;

  static bool _isSteam(Code code) =>
      code.type == Type.steam ||
      (code.type == Type.totp && code.issuer.toLowerCase() == 'steam');

  static bool supports(Code code) =>
      !code.hasError &&
      !code.isTrashed &&
      (_isSteam(code) || code.type == Type.totp);

  factory CodeSnapshot.fromCodes(Iterable<Code> codes) {
    final entries = <Map<String, Object>>[];
    var omitted = 0;
    for (final code in codes.where((c) => !c.hasError && !c.isTrashed)) {
      if (!supports(code)) {
        omitted++;
        continue;
      }
      try {
        entries.add(_encodeEntry(code));
      } on FormatException {
        omitted++;
      }
    }
    final payload = <String, Object>{'entries': entries};
    return CodeSnapshot._(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      omitted,
    );
  }

  static Map<String, Object> _encodeEntry(Code code) {
    final steam = _isSteam(code);
    final digits = steam ? 5 : code.digits;
    final period = steam ? 30 : code.period;
    if (digits < 1 || digits > 10 || period <= 0 || period > 0x7fffffff) {
      throw const FormatException('Unsupported OTP settings.');
    }
    final secret = base32.decode(getSanitizedSecret(code.secret));
    if (secret.isEmpty) {
      throw const FormatException('Missing OTP secret.');
    }
    final tags = code.display.tags.where((tag) => tag.isNotEmpty).toList()
      ..sort();
    return {
      'id': code.generatedID!.toString(),
      'issuer': code.issuer,
      'account': code.account,
      'secret': base64Encode(secret),
      'generator': steam ? 'steam' : 'totp',
      'algorithm': steam ? Algorithm.sha1.name : code.algorithm.name,
      'digits': digits,
      'period': period,
      'pinned': code.isPinned,
      'tags': tags,
    };
  }
}
