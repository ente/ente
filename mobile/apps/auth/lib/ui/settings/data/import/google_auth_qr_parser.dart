import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';

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
  return runRustImport(() {
    final migration = rust.parseGoogleMigration(input: qrCodeData);
    return GoogleAuthMigration(
      codes: migration.codes.map(importCode).toList(growable: false),
      batchId: migration.batchId,
      batchSize: migration.batchSize,
      batchIndex: migration.batchIndex,
    );
  });
}
