import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_sheet.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";

class ReviewSelectionBar extends StatelessWidget {
  const ReviewSelectionBar({
    required this.selectedCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClear,
    required this.onMarkAsReviewed,
    required this.onReviewAgain,
    super.key,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback? onMarkAsReviewed;
  final VoidCallback? onReviewAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    return SelectionActionSheet(
      actions: [
        SelectionSheetAction(
          labelText: l10n.markAsReviewed,
          hugeIcon: HugeIcons.strokeRoundedTickDouble02,
          onTap: onMarkAsReviewed,
        ),
        SelectionSheetAction(
          labelText: l10n.reviewAgain,
          hugeIcon: HugeIcons.strokeRoundedReload,
          onTap: onReviewAgain,
        ),
      ],
      selectionControls: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: SelectionControlChip(
                  label: l10n.selectAllShort,
                  semanticLabel: l10n.selectAll,
                  isSelected: allSelected,
                  icon: SelectAllStatusIcon(
                    isSelected: allSelected,
                    size: IconSizes.small,
                    unselectedColor: context.componentColors.textLighter,
                  ),
                  onTap: onSelectAll,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: SelectionControlChip(
                  label: selectedCount.toString(),
                  semanticLabel:
                      "${l10n.cancel}, ${l10n.selectedPhotos(count: selectedCount)}",
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
                  onTap: onClear,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
