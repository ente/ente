import 'package:ente_components/components/chip_surface.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

/// Compact selection action used to select or clear a group of items.
///
/// This is separate from a filter chip: it represents an action and
/// keeps the same neutral surface when enabled or disabled.
/// Sources:
/// https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=18629-313326&m=dev
/// https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=15782-102259&m=dev
class SelectionSummaryChipComponent extends StatelessWidget {
  const SelectionSummaryChipComponent({
    required this.label,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.isSelected = false,
    super.key,
  });

  final String label;
  final Widget icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool isSelected;

  static const double width = 104;
  static const double minHeight = 36;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final enabled = onTap != null;
    final foreground = enabled ? colors.textBase : colors.textLighter;

    return SizedBox(
      width: width,
      child: ChipSurface(
        surfaceKey: const ValueKey('selection-summary-chip-surface'),
        enabled: enabled,
        selected: isSelected,
        semanticLabel: semanticLabel,
        minHeight: minHeight,
        padding: const EdgeInsets.fromLTRB(
          Spacing.sm,
          Spacing.sm,
          Spacing.md,
          Spacing.sm,
        ),
        background: colors.fillLight,
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 66,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyles.mini.copyWith(color: foreground),
              ),
            ),
            const SizedBox(width: Spacing.xs),
            ChipIconSlot(
              color: foreground,
              size: 12,
              slotSize: 14,
              child: icon,
            ),
          ],
        ),
      ),
    );
  }
}
