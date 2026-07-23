import 'package:ente_components/components/chip_surface.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

enum TagChipComponentState { selected, unselected, disabled }

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2482-6479&m=dev
/// Section: Tag Chip
/// Specs: 44px height, 16px radius, body text, selected/unselected/disabled states with one optional icon slot.
class TagChipComponent extends StatelessWidget {
  const TagChipComponent({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.state = TagChipComponentState.unselected,
    this.onTap,
    this.tooltip,
  }) : assert(leading == null || trailing == null);

  final String label;
  final Widget? leading;
  final Widget? trailing;
  final TagChipComponentState state;
  final VoidCallback? onTap;
  final String? tooltip;

  bool get _selected => state == TagChipComponentState.selected;

  bool get _enabled => state != TagChipComponentState.disabled && onTap != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final contentColor = switch (state) {
      TagChipComponentState.selected => colors.specialWhite,
      TagChipComponentState.unselected => colors.textLight,
      TagChipComponentState.disabled => colors.textLightest,
    };
    final background = _selected ? colors.primary : colors.fillLight;

    return ChipSurface(
      surfaceKey: const ValueKey('tag-chip-surface'),
      enabled: _enabled,
      selected: _selected,
      semanticLabel: tooltip ?? label,
      minHeight: 44,
      padding: _padding,
      background: background,
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: _enabled ? onTap : null,
      tooltip: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: _children(contentColor),
      ),
    );
  }

  List<Widget> _children(Color color) {
    final children = <Widget>[];

    if (leading != null) {
      children.add(
        ChipIconSlot(
          color: color,
          size: _iconSlotSize,
          slotSize: _iconSlotSize,
          child: leading!,
        ),
      );
      children.add(const SizedBox(width: Spacing.xs));
    }

    children.add(
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyles.body.copyWith(color: color),
      ),
    );

    if (trailing != null) {
      children.add(const SizedBox(width: Spacing.xs));
      children.add(
        ChipIconSlot(
          color: color,
          size: _iconSlotSize,
          slotSize: _iconSlotSize,
          child: trailing!,
        ),
      );
    }

    return children;
  }

  EdgeInsets get _padding {
    if (leading != null) {
      return const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      );
    }

    if (trailing != null) {
      return const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.md,
        Spacing.md,
      );
    }

    return const EdgeInsets.symmetric(
      horizontal: Spacing.xl,
      vertical: Spacing.md,
    );
  }
}

const double _iconSlotSize = 20;
