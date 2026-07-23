import 'dart:math' as math;

import 'package:ente_components/components/chip_surface.dart';
import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum FilterChipComponentState { selected, unselected, disabled }

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=9524-4352&m=dev
/// Section: Filter Chip
/// Specs: 40px minimum height, pill radius, selected/unselected/disabled states with icon and avatar slots.
class FilterChipComponent extends StatelessWidget {
  const FilterChipComponent({
    super.key,
    this.label,
    this.leading,
    this.trailing,
    this.avatar,
    this.state = FilterChipComponentState.unselected,
    this.onChanged,
    this.tooltip,
    this.avatarSize,
    this.scaleAvatarWithText = false,
  }) : assert(label != null || avatar != null);

  final String? label;
  final Widget? leading;
  final Widget? trailing;
  final Widget? avatar;
  final FilterChipComponentState state;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;
  final double? avatarSize;
  final bool scaleAvatarWithText;

  static const minHeight = 40.0;
  static const _textVerticalPadding = 24.0;
  static const _labelLineHeight = 16.0;
  static const _avatarVerticalPadding = Spacing.xs * 2;

  static double heightForTextScale(BuildContext context) {
    final textHeight = MediaQuery.textScalerOf(context).scale(_labelLineHeight);
    final scaledHeight = _textVerticalPadding + textHeight;
    return scaledHeight > minHeight ? scaledHeight : minHeight;
  }

  static double avatarSizeForTextScale(BuildContext context) {
    return heightForTextScale(context) - _avatarVerticalPadding;
  }

  double _avatarSizeFor(BuildContext context) {
    final baseAvatarSize = avatarSize ?? _avatarSize;
    if (!scaleAvatarWithText) {
      return baseAvatarSize;
    }
    final scaledAvatarSize = avatarSizeForTextScale(context);
    return math.max(scaledAvatarSize, baseAvatarSize);
  }

  bool get _selected => state == FilterChipComponentState.selected;

  bool get _enabled =>
      state != FilterChipComponentState.disabled && onChanged != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final textColor = switch (state) {
      FilterChipComponentState.selected => colors.textReverse,
      FilterChipComponentState.unselected => colors.textLight,
      FilterChipComponentState.disabled => colors.textLightest,
    };
    final background = _selected
        ? _inverseBackgroundBase(context)
        : colors.fillLight;
    final effectiveAvatarSize = _avatarSizeFor(context);
    final textScaledHeight = heightForTextScale(context);
    final effectiveChipHeight = avatar == null
        ? textScaledHeight
        : math.max(
            textScaledHeight,
            effectiveAvatarSize + _avatarVerticalPadding,
          );

    return ChipSurface(
      surfaceKey: const ValueKey('filter-chip-surface'),
      enabled: _enabled,
      selected: _selected,
      semanticLabel: tooltip ?? label,
      minHeight: effectiveChipHeight,
      minWidth: effectiveChipHeight,
      padding: _padding,
      background: background,
      borderRadius: BorderRadius.circular(effectiveChipHeight / 2),
      onTap: _enabled ? () => onChanged!(!_selected) : null,
      tooltip: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: _children(effectiveAvatarSize, textColor),
      ),
    );
  }

  Color _inverseBackgroundBase(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? ColorTokens.light.backgroundBase
        : ColorTokens.dark.backgroundBase;
  }

  List<Widget> _children(double effectiveAvatarSize, Color color) {
    final children = <Widget>[];
    final gap = avatar != null ? Spacing.xs : Spacing.sm;

    void addGap() {
      if (children.isNotEmpty) {
        children.add(SizedBox(width: gap));
      }
    }

    if (avatar != null) {
      children.add(
        _FilterChipAvatar(
          enabled: state != FilterChipComponentState.disabled,
          size: effectiveAvatarSize,
          child: avatar!,
        ),
      );
    }

    if (leading != null) {
      addGap();
      children.add(
        ChipIconSlot(
          color: color,
          size: IconSizes.small,
          slotSize: _iconSlotSize,
          child: leading!,
        ),
      );
    }

    if (label != null) {
      addGap();
      children.add(
        Text(
          label!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyles.mini.copyWith(color: color),
        ),
      );
    }

    final selectedTrailing = _selected && trailing == null;
    if (trailing != null || selectedTrailing) {
      addGap();
      children.add(
        ChipIconSlot(
          color: color,
          size: selectedTrailing ? _selectedTrailingIconSize : IconSizes.small,
          slotSize: selectedTrailing
              ? _selectedTrailingIconSize
              : _iconSlotSize,
          child: selectedTrailing
              ? const HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  size: _selectedTrailingIconSize,
                )
              : trailing!,
        ),
      );
    }

    return children;
  }

  EdgeInsets get _padding {
    if (avatar != null && label == null) {
      return _selected
          ? const EdgeInsets.fromLTRB(
              Spacing.xs,
              Spacing.xs,
              Spacing.sm,
              Spacing.xs,
            )
          : const EdgeInsets.all(Spacing.xs);
    }

    if (avatar != null) {
      return EdgeInsets.fromLTRB(
        Spacing.xs,
        Spacing.xs,
        _selected ? Spacing.sm : 18,
        Spacing.xs,
      );
    }

    if (leading != null && trailing == null) {
      return EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        _selected ? Spacing.md : Spacing.lg,
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

    if (_selected) {
      return const EdgeInsets.fromLTRB(18, Spacing.md, Spacing.md, Spacing.md);
    }

    return const EdgeInsets.symmetric(horizontal: 18, vertical: Spacing.md);
  }
}

const double _iconSlotSize = 16;
const double _selectedTrailingIconSize = 14;
const double _avatarSize = 32;

class _FilterChipAvatar extends StatelessWidget {
  const _FilterChipAvatar({
    required this.enabled,
    required this.size,
    required this.child,
  });

  final bool enabled;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox.square(dimension: size, child: child),
      ),
    );
  }
}
