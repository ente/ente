import "dart:collection";

import "package:photos/core/constants.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";

class DevicePickerSelectedFiles extends SelectedFiles {
  final _assetIDs = Expando<String>();
  late final _files = LinkedHashSet<EnteFile>(
    equals: (first, second) => assetID(first) == assetID(second),
    hashCode: (file) => assetID(file).hashCode,
  );
  bool locked = false;

  @override
  Set<EnteFile> get files => _files;

  void register(EnteFile file, String id) => _assetIDs[file] ??= id;

  String? assetID(EnteFile file) => _assetIDs[file] ?? file.localID;

  @override
  bool isFileSelected(EnteFile file) => files.contains(file);

  @override
  void toggleSelection(EnteFile file) {
    if (locked || file is DummyFile) return;
    if (isFileSelected(file)) {
      unSelectAll({file});
    } else {
      selectAll({file});
    }
  }

  @override
  void toggleGroupSelection(Set<EnteFile> filesToToggle) {
    if (locked) return;
    if (files.length == maxPickAssetLimit &&
        filesToToggle.any(isFileSelected)) {
      unSelectAll(filesToToggle);
    } else {
      super.toggleGroupSelection(filesToToggle);
    }
  }

  @override
  void selectAll(Set<EnteFile> filesToSelect) {
    if (locked) return;
    final remaining = maxPickAssetLimit - files.length;
    final additions = filesToSelect
        .where((file) => file is! DummyFile && !files.contains(file))
        .take(remaining)
        .toSet();
    if (additions.isNotEmpty) super.selectAll(additions);
  }

  @override
  void unSelectAll(Set<EnteFile> filesToUnselect, {bool skipNotify = false}) {
    if (!locked) {
      super.unSelectAll(
        filesToUnselect.map(files.lookup).nonNulls.toSet(),
        skipNotify: skipNotify,
      );
    }
  }

  @override
  void clearAll({bool fireEvent = true}) {
    if (!locked) super.clearAll(fireEvent: false);
  }
}
