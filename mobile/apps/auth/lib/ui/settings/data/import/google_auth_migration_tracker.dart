import 'package:ente_auth/ui/settings/data/import/google_auth_qr_parser.dart';

class GoogleAuthMigrationTracker {
  final Map<(int, int), Set<int>> _importedBatchIndices = {};

  bool record(GoogleAuthMigration migration) {
    if (!migration.hasValidBatchMetadata) return false;
    if (migration.batchSize == 1) return true;
    if (migration.batchId == 0) return false;

    final key = (migration.batchId, migration.batchSize);
    final importedIndices = _importedBatchIndices.putIfAbsent(
      key,
      () => <int>{},
    );
    importedIndices.add(migration.batchIndex);
    if (importedIndices.length != migration.batchSize) return false;

    _importedBatchIndices.remove(key);
    return true;
  }
}
