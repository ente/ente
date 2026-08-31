import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";

class CollageItemWidget extends StatelessWidget {
  const CollageItemWidget(
    this.file, {
    super.key,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isSwapActive = false,
  });

  final EnteFile file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isSwapActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final shouldShowOutline = isSelected || isSwapActive;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            child: ZoomableImage(
              key: ValueKey(file.tag),
              file,
              backgroundDecoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              tagPrefix: "collage_",
              shouldCover: true,
              enableVerticalSwipeActions: false,
            ),
          ),
          if (shouldShowOutline)
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary500
                        : colorScheme.strokeMuted,
                    width: isSelected ? 3 : 2,
                  ),
                ),
              ),
            ),
          if (isSelected)
            IgnorePointer(
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colorScheme.backgroundElevated,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Icon(
                    Icons.swap_horiz,
                    size: 16,
                    color: colorScheme.primary500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
