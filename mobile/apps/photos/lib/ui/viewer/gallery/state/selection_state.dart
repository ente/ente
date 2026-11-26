import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";

// Gallery and FileSelectionOverlayBar must share this ancestor for select-all.
// ignore: must_be_immutable
class SelectionState extends InheritedWidget {
  final SelectedFiles selectedFiles;
  final void Function(Route<dynamic>, List<EnteFile>)? onPreview;
  final bool respectSystemGestureInsets;

  const SelectionState({
    super.key,
    required this.selectedFiles,
    this.onPreview,
    this.respectSystemGestureInsets = false,
    required super.child,
  });

  SelectionState.preview({
    super.key,
    required this.selectedFiles,
    required List<EnteFile> files,
    required Widget child,
    this.onPreview,
  }) : respectSystemGestureInsets = false,
       super(
         child: onPreview == null
             ? child
             : Builder(
                 builder: (context) {
                   onPreview(ModalRoute.of(context)!, files);
                   return child;
                 },
               ),
       );

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
