import 'dart:convert';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/protos/googleauth.pb.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_import.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_migration_tracker.dart';
import 'package:ente_auth/utils/gallery_import_util.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Google Authenticator migration QR codes', () {
    final secret = _testSecret();
    final qrCode = _testGoogleAuthQrCode(secret);

    expect(isGoogleAuthExportQr(qrCode), true);

    final codes = parseGoogleAuth(qrCode);
    expect(codes, hasLength(2));
    expect(codes[0].issuer, 'GitHub');
    expect(codes[0].account, 'testdata@ente.io');
    expect(codes[0].secret, base32.encode(secret));
    expect(codes[0].algorithm, Algorithm.sha256);
    expect(codes[0].digits, 8);
    expect(codes[0].type, Type.totp);
    expect(codes[1].issuer, 'Example');
    expect(codes[1].account, 'counter@example.com');
    expect(codes[1].counter, 42);
    expect(codes[1].type, Type.hotp);
  });

  test('parses Google Authenticator migration batch metadata', () {
    final migration = parseGoogleAuthMigration(
      _testGoogleAuthQrCode(
        _testSecret(),
        batchId: 42,
        batchSize: 3,
        batchIndex: 2,
      ),
    );

    expect(migration.batchId, 42);
    expect(migration.batchSize, 3);
    expect(migration.batchIndex, 2);
    expect(migration.hasValidBatchMetadata, true);
  });

  test('completes a single-batch Google Authenticator migration', () {
    final tracker = GoogleAuthMigrationTracker();

    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 1, batchIndex: 0)),
      true,
    );
  });

  test('waits for every Google Authenticator migration batch', () {
    final tracker = GoogleAuthMigrationTracker();

    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 3, batchIndex: 2)),
      false,
    );
    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 3, batchIndex: 0)),
      false,
    );
    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 3, batchIndex: 1)),
      true,
    );
  });

  test('does not count duplicate or unrelated migration batches', () {
    final tracker = GoogleAuthMigrationTracker();

    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 2, batchIndex: 0)),
      false,
    );
    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 2, batchIndex: 0)),
      false,
    );
    expect(
      tracker.record(_testMigration(batchId: 7, batchSize: 2, batchIndex: 1)),
      false,
    );
    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 2, batchIndex: 1)),
      true,
    );
  });

  test('does not complete without valid migration batch metadata', () {
    final tracker = GoogleAuthMigrationTracker();

    expect(
      tracker.record(_testMigration(batchId: 0, batchSize: 2, batchIndex: 1)),
      false,
    );
    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 0, batchIndex: 0)),
      false,
    );
    expect(
      tracker.record(_testMigration(batchId: 42, batchSize: 2, batchIndex: 2)),
      false,
    );
  });

  test('classifies Google Authenticator QR payloads from images', () {
    final qrCode = _testGoogleAuthQrCode(_testSecret());

    final result = parseQrImportPayload(qrCode);

    expect(result.code, isNull);
    expect(result.googleAuthCodes, hasLength(2));
    expect(result.googleAuthCodes![0].issuer, 'GitHub');
    expect(result.googleAuthMigration?.batchSize, 0);
  });

  test('classifies standard OTP QR payloads from images', () {
    const qrCode =
        'otpauth://totp/GitHub:testdata@ente.io?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';

    final result = parseQrImportPayload(qrCode);

    expect(result.googleAuthCodes, isNull);
    expect(result.code?.issuer, 'GitHub');
    expect(result.code?.account, 'testdata@ente.io');
  });
}

Uint8List _testSecret() {
  return Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
}

String _testGoogleAuthQrCode(
  Uint8List secret, {
  int batchId = 0,
  int batchSize = 0,
  int batchIndex = 0,
}) {
  final payload = MigrationPayload()
    ..batchId = batchId
    ..batchSize = batchSize
    ..batchIndex = batchIndex
    ..otpParameters.add(
      MigrationPayload_OtpParameters()
        ..issuer = 'GitHub'
        ..name = 'testdata@ente.io'
        ..secret = secret
        ..algorithm = MigrationPayload_Algorithm.ALGORITHM_SHA256
        ..digits = MigrationPayload_DigitCount.DIGIT_COUNT_EIGHT
        ..type = MigrationPayload_OtpType.OTP_TYPE_TOTP,
    )
    ..otpParameters.add(
      MigrationPayload_OtpParameters()
        ..issuer = 'Example'
        ..name = 'counter@example.com'
        ..secret = secret
        ..algorithm = MigrationPayload_Algorithm.ALGORITHM_SHA1
        ..digits = MigrationPayload_DigitCount.DIGIT_COUNT_SIX
        ..type = MigrationPayload_OtpType.OTP_TYPE_HOTP
        ..counter = Int64(42),
    );
  return '$kGoogleAuthExportPrefix${Uri.encodeComponent(base64Encode(payload.writeToBuffer()))}';
}

GoogleAuthMigration _testMigration({
  required int batchId,
  required int batchSize,
  required int batchIndex,
}) {
  return GoogleAuthMigration(
    codes: const [],
    batchId: batchId,
    batchSize: batchSize,
    batchIndex: batchIndex,
  );
}
