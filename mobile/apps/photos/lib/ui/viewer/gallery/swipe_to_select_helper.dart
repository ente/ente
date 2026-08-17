import 'dart:math';

import 'package:flutter/services.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/selected_files.dart';

class SwipeToSelectHelper {
  final List<EnteFile> allFiles;
  final SelectedFiles selectedFiles;

  SwipeToSelectHelper({required this.allFiles, required this.selectedFiles}) {
    selectedFiles.addListener(_onSelectionChanged);
  }

  int? _fromIndex;
  int? _lastToIndex;
  bool? _selecting;

  // isActive can be stale; use GallerySwipeHelper's notifier to track the
  // pointer gesture.
  bool get isActive => _fromIndex != null;

  void startSelection(EnteFile file, {bool? forceSelecting}) {
    final index = allFiles.indexOf(file);
    if (index == -1) return;

    _fromIndex = index;
    _lastToIndex = index;
    _selecting = forceSelecting ?? !selectedFiles.isFileSelected(file);

    if (_selecting == true) {
      selectedFiles.selectAll({file});
      HapticFeedback.selectionClick();
    } else {
      selectedFiles.unSelectAll({file});
      HapticFeedback.selectionClick();
    }
  }

  void updateSelection(EnteFile file) {
    if (_fromIndex == null) return;

    final toIndex = allFiles.indexOf(file);
    if (toIndex == -1 || toIndex == _lastToIndex) return;

    _toggleSelectionToIndex(toIndex);
    _lastToIndex = toIndex;
  }

  void endSelection() {
    _fromIndex = null;
    _lastToIndex = null;
    _selecting = null;
  }

  // Reversing the drag undoes changes outside the new start-to-pointer range.
  void _toggleSelectionToIndex(int toIndex) {
    if (_fromIndex == null || _lastToIndex == null || _selecting == null) {
      return;
    }

    final fromIndex = _fromIndex!;
    final lastToIndex = _lastToIndex!;
    final selecting = _selecting!;

    Set<EnteFile> getRange(int start, int end) {
      if (start < end && start >= 0 && end <= allFiles.length) {
        return allFiles.getRange(start, end).toSet();
      }
      return {};
    }

    if (selecting) {
      if (toIndex <= fromIndex) {
        if (toIndex < lastToIndex) {
          final itemsToAdd = getRange(toIndex, min(fromIndex, lastToIndex));
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
          if (fromIndex < lastToIndex) {
            final itemsToRemove = getRange(fromIndex + 1, lastToIndex + 1);
            if (itemsToRemove.isNotEmpty) {
              selectedFiles.unSelectAll(itemsToRemove);
              HapticFeedback.selectionClick();
            }
          }
        } else if (lastToIndex < toIndex) {
          final itemsToRemove = getRange(lastToIndex, toIndex);
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
        }
      } else if (fromIndex < toIndex) {
        if (lastToIndex < toIndex) {
          final itemsToAdd = getRange(max(fromIndex, lastToIndex), toIndex + 1);
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
          if (lastToIndex < fromIndex) {
            final itemsToRemove = getRange(lastToIndex, fromIndex);
            if (itemsToRemove.isNotEmpty) {
              selectedFiles.unSelectAll(itemsToRemove);
              HapticFeedback.selectionClick();
            }
          }
        } else if (toIndex < lastToIndex) {
          final itemsToRemove = getRange(toIndex + 1, lastToIndex + 1);
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
        }
      }
    } else {
      if (toIndex <= fromIndex) {
        if (toIndex < lastToIndex) {
          final itemsToRemove = getRange(toIndex, min(fromIndex, lastToIndex));
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
          if (fromIndex < lastToIndex) {
            final itemsToAdd = getRange(fromIndex + 1, lastToIndex + 1);
            if (itemsToAdd.isNotEmpty) {
              selectedFiles.selectAll(itemsToAdd);
              HapticFeedback.selectionClick();
            }
          }
        } else if (lastToIndex < toIndex) {
          final itemsToAdd = getRange(lastToIndex, toIndex);
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
        }
      } else if (fromIndex < toIndex) {
        if (lastToIndex < toIndex) {
          final itemsToRemove = getRange(
            max(fromIndex, lastToIndex),
            toIndex + 1,
          );
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
          if (lastToIndex < fromIndex) {
            final itemsToAdd = getRange(lastToIndex, fromIndex);
            if (itemsToAdd.isNotEmpty) {
              selectedFiles.selectAll(itemsToAdd);
              HapticFeedback.selectionClick();
            }
          }
        } else if (toIndex < lastToIndex) {
          final itemsToAdd = getRange(toIndex + 1, lastToIndex + 1);
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
        }
      }
    }
  }

  void reset() {
    endSelection();
  }

  void _onSelectionChanged() {
    if (selectedFiles.files.isEmpty && isActive) {
      reset();
    }
  }

  void dispose() {
    selectedFiles.removeListener(_onSelectionChanged);
  }
}
