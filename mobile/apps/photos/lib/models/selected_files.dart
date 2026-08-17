import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/clear_selections_event.dart';
import 'package:photos/models/file/dummy_file.dart';
import 'package:photos/models/file/file.dart';

class SelectedFiles extends ChangeNotifier {
  final files = <EnteFile>{};
  final lastSelectionOperationFiles = <EnteFile>{};

  void toggleSelection(EnteFile fileToToggle) {
    if (fileToToggle is DummyFile) {
      return;
    }
    final EnteFile? alreadySelected = files.firstWhereOrNull(
      (element) => _isMatch(fileToToggle, element),
    );
    if (alreadySelected != null) {
      files.remove(alreadySelected);
    } else {
      files.add(fileToToggle);
    }
    lastSelectionOperationFiles.clear();
    lastSelectionOperationFiles.add(fileToToggle);
    notifyListeners();
  }

  void toggleGroupSelection(Set<EnteFile> filesToToggle) {
    final nonDummyFiles = filesToToggle
        .where((file) => file is! DummyFile)
        .toSet();
    if (nonDummyFiles.isEmpty) {
      return;
    }
    if (files.containsAll(nonDummyFiles)) {
      unSelectAll(nonDummyFiles);
    } else {
      selectAll(nonDummyFiles);
    }
  }

  void selectAll(Set<EnteFile> filesToSelect) {
    final nonDummyFiles = filesToSelect
        .where((file) => file is! DummyFile)
        .toSet();
    files.addAll(nonDummyFiles);
    lastSelectionOperationFiles.clear();
    lastSelectionOperationFiles.addAll(nonDummyFiles);
    notifyListeners();
  }

  void unSelectAll(Set<EnteFile> filesToUnselect, {bool skipNotify = false}) {
    files.removeWhere((file) => filesToUnselect.contains(file));
    lastSelectionOperationFiles.clear();
    lastSelectionOperationFiles.addAll(
      filesToUnselect.where((file) => file is! DummyFile),
    );
    if (!skipNotify) {
      notifyListeners();
    }
  }

  bool isFileSelected(EnteFile file) {
    final EnteFile? alreadySelected = files.firstWhereOrNull(
      (element) => _isMatch(file, element),
    );
    return alreadySelected != null;
  }

  bool isPartOfLastSelected(EnteFile file) {
    final EnteFile? matchedFile = lastSelectionOperationFiles.firstWhereOrNull(
      (element) => _isMatch(file, element),
    );
    return matchedFile != null;
  }

  bool _isMatch(EnteFile first, EnteFile second) {
    if (first.generatedID != null && second.generatedID != null) {
      if (first.generatedID == second.generatedID) {
        return true;
      }
    } else if (first.uploadedFileID != null && second.uploadedFileID != null) {
      return first.uploadedFileID == second.uploadedFileID;
    }
    return false;
  }

  void clearAll({bool fireEvent = true}) {
    if (fireEvent) {
      Bus.instance.fire(ClearSelectionsEvent());
    }
    lastSelectionOperationFiles.addAll(files);
    files.clear();
    notifyListeners();
  }

  // Remove before mutating fields used by == or hashCode, then reinsert.
  void mutateFile(EnteFile file, void Function() mutate) {
    final wasInFiles = files.remove(file);
    final wasInLastOp = lastSelectionOperationFiles.remove(file);
    mutate();
    if (wasInFiles) files.add(file);
    if (wasInLastOp) lastSelectionOperationFiles.add(file);
    if (wasInFiles || wasInLastOp) notifyListeners();
  }

  void retainFiles(Set<EnteFile> filesToRetain) {
    files.retainAll(filesToRetain);
    notifyListeners();
  }

  void replaceSelection(Set<EnteFile> filesToSelect) {
    final nonDummyFiles = filesToSelect
        .where((file) => file is! DummyFile)
        .toSet();
    lastSelectionOperationFiles.clear();
    lastSelectionOperationFiles.addAll(files);
    files
      ..clear()
      ..addAll(nonDummyFiles);
    lastSelectionOperationFiles.addAll(nonDummyFiles);
    notifyListeners();
  }
}
