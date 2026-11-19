import 'dart:collection';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/clear_selections_event.dart';
import 'package:photos/models/file/dummy_file.dart';
import 'package:photos/models/file/file.dart';

class SelectedFiles extends ChangeNotifier {
  SelectedFiles({this.dedupeByUploadID = false})
    : files = dedupeByUploadID ? _IndexedSelectionFiles() : <EnteFile>{};

  final bool dedupeByUploadID;
  final Set<EnteFile> files;
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
    final nonDummyFiles = _selectableFiles(filesToToggle);
    if (nonDummyFiles.isEmpty) {
      return;
    }
    if (dedupeByUploadID
        ? nonDummyFiles.every(isFileSelected)
        : files.containsAll(nonDummyFiles)) {
      unSelectAll(nonDummyFiles);
    } else {
      selectAll(nonDummyFiles);
    }
  }

  void selectAll(Set<EnteFile> filesToSelect) {
    final nonDummyFiles = _selectableFiles(filesToSelect);
    if (dedupeByUploadID) nonDummyFiles.removeWhere(isFileSelected);
    files.addAll(nonDummyFiles);
    lastSelectionOperationFiles.clear();
    lastSelectionOperationFiles.addAll(nonDummyFiles);
    notifyListeners();
  }

  void unSelectAll(Set<EnteFile> filesToUnselect, {bool skipNotify = false}) {
    final identities = dedupeByUploadID
        ? (_IndexedSelectionFiles()..addAll(filesToUnselect))
        : null;
    files.removeWhere(
      (file) => identities != null
          ? identities.matches(file)
          : filesToUnselect.contains(file),
    );
    lastSelectionOperationFiles.clear();
    lastSelectionOperationFiles.addAll(
      filesToUnselect.where((file) => file is! DummyFile),
    );
    if (!skipNotify) {
      notifyListeners();
    }
  }

  bool isFileSelected(EnteFile file) {
    final selected = files;
    if (selected is _IndexedSelectionFiles) return selected.matches(file);
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
    if (dedupeByUploadID) {
      if (first.uploadedFileID != null && second.uploadedFileID != null) {
        return first.uploadedFileID == second.uploadedFileID;
      }
      if (first.localID != null && first.localID == second.localID) {
        return true;
      }
    }
    if (first.generatedID != null && second.generatedID != null) {
      if (first.generatedID == second.generatedID) {
        return true;
      }
    } else if (first.uploadedFileID != null && second.uploadedFileID != null) {
      return first.uploadedFileID == second.uploadedFileID;
    } else if (first.localID != null && second.localID != null) {
      return first.localID == second.localID;
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
    if (dedupeByUploadID) {
      final identities = _IndexedSelectionFiles()..addAll(filesToRetain);
      files.removeWhere((file) => !identities.matches(file));
    } else {
      files.retainAll(filesToRetain);
    }
    notifyListeners();
  }

  void replaceSelection(Set<EnteFile> filesToSelect) {
    final nonDummyFiles = _selectableFiles(filesToSelect);
    lastSelectionOperationFiles.clear();
    lastSelectionOperationFiles.addAll(files);
    files
      ..clear()
      ..addAll(nonDummyFiles);
    lastSelectionOperationFiles.addAll(nonDummyFiles);
    notifyListeners();
  }

  Set<EnteFile> _selectableFiles(Iterable<EnteFile> candidates) {
    if (!dedupeByUploadID) {
      return candidates.where((file) => file is! DummyFile).toSet();
    }
    final result = _IndexedSelectionFiles();
    for (final file in candidates) {
      if (file is! DummyFile && !result.matches(file)) {
        result.add(file);
      }
    }
    return result;
  }
}

class _IndexedSelectionFiles extends SetBase<EnteFile> {
  final _files = <EnteFile>{};
  final _uploaded = <int, int>{};
  final _local = <String, int>{};
  final _generated = <int, int>{};
  final _unuploadedLocal = <String, int>{};
  final _unuploadedGenerated = <int, int>{};

  bool matches(EnteFile file) {
    final uploadedID = file.uploadedFileID;
    if (uploadedID != null && _uploaded.containsKey(uploadedID)) return true;
    final local = uploadedID == null ? _local : _unuploadedLocal;
    final generated = uploadedID == null ? _generated : _unuploadedGenerated;
    return (file.localID != null && local.containsKey(file.localID)) ||
        (file.generatedID != null && generated.containsKey(file.generatedID));
  }

  @override
  bool add(EnteFile file) {
    if (!_files.add(file)) return false;
    _updateIdentities(file, 1);
    return true;
  }

  @override
  bool remove(Object? value) {
    if (value is! EnteFile || !_files.remove(value)) return false;
    _updateIdentities(value, -1);
    return true;
  }

  void _updateIdentities(EnteFile file, int change) {
    _updateCount(_uploaded, file.uploadedFileID, change);
    _updateCount(_local, file.localID, change);
    _updateCount(_generated, file.generatedID, change);
    if (file.uploadedFileID == null) {
      _updateCount(_unuploadedLocal, file.localID, change);
      _updateCount(_unuploadedGenerated, file.generatedID, change);
    }
  }

  void _updateCount<T>(Map<T, int> counts, T? identity, int change) {
    if (identity == null) return;
    final count = (counts[identity] ?? 0) + change;
    if (count == 0) {
      counts.remove(identity);
    } else {
      counts[identity] = count;
    }
  }

  @override
  void clear() {
    _files.clear();
    _uploaded.clear();
    _local.clear();
    _generated.clear();
    _unuploadedLocal.clear();
    _unuploadedGenerated.clear();
  }

  @override
  bool contains(Object? element) => _files.contains(element);

  @override
  EnteFile? lookup(Object? element) => _files.lookup(element);

  @override
  Iterator<EnteFile> get iterator => _files.iterator;

  @override
  int get length => _files.length;

  @override
  EnteFile get first => _files.first;

  @override
  EnteFile get last => _files.last;

  @override
  Set<EnteFile> toSet() => _files.toSet();
}
