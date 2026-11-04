import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:locker/services/files/sync/models/file.dart';

class SelectedFiles extends ChangeNotifier {
  final files = <EnteFile>{};

  void toggleSelection(EnteFile fileToToggle) {
    final EnteFile? alreadySelected = files.firstWhereOrNull(
      (element) => _isMatch(fileToToggle, element),
    );
    if (alreadySelected != null) {
      files.remove(alreadySelected);
    } else {
      files.add(fileToToggle);
    }
    notifyListeners();
  }

  void selectAll(Set<EnteFile> filesToSelect) {
    files.addAll(filesToSelect);
    notifyListeners();
  }

  void retainSelection(Iterable<EnteFile> visibleFiles) {
    if (files.isEmpty) return;
    final selected = visibleFiles
        .where((file) => file.uploadedFileID != null && files.contains(file))
        .toSet();
    files
      ..clear()
      ..addAll(selected);
    notifyListeners();
  }

  bool isFileSelected(EnteFile file) {
    final EnteFile? alreadySelected = files.firstWhereOrNull(
      (element) => _isMatch(file, element),
    );
    return alreadySelected != null;
  }

  bool _isMatch(EnteFile first, EnteFile second) {
    if (first.uploadedFileID != null && second.uploadedFileID != null) {
      return first.uploadedFileID == second.uploadedFileID;
    }
    return false;
  }

  void clearAll({bool fireEvent = true}) {
    files.clear();
    notifyListeners();
  }

  bool get hasSelections => files.isNotEmpty;

  int get count => files.length;
}
