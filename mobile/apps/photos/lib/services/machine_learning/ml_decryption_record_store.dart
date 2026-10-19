import "package:logging/logging.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class MlDecryptionRecordStore {
  static const _preferenceKey = "ml_decryption_record_file_ids";
  static const maxRecords = 100;

  final SharedPreferences _preferences;
  final Lock _lock = Lock();
  final Logger _logger = Logger("MlDecryptionRecordStore");

  MlDecryptionRecordStore(this._preferences);

  List<int> get fileIDs {
    final result = <int>{};
    final values = _preferences.get(_preferenceKey) as List<Object?>?;
    for (final value in values?.take(maxRecords) ?? const []) {
      final fileID = value is String ? int.tryParse(value) : null;
      if (fileID != null) {
        result.add(fileID);
      }
    }
    return result.toList()..sort();
  }

  int get count => fileIDs.length;

  bool get _hasOversizedRecords =>
      ((_preferences.get(_preferenceKey) as List<Object?>?)?.length ?? 0) >
      maxRecords;

  Future<void> add(int fileID) async {
    await _lock.synchronized(() async {
      final updatedFileIDs = fileIDs.toSet();
      final added =
          updatedFileIDs.length < maxRecords && updatedFileIDs.add(fileID);
      if (!added && !_hasOversizedRecords) {
        return;
      }
      await _store(
        updatedFileIDs,
        "Failed to store ML decryption record for fileID $fileID",
      );
    });
  }

  Future<void> removeAll(Iterable<int> fileIDs) async {
    final fileIDsToRemove = fileIDs.toSet();
    await _lock.synchronized(() async {
      final updatedFileIDs = this.fileIDs.toSet();
      final previousCount = updatedFileIDs.length;
      updatedFileIDs.removeAll(fileIDsToRemove);
      if (updatedFileIDs.length == previousCount && !_hasOversizedRecords) {
        return;
      }
      await _store(updatedFileIDs, "Failed to prune ML decryption records");
    });
  }

  Future<void> _store(Set<int> fileIDs, String failureMessage) async {
    final values = fileIDs.toList()..sort();
    try {
      final stored = await _preferences.setStringList(
        _preferenceKey,
        values.map((id) => id.toString()).toList(),
      );
      if (!stored) {
        _logger.warning(failureMessage);
      }
    } catch (error, stackTrace) {
      _logger.warning(failureMessage, error, stackTrace);
    }
  }

  void logFileIDs() {
    _logger.info("ML decryption record fileIDs: $fileIDs");
  }
}
