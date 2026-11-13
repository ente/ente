import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/models/selected_files.dart";

// Gallery and FileSelectionOverlayBar must share this ancestor for select-all.
// ignore: must_be_immutable
class SelectionState extends InheritedWidget {
  final SelectedFiles selectedFiles;

  const SelectionState({
    super.key,
    required this.selectedFiles,
    required super.child,
  });

  static SelectionState? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SelectionState>();
  }

  static SelectionState? of(BuildContext context) {
    final SelectionState? result = maybeOf(context);
    if (result == null) {
      Logger("SelectionState").warning(
        "No SelectionState found in context. Ignore this if file selection is disabled in the gallery used.",
      );
    }
    return result;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return false;
  }
}
