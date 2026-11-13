import 'dart:async';

import 'package:ente_components/components/menu_component.dart';
import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';

class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.svgIconPath,
    this.trailing,
    this.onTap,
    this.onDoubleTap,
    this.showChevron = true,
    this.isDestructive = false,
    this.showOnlyLoadingState = false,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 1,
    this.semanticsIdentifier,
  });

  final String title;
  final String? subtitle;
  final List<List<dynamic>>? icon;
  final String? svgIconPath;
  final Widget? trailing;
  final FutureOr<void> Function()? onTap;
  final FutureOr<void> Function()? onDoubleTap;
  final bool showChevron;
  final bool isDestructive;
  final bool showOnlyLoadingState;
  final int titleMaxLines;
  final int subtitleMaxLines;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final textColor = isDestructive ? colors.warning : colors.textBase;
    final iconColor = isDestructive ? colors.warning : colors.textLight;

    final item = MenuComponent(
      title: title,
      subtitle: subtitle,
      titleColor: textColor,
      iconColor: iconColor,
      leading: _buildLeading(iconColor),
      trailing: trailing ?? (showChevron ? _chevron(colors) : null),
      showOnlyLoadingState: showOnlyLoadingState,
      titleMaxLines: titleMaxLines,
      subtitleMaxLines: subtitleMaxLines,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
    );
    final identifier = semanticsIdentifier;
    return identifier == null
        ? item
        : Semantics(identifier: identifier, child: item);
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
