import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/viewer/file_details_new/file_details_menu_group.dart";

class FileDetailsInfoItemNew extends StatelessWidget {
  const FileDetailsInfoItemNew({
    required this.leading,
    required this.title,
    required this.subtitles,
    this.onTap,
    this.onEdit,
    super.key,
  });

  final Widget leading;
  final String title;
  final List<Widget> subtitles;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Material(
      color: colors.fillLight,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: fileDetailsMenuRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 36,
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: colors.textLight,
                        size: IconSizes.small,
                      ),
                      child: leading,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.body.copyWith(color: colors.textBase),
                      ),
                      if (subtitles.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xs),
                        SizedBox(
                          height: 16,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < subtitles.length;
                                  index++
                                ) ...[
                                  subtitles[index],
                                  if (index < subtitles.length - 1)
                                    const SizedBox(width: Spacing.md),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onEdit != null) ...[
                  const SizedBox(width: Spacing.md),
                  IconButtonComponent(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedEdit03,
                      size: IconSizes.small,
                      color: colors.textLight,
                    ),
                    variant: IconButtonComponentVariant.secondary,
                    shouldSurfaceExecutionStates: false,
                    onTap: onEdit,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
