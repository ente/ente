import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:flutter/foundation.dart';
import 'package:otp/otp.dart' as otp;
import 'package:steam_totp/steam_totp.dart';

int millisecondsSinceEpoch() {
  return DateTime.now().millisecondsSinceEpoch +
      PreferenceService.instance.timeOffsetInMilliSeconds();
}

String getOTP(Code code) {
  if (code.type == Type.steam || code.issuer.toLowerCase() == 'steam') {
    return _getSteamCode(code);
  }
  if (code.type == Type.hotp) {
    return _getHOTPCode(code);
  }
  return otp.OTP.generateTOTPCodeString(
    getSanitizedSecret(code.secret),
    millisecondsSinceEpoch(),
    length: code.digits,
    interval: code.period,
    algorithm: _getAlgorithm(code),
    isGoogle: true,
  );
}

String _getHOTPCode(Code code) {
  return otp.OTP.generateHOTPCodeString(
    getSanitizedSecret(code.secret),
    code.counter,
    length: code.digits,
    algorithm: _getAlgorithm(code),
    isGoogle: true,
  );
}

String _getSteamCode(Code code, [bool isNext = false]) {
  final SteamTOTP steamtotp = SteamTOTP(secret: code.secret);

  return steamtotp.generate(
    millisecondsSinceEpoch() ~/ 1000 + (isNext ? code.period : 0),
  );
}

String getNextTotp(Code code) {
  if (code.type == Type.steam || code.issuer.toLowerCase() == 'steam') {
    return _getSteamCode(code, true);
  }
  return otp.OTP.generateTOTPCodeString(
    getSanitizedSecret(code.secret),
    millisecondsSinceEpoch() + code.period * 1000,
    length: code.digits,
    interval: code.period,
    algorithm: _getAlgorithm(code),
    isGoogle: true,
  );
}

(int, List<String>) generateFutureTotpCodes(Code code, int count) {
  final int startTime =
      ((millisecondsSinceEpoch() ~/ 1000) ~/ code.period) * code.period * 1000;
  final String secret = getSanitizedSecret(code.secret);
  final List<String> codes = [];
  if (code.type == Type.steam || code.issuer.toLowerCase() == 'steam') {
    final SteamTOTP steamTotp = SteamTOTP(secret: code.secret);
    for (int i = 0; i < count; i++) {
      int generatedTime = startTime + code.period * 1000 * i;
      codes.add(steamTotp.generate(generatedTime ~/ 1000));
    }
  } else {
    for (int i = 0; i < count; i++) {
      int generatedTime = startTime + code.period * 1000 * i;
      final genCode = otp.OTP.generateTOTPCodeString(
        secret,
        generatedTime,
        length: code.digits,
        interval: code.period,
        algorithm: _getAlgorithm(code),
        isGoogle: true,
      );
      codes.add(genCode);
    }
  }
  return (startTime, codes);
}

otp.Algorithm _getAlgorithm(Code code) {
  switch (code.algorithm) {
    case Algorithm.sha256:
      return otp.Algorithm.SHA256;
    case Algorithm.sha512:
      return otp.Algorithm.SHA512;
    default:
      return otp.Algorithm.SHA1;
  }
}

String getSanitizedSecret(String secret) {
  return secret.toUpperCase().trim().replaceAll(' ', '');
}

String safeDecode(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (e) {
    // note: don't log the value, it might contain sensitive information
    debugPrint("Failed to decode $e");
    return value;
  }
}
