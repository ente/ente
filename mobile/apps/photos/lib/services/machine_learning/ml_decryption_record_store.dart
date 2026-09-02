import "package:logging/logging.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class MlDecryptionRecordStore {
  static const _preferenceKey = "ml_decryption_record_file_ids";

  final SharedPreferences _preferences;
  final Lock _lock = Lock();
  final Logger _logger = Logger("MlDecryptionRecordStore");

  MlDecryptionRecordStore(this._preferences);

  List<int> get fileIDs {
    final result = <int>{};
    for (final value
        in _preferences.getStringList(_preferenceKey) ?? const []) {
      final fileID = int.tryParse(value);
      if (fileID != null) {
        result.add(fileID);
      }
    }
    return result.toList()..sort();
  }

  int get count => fileIDs.length;

  Future<void> add(int fileID) async {
    await _lock.synchronized(() async {
      final updatedFileIDs = fileIDs.toSet();
      if (!updatedFileIDs.add(fileID)) {
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
    if (fileIDsToRemove.isEmpty) return;
    await _lock.synchronized(() async {
      final updatedFileIDs = this.fileIDs.toSet();
      final previousCount = updatedFileIDs.length;
      updatedFileIDs.removeAll(fileIDsToRemove);
      if (updatedFileIDs.length == previousCount) {
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
