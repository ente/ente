import 'dart:math';

import 'package:flutter/services.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/selected_files.dart';

/// Helper class to manage swipe-to-select gesture logic.
///
/// This class implements an efficient range selection algorithm that:
/// - Maintains a continuous selection from anchor to current position
/// - Only modifies the delta between previous and current position
/// - Supports bidirectional dragging
/// - Has two modes: adding (from unselected) or removing (from selected)
class SwipeToSelectHelper {
  final List<EnteFile> allFiles;
  final SelectedFiles selectedFiles;

  SwipeToSelectHelper({required this.allFiles, required this.selectedFiles}) {
    selectedFiles.addListener(_onSelectionChanged);
  }

  int? _fromIndex; // Anchor point (where swipe started)
  int? _lastToIndex; // Previous position during drag
  bool? _selecting; // true = adding, false = removing

  /// Whether a swipe gesture is currently active
  /// Note: There is some edge case where this isn't perfectly accurate, so
  /// _swipeActiveNotifier was added to GallerySwipeHelper for more reliable
  /// tracking. Not removing this since this is still useful for some logic.
  bool get isActive => _fromIndex != null;

  /// Start a selection gesture at the given file
  /// [forceSelecting] - if true, forces adding mode regardless of file's current state
  void startSelection(EnteFile file, {bool? forceSelecting}) {
    final index = allFiles.indexOf(file);
    if (index == -1) return;

    _fromIndex = index;
    _lastToIndex = index;
    // Use forced mode if provided, otherwise determine based on initial file's selection state
    _selecting = forceSelecting ?? !selectedFiles.isFileSelected(file);

    // Immediately select/deselect the starting file based on mode
    if (_selecting == true) {
      selectedFiles.selectAll({file});
      HapticFeedback.selectionClick();
    } else {
      selectedFiles.unSelectAll({file});
      HapticFeedback.selectionClick();
    }
  }

  /// Update selection as the pointer moves to a new file
  void updateSelection(EnteFile file) {
    if (_fromIndex == null) return;

    final toIndex = allFiles.indexOf(file);
    if (toIndex == -1 || toIndex == _lastToIndex) return;

    _toggleSelectionToIndex(toIndex);
    _lastToIndex = toIndex;
  }

  /// End the selection gesture
  void endSelection() {
    _fromIndex = null;
    _lastToIndex = null;
    _selecting = null;
  }

  /// Core algorithm that efficiently updates selection ranges
  void _toggleSelectionToIndex(int toIndex) {
    if (_fromIndex == null || _lastToIndex == null || _selecting == null) {
      return;
    }

    final fromIndex = _fromIndex!;
    final lastToIndex = _lastToIndex!;
    final selecting = _selecting!;

    // Helper function to get range of files
    Set<EnteFile> getRange(int start, int end) {
      if (start < end && start >= 0 && end <= allFiles.length) {
        return allFiles.getRange(start, end).toSet();
      }
      return {};
    }

    if (selecting) {
      // Adding mode: maintain continuous selection from fromIndex to toIndex
      if (toIndex <= fromIndex) {
        // Moving left of starting point
        if (toIndex < lastToIndex) {
          // Extending leftward
          final itemsToAdd = getRange(toIndex, min(fromIndex, lastToIndex));
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
          // Remove items to the right of start if we were previously there
          if (fromIndex < lastToIndex) {
            final itemsToRemove = getRange(fromIndex + 1, lastToIndex + 1);
            if (itemsToRemove.isNotEmpty) {
              selectedFiles.unSelectAll(itemsToRemove);
              HapticFeedback.selectionClick();
            }
          }
        } else if (lastToIndex < toIndex) {
          // Contracting from left
          final itemsToRemove = getRange(lastToIndex, toIndex);
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
        }
      } else if (fromIndex < toIndex) {
        // Moving right of starting point
        if (lastToIndex < toIndex) {
          // Extending rightward
          final itemsToAdd = getRange(max(fromIndex, lastToIndex), toIndex + 1);
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
          // Remove items to the left of start if we were previously there
          if (lastToIndex < fromIndex) {
            final itemsToRemove = getRange(lastToIndex, fromIndex);
            if (itemsToRemove.isNotEmpty) {
              selectedFiles.unSelectAll(itemsToRemove);
              HapticFeedback.selectionClick();
            }
          }
        } else if (toIndex < lastToIndex) {
          // Contracting from right
          final itemsToRemove = getRange(toIndex + 1, lastToIndex + 1);
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
        }
      }
    } else {
      // Removing mode: maintain continuous unselection from fromIndex to toIndex
      if (toIndex <= fromIndex) {
        // Moving left of starting point
        if (toIndex < lastToIndex) {
          // Extending leftward
          final itemsToRemove = getRange(toIndex, min(fromIndex, lastToIndex));
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
          // Add items back to the right of start if we were previously there
          if (fromIndex < lastToIndex) {
            final itemsToAdd = getRange(fromIndex + 1, lastToIndex + 1);
            if (itemsToAdd.isNotEmpty) {
              selectedFiles.selectAll(itemsToAdd);
              HapticFeedback.selectionClick();
            }
          }
        } else if (lastToIndex < toIndex) {
          // Contracting from left
          final itemsToAdd = getRange(lastToIndex, toIndex);
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
        }
      } else if (fromIndex < toIndex) {
        // Moving right of starting point
        if (lastToIndex < toIndex) {
          // Extending rightward
          final itemsToRemove = getRange(
            max(fromIndex, lastToIndex),
            toIndex + 1,
          );
          if (itemsToRemove.isNotEmpty) {
            selectedFiles.unSelectAll(itemsToRemove);
            HapticFeedback.selectionClick();
          }
          // Add items back to the left of start if we were previously there
          if (lastToIndex < fromIndex) {
            final itemsToAdd = getRange(lastToIndex, fromIndex);
            if (itemsToAdd.isNotEmpty) {
              selectedFiles.selectAll(itemsToAdd);
              HapticFeedback.selectionClick();
            }
          }
        } else if (toIndex < lastToIndex) {
          // Contracting from right
          final itemsToAdd = getRange(toIndex + 1, lastToIndex + 1);
          if (itemsToAdd.isNotEmpty) {
            selectedFiles.selectAll(itemsToAdd);
            HapticFeedback.selectionClick();
          }
        }
      }
    }
  }

  /// Reset the helper (e.g., when gallery files change)
  void reset() {
    endSelection();
  }

  /// Listener for selection changes
  void _onSelectionChanged() {
    // Reset swipe state when all selections are cleared
    if (selectedFiles.files.isEmpty && isActive) {
      reset();
    }
  }

  /// Clean up resources
  void dispose() {
    selectedFiles.removeListener(_onSelectionChanged);
  }
}
