import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class ReviewGridTile extends StatelessWidget {
  const ReviewGridTile({
    required this.file,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    super.key,
  });

  static const _selectedInsetFraction = 0.05;
  static const _tickSize = 20.0;

  final EnteFile file;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.standard;
    return Semantics(
      button: true,
      selected: selected,
      label: file.displayName,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedPadding(
            padding: EdgeInsets.all(
              selected ? constraints.maxWidth * _selectedInsetFraction : 0,
            ),
            duration: duration,
            curve: Curves.easeOutCubic,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: selected ? Radii.lg : Radii.xs),
              duration: duration,
              curve: Curves.easeOutCubic,
              builder: (context, radius, child) => ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: child,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ThumbnailWidget(
                    file,
                    key: Key("review_grid_${file.tag}"),
                    diskLoadDeferDuration:
                        galleryThumbnailDiskLoadDeferDuration,
                    serverLoadDeferDuration:
                        galleryThumbnailServerLoadDeferDuration,
                    shouldShowSyncStatus: false,
                    shouldShowLivePhotoOverlay: true,
                    shouldShowVideoDuration: true,
                    placeholderColor: colors.fillDark,
                  ),
                  Positioned(
                    top: Spacing.sm,
                    right: Spacing.sm,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: duration,
                      child: SelectAllStatusIcon(
                        isSelected: true,
                        size: _tickSize,
                        selectedFillColor: colors.primary,
                        selectedTickColor: colors.specialWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
