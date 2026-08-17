import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/ui/common/touch_cross_detector.dart";
import "package:photos/ui/viewer/gallery/state/gallery_swipe_helper.dart";

class SwipeSelectableFileWidget extends StatefulWidget {
  final Widget child;
  final EnteFile file;
  final SelectedFiles? selectedFiles;
  final Function(int? pointerId, bool isInside)? onPointerStateChanged;

  const SwipeSelectableFileWidget({
    super.key,
    required this.child,
    required this.file,
    required this.selectedFiles,
    this.onPointerStateChanged,
  });

  @override
  State<SwipeSelectableFileWidget> createState() =>
      _SwipeSelectableFileWidgetState();
}

class _SwipeSelectableFileWidgetState extends State<SwipeSelectableFileWidget> {
  bool _isPointerInside = false;

  @override
  Widget build(BuildContext context) {
    final swipeHelper = GallerySwipeHelper.of(context);
    final swipeActiveNotifier = GallerySwipeHelper.swipeActiveNotifierOf(
      context,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: swipeActiveNotifier ?? ValueNotifier(false),
      builder: (context, isSwipeActive, child) {
        if (isSwipeActive &&
            _isPointerInside &&
            swipeHelper != null &&
            !swipeHelper.isActive &&
            widget.selectedFiles != null &&
            widget.selectedFiles!.files.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                isSwipeActive &&
                _isPointerInside &&
                !swipeHelper.isActive) {
              swipeHelper.startSelection(widget.file);
            }
          });
        }

        return TouchCrossDetector(
          onPointerDown: (event) {
            _isPointerInside = true;
            widget.onPointerStateChanged?.call(event.pointer, true);
          },
          onHover: (event) {
            _isPointerInside = true;
            if (swipeActiveNotifier?.value == true &&
                swipeHelper != null &&
                !swipeHelper.isActive &&
                widget.selectedFiles != null &&
                widget.selectedFiles!.files.isNotEmpty) {
              swipeHelper.startSelection(widget.file);
            }
          },
          onEnter: (event) {
            _isPointerInside = true;
            widget.onPointerStateChanged?.call(event.pointer, true);
            if ((swipeActiveNotifier?.value == true ||
                    swipeHelper?.isActive == true) &&
                swipeHelper != null) {
              if (!swipeHelper.isActive) {
                swipeHelper.startSelection(widget.file);
              } else {
                swipeHelper.updateSelection(widget.file);
              }
            }
          },
          onExit: (event) {
            _isPointerInside = false;
            widget.onPointerStateChanged?.call(null, false);
          },
          child: widget.child,
        );
      },
    );
  }
}
