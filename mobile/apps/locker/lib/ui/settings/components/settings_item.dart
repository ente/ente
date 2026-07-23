import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";

class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.svgIconPath,
    this.leading,
    this.trailing,
    this.onTap,
    this.onDoubleTap,
    this.showChevron = true,
    this.isDestructive = false,
    this.selected = false,
    this.showOnlyLoadingState = false,
    this.shouldSurfaceExecutionStates = false,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 1,
  });

  final String title;
  final String? subtitle;
  final List<List<dynamic>>? icon;
  final String? svgIconPath;
  final Widget? leading;
  final Widget? trailing;
  final FutureOr<void> Function()? onTap;
  final FutureOr<void> Function()? onDoubleTap;
  final bool showChevron;
  final bool isDestructive;
  final bool selected;
  final bool showOnlyLoadingState;
  final bool shouldSurfaceExecutionStates;
  final int titleMaxLines;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final effectiveTextColor = isDestructive ? colors.warning : colors.textBase;
    final effectiveIconColor = isDestructive
        ? colors.warning
        : colors.textLight;

    return MenuComponent(
      title: title,
      subtitle: subtitle,
      titleColor: effectiveTextColor,
      iconColor: effectiveIconColor,
      selected: selected,
      leading: leading ?? _buildLeading(effectiveIconColor),
      trailing: trailing ?? (showChevron ? _chevron(colors) : null),
      showOnlyLoadingState: showOnlyLoadingState,
      shouldSurfaceExecutionStates: shouldSurfaceExecutionStates,
      titleMaxLines: titleMaxLines,
      subtitleMaxLines: subtitleMaxLines,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
    );
  }

  Widget? _buildLeading(Color color) {
    if (icon != null) {
      return HugeIcon(
        icon: icon!,
        color: color,
        size: IconSizes.small,
        strokeWidth: 1.6,
      );
    }
    if (svgIconPath != null) {
      return SvgPicture.asset(
        svgIconPath!,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        width: IconSizes.small,
        height: IconSizes.small,
      );
    }
    return null;
  }

  Widget _chevron(ColorTokens colors) {
    return Icon(
      Icons.chevron_right_outlined,
      color: colors.textLight,
      size: IconSizes.medium,
    );
  }
}
