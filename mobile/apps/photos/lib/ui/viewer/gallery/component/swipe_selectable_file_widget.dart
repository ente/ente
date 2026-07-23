import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/ui/common/touch_cross_detector.dart";
import "package:photos/ui/viewer/gallery/state/gallery_swipe_helper.dart";

/// A wrapper widget that adds swipe-to-select functionality to a file widget.
///
/// This widget encapsulates all the swipe selection logic, keeping the
/// GalleryFileWidget clean and focused on file display.
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
        // Check if we need to start selection when swipe becomes active
        if (isSwipeActive &&
            _isPointerInside &&
            swipeHelper != null &&
            !swipeHelper.isActive &&
            widget.selectedFiles != null &&
            widget.selectedFiles!.files.isNotEmpty) {
          // Schedule the selection to happen after the current build
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
            // If files are already selected and swipe is not active, prepare for potential swipe
            // The actual selection will start when horizontal movement is detected
          },
          onHover: (event) {
            _isPointerInside = true;
            // Handle the initial file selection when swipe becomes active
            // This is mainly for horizontal swipe detection since vertical after long press
            // is already handled by swipeHelper being active
            if (swipeActiveNotifier?.value == true &&
                swipeHelper != null &&
                !swipeHelper.isActive &&
                widget.selectedFiles != null &&
                widget.selectedFiles!.files.isNotEmpty) {
              // Start selection for the first file when horizontal swipe is detected
              swipeHelper.startSelection(widget.file);
            }
          },
          onEnter: (event) {
            _isPointerInside = true;
            widget.onPointerStateChanged?.call(event.pointer, true);
            // Check if swipe is active (either from horizontal swipe or from long press)
            if ((swipeActiveNotifier?.value == true ||
                    swipeHelper?.isActive == true) &&
                swipeHelper != null) {
              if (!swipeHelper.isActive) {
                // Start selection when first entering a file during active swipe
                swipeHelper.startSelection(widget.file);
              } else {
                // Update selection for subsequent files
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
