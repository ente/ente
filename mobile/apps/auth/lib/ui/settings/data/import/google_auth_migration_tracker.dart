import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_qr_parser.dart';

class GoogleAuthMigrationTracker {
  int? _batchId;
  int? _batchSize;
  final Map<int, List<Code>> _batches = {};

  int get receivedBatchCount => _batches.length;
  int get batchSize => _batchSize ?? 0;

  List<Code>? add(GoogleAuthMigration migration) {
    if (_batchId != null &&
        (_batchId != migration.batchId || _batchSize != migration.batchSize)) {
      throw const FormatException(
        'QR code belongs to a different Google Authenticator export',
      );
    }
    if (migration.batchSize == 0) {
      _reset();
      return migration.codes;
    }
    if (!migration.hasValidBatchMetadata) {
      throw const FormatException('Invalid Google Authenticator export batch');
    }
    if (migration.batchSize == 1) {
      _reset();
      return migration.codes;
    }

    _batchId = migration.batchId;
    _batchSize = migration.batchSize;
    _batches.putIfAbsent(migration.batchIndex, () => migration.codes);
    if (_batches.length != migration.batchSize) return null;

    final codes = [
      for (var index = 0; index < migration.batchSize; index++)
        ..._batches[index]!,
    ];
    _reset();
    return codes;
  }

  void _reset() {
    _batchId = null;
    _batchSize = null;
    _batches.clear();
  }
}
