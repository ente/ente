import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class SelectionPreviewButton extends StatelessWidget {
  const SelectionPreviewButton({
    required this.file,
    required this.count,
    required this.onTap,
    super.key,
  });

  final EnteFile file;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Semantics(
      label:
          '${context.strings.preview}, ${context.strings.selectedCount(count: count)}',
      button: true,
      enabled: onTap != null,
      child: Tooltip(
        message: context.strings.preview,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: ExcludeSemantics(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.xs),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: ThumbnailWidget(
                        file,
                        rawThumbnail: true,
                        placeholderColor: colors.fillLight,
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  bottom: 0,
                  start: 0,
                  end: 0,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.bottomEnd,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.fillBase,
                        borderRadius: BorderRadius.circular(Radii.lg),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyles.tiny.copyWith(
                          color: colors.textReverse,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
