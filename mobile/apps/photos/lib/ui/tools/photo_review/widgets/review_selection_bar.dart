import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";

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
    final colors = context.componentColors;
    final l10n = context.strings;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.backgroundBase,
        border: Border.all(color: colors.strokeDark),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.button),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.xl,
            Spacing.lg,
            Spacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SelectionSummaryChipComponent(
                    label: l10n.selectAll,
                    semanticLabel: l10n.selectAll,
                    isSelected: allSelected,
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedTick02),
                    onTap: onSelectAll,
                  ),
                  SelectionSummaryChipComponent(
                    label: l10n.selectedPhotos(count: selectedCount),
                    semanticLabel:
                        "${l10n.cancel}, ${l10n.selectedPhotos(count: selectedCount)}",
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
                    onTap: onClear,
                  ),
                ],
              ),
              const SizedBox(height: 27),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.fillLight,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ActionTile(
                      label: l10n.markAsReviewed,
                      icon: HugeIcons.strokeRoundedTickDouble02,
                      onTap: onMarkAsReviewed,
                    ),
                    const SizedBox(width: 72),
                    _ActionTile(
                      label: l10n.reviewAgain,
                      icon: HugeIcons.strokeRoundedReload,
                      onTap: onReviewAgain,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final List<List<dynamic>> icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final foreground = onTap == null ? colors.textLighter : colors.textBase;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: SizedBox(
          width: 102,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: HugeIcon(
                      icon: icon,
                      size: IconSizes.small,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.mini.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
