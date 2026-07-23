import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/protos/googleauth.pb.dart';
import 'package:logging/logging.dart';

const kGoogleAuthExportPrefix = 'otpauth-migration://offline?data=';

bool isGoogleAuthExportQr(String qrCodeData) {
  return qrCodeData.startsWith(kGoogleAuthExportPrefix);
}

class GoogleAuthMigration {
  final List<Code> codes;
  final int batchId;
  final int batchSize;
  final int batchIndex;

  const GoogleAuthMigration({
    required this.codes,
    required this.batchId,
    required this.batchSize,
    required this.batchIndex,
  });

  bool get hasValidBatchMetadata =>
      batchSize > 0 && batchIndex >= 0 && batchIndex < batchSize;
}

List<Code> parseGoogleAuth(String qrCodeData) {
  return parseGoogleAuthMigration(qrCodeData).codes;
}

GoogleAuthMigration parseGoogleAuthMigration(String qrCodeData) {
  try {
    List<Code> codes = <Code>[];
    final String payload = qrCodeData.substring(kGoogleAuthExportPrefix.length);
    final Uint8List base64Decoded = base64Decode(Uri.decodeComponent(payload));
    final MigrationPayload mPayload = MigrationPayload.fromBuffer(
      base64Decoded,
    );
    for (var otpParameter in mPayload.otpParameters) {
      // Build the OTP URL
      String otpUrl;
      String issuer = otpParameter.issuer;
      String account = otpParameter.name;
      var counter = otpParameter.counter;
      // Create a list of bytes from the list of integers.
      Uint8List bytes = Uint8List.fromList(otpParameter.secret);

      // Encode the bytes to base 32.
      String base32String = base32.encode(bytes);
      String secret = base32String;
      // identify digit count
      int digits = 6;
      int timer = 30; // default timer, no field in Google Auth
      Algorithm algorithm = Algorithm.sha1;
      switch (otpParameter.algorithm) {
        case MigrationPayload_Algorithm.ALGORITHM_MD5:
          throw Exception('GoogleAuthImport: MD5 is not supported');
        case MigrationPayload_Algorithm.ALGORITHM_SHA1:
          algorithm = Algorithm.sha1;
          break;
        case MigrationPayload_Algorithm.ALGORITHM_SHA256:
          algorithm = Algorithm.sha256;
          break;
        case MigrationPayload_Algorithm.ALGORITHM_SHA512:
          algorithm = Algorithm.sha512;
          break;
        case MigrationPayload_Algorithm.ALGORITHM_UNSPECIFIED:
          algorithm = Algorithm.sha1;
          break;
      }
      switch (otpParameter.digits) {
        case MigrationPayload_DigitCount.DIGIT_COUNT_EIGHT:
          digits = 8;
          break;
        case MigrationPayload_DigitCount.DIGIT_COUNT_SIX:
          digits = 6;
          break;
        case MigrationPayload_DigitCount.DIGIT_COUNT_UNSPECIFIED:
          digits = 6;
      }

      if (otpParameter.type == MigrationPayload_OtpType.OTP_TYPE_TOTP ||
          otpParameter.type == MigrationPayload_OtpType.OTP_TYPE_UNSPECIFIED) {
        otpUrl =
            'otpauth://totp/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=${algorithm.name}&digits=$digits&period=$timer';
      } else if (otpParameter.type == MigrationPayload_OtpType.OTP_TYPE_HOTP) {
        otpUrl =
            'otpauth://hotp/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=${algorithm.name}&digits=$digits&counter=$counter';
      } else {
        throw Exception('Invalid OTP type');
      }
      codes.add(Code.fromOTPAuthUrl(otpUrl));
    }
    return GoogleAuthMigration(
      codes: codes,
      batchId: mPayload.batchId,
      batchSize: mPayload.batchSize,
      batchIndex: mPayload.batchIndex,
    );
  } catch (e, s) {
    Logger(
      "GoogleAuthImport",
    ).severe("Error while parsing Google Auth QR code", e, s);
    throw Exception('Failed to parse Google Auth QR code \n ${e.toString()}');
  }
}
