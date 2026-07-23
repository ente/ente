import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/clear_selections_event.dart';
import 'package:photos/models/file/dummy_file.dart';
import 'package:photos/models/file/file.dart';

/// Manages the set of currently selected files in the gallery.
///
/// This class serves as the single source of truth for file selection state
/// and automatically filters out [DummyFile] instances from all selection
/// operations. Dummy files are used for gallery layout purposes and should
/// never be selected.
///
/// All selection methods ([toggleSelection], [selectAll],
/// [unSelectAll], [toggleGroupSelection]) automatically exclude dummy files.
/// Calling code does not need to check for or filter out dummy files before
/// calling these methods.
class SelectedFiles extends ChangeNotifier {
  final files = <EnteFile>{};

  ///This variable is used to track the files that were involved in last selection
  ///operation (select/unselect). Each [LazyGridView] checks this variable on
  ///change in [SelectedFiles] to see if any of it's files were involved in last
  ///select/unselect operation. If yes, then it will rebuild itself.
  final lastSelectionOperationFiles = <EnteFile>{};

  void toggleSelection(EnteFile fileToToggle) {
    // Skip dummy files - they should never be selected
    if (fileToToggle is DummyFile) {
      return;
    }
    // To handle the cases, where the file might have changed due to upload
    // or any other update, using file.generatedID to track if this file was already
    // selected or not
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
    // Filter out dummy files before processing
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
    // Filter out dummy files before adding to selection
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
    // Filter out dummy files before adding to lastSelectionOperationFiles
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

  /// Removes [file] from internal sets before a mutation that changes fields
  /// participating in `==`/`hashCode`, then re-adds it after the mutation.
  ///
  /// Call this around in-place mutations (e.g. [EnteFile.applyUploadedData])
  /// so that the hash-based sets stay consistent.
  void mutateFile(EnteFile file, void Function() mutate) {
    final wasInFiles = files.remove(file);
    final wasInLastOp = lastSelectionOperationFiles.remove(file);
    mutate();
    if (wasInFiles) files.add(file);
    if (wasInLastOp) lastSelectionOperationFiles.add(file);
    if (wasInFiles || wasInLastOp) notifyListeners();
  }

  ///Retains only the files that are present in the [filesToRetain] set in
  ///[files]. Takes the intersection of the two sets.
  void retainFiles(Set<EnteFile> filesToRetain) {
    files.retainAll(filesToRetain);
    notifyListeners();
  }

  ///Replaces the current selection with [filesToSelect] in a single update.
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
