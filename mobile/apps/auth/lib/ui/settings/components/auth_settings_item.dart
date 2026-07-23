import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Auth-local settings composition built from Ente's shared menu primitive.
///
/// Keep this local until the team decides whether the Photos and Locker
/// settings wrappers should be consolidated in `ente_components`.
class AuthSettingsItem extends StatelessWidget {
  const AuthSettingsItem({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.onDoubleTap,
    this.showChevron = true,
    this.isDestructive = false,
    this.showOnlyLoadingState = false,
    this.semanticsIdentifier,
  });

  final String title;
  final String? subtitle;
  final List<List<dynamic>>? icon;
  final Widget? trailing;
  final FutureOr<void> Function()? onTap;
  final FutureOr<void> Function()? onDoubleTap;
  final bool showChevron;
  final bool isDestructive;
  final bool showOnlyLoadingState;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final foregroundColor = isDestructive ? colors.warning : colors.textBase;
    final iconColor = isDestructive ? colors.warning : colors.textLight;

    final item = MenuComponent(
      title: title,
      subtitle: subtitle,
      titleColor: foregroundColor,
      iconColor: iconColor,
      leading: _leadingIcon(iconColor),
      trailing: trailing ?? (showChevron ? _chevron(colors) : null),
      showOnlyLoadingState: showOnlyLoadingState,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
    );
    final identifier = semanticsIdentifier;
    return identifier == null
        ? item
        : Semantics(identifier: identifier, child: item);
  }

  Widget? _leadingIcon(Color color) {
    if (icon == null) return null;
    return HugeIcon(
      icon: icon!,
      color: color,
      size: IconSizes.small,
      strokeWidth: 1.6,
    );
  }

  Widget _chevron(ColorTokens colors) {
    return Icon(
      Icons.chevron_right_outlined,
      color: colors.textLight,
      size: IconSizes.medium,
    );
  }
}
