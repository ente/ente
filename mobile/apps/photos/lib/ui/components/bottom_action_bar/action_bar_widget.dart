import "package:ente_components/components/chip_surface.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/models/selected_files.dart";

class ActionBarWidget extends StatelessWidget {
  const ActionBarWidget({
    required this.selectedFiles,
    required this.onCancel,
    super.key,
  });

  final SelectedFiles selectedFiles;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedFiles,
      builder: (context, _) {
        final currentUserID = Configuration.instance.getUserID() ?? -1;
        final ownedCount = selectedFiles.files
            .where(
              (file) => file.ownerID == null || file.ownerID == currentUserID,
            )
            .length;
        final summary = ownedCount == selectedFiles.files.length
            ? context.strings.selectedPhotos(count: selectedFiles.files.length)
            : context.strings.selectedPhotosWithYours(
                count: selectedFiles.files.length,
                yourCount: ownedCount,
              );
        return SelectionControlChip(
          label: selectedFiles.files.length.toString(),
          semanticLabel: "${context.strings.cancel}, $summary",
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedCancel01,
            size: IconSizes.small,
          ),
          onTap: onCancel,
        );
      },
    );
  }
}

class SelectionControlChip extends StatelessWidget {
  const SelectionControlChip({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.isSelected = false,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final Widget icon;
  final VoidCallback? onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final color = onTap == null ? colors.textLightest : colors.textBase;
    return ChipSurface(
      surfaceKey: const ValueKey("selection-control-chip"),
      enabled: onTap != null,
      selected: isSelected,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      minHeight: 44,
      minWidth: 64,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      background: colors.fillLight,
      borderRadius: BorderRadius.circular(100),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.body.copyWith(color: color),
            ),
          ),
          const SizedBox(width: Spacing.md),
          ChipIconSlot(
            color: color,
            size: IconSizes.small,
            slotSize: IconSizes.small,
            child: icon,
          ),
        ],
      ),
    );
  }
}
