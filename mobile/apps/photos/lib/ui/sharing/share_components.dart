import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/components/collection_share_badge.dart";

class ShareScaffold extends StatelessWidget {
  const ShareScaffold({
    super.key,
    required this.title,
    this.children = const [],
    this.slivers,
    this.subtitle,
    this.actions = const [],
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 20),
    this.resizeToAvoidBottomInset,
    this.physics = const BouncingScrollPhysics(),
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? slivers;
  final List<Widget> actions;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final bool? resizeToAvoidBottomInset;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    final bodySlivers =
        slivers ??
        [
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: padding,
              sliver: SliverList.list(children: children),
            ),
          ),
        ];

    final content = AppBarComponent(
      title: title,
      subtitle: subtitle,
      actions: actions,
      physics: physics,
      slivers: bodySlivers,
    );

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: footer == null
          ? content
          : Column(
              children: [
                Expanded(child: content),
                footer!,
              ],
            ),
    );
  }
}

class ShareSectionTitle extends StatelessWidget {
  const ShareSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        title,
        style: TextStyles.large.copyWith(
          color: context.componentColors.textBase,
        ),
      ),
    );
  }
}

class ShareSectionDescription extends StatelessWidget {
  const ShareSectionDescription(
    this.content, {
    super.key,
    this.padding = const EdgeInsets.only(top: Spacing.sm),
  });

  final String content;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        content,
        style: TextStyles.body.copyWith(
          color: context.componentColors.textLight,
        ),
      ),
    );
  }
}

class ShareMenuGroup extends StatelessWidget {
  const ShareMenuGroup({
    super.key,
    required this.items,
    this.showDividers = false,
    this.dividerPadding = EdgeInsets.zero,
  });

  final List<Widget> items;
  final bool showDividers;
  final EdgeInsetsGeometry dividerPadding;

  @override
  Widget build(BuildContext context) {
    return MenuGroupComponent(
      backgroundColor: context.componentColors.fillLight,
      borderRadius: BorderRadius.circular(Radii.button),
      showDividers: showDividers,
      dividerPadding: dividerPadding,
      items: items,
    );
  }
}

class ShareMenuItem extends StatelessWidget {
  const ShareMenuItem({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.showChevron = false,
    this.selected = false,
    this.isDestructive = false,
    this.isDisabled = false,
    this.showOnlyLoadingState = false,
    this.shouldSurfaceExecutionStates = false,
    this.shouldShowSuccessConfirmation = false,
    this.titleColor,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 2,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final List<List<dynamic>>? icon;
  final Widget? leading;
  final Widget? trailing;
  final bool showChevron;
  final bool selected;
  final bool isDestructive;
  final bool isDisabled;
  final bool showOnlyLoadingState;
  final bool shouldSurfaceExecutionStates;
  final bool shouldShowSuccessConfirmation;
  final Color? titleColor;
  final int titleMaxLines;
  final int subtitleMaxLines;
  final FutureOr<void> Function()? onTap;
  final VoidCallback? onLongPress;

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
      titleColor: titleColor ?? effectiveTextColor,
      iconColor: effectiveIconColor,
      leading: leading ?? _leading(effectiveIconColor),
      trailing: trailing ?? (showChevron ? shareChevron(context) : null),
      selected: selected,
      isDisabled: isDisabled,
      showOnlyLoadingState: showOnlyLoadingState,
      shouldSurfaceExecutionStates: shouldSurfaceExecutionStates,
      shouldShowSuccessConfirmation: shouldShowSuccessConfirmation,
      titleMaxLines: titleMaxLines,
      subtitleMaxLines: subtitleMaxLines,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget? _leading(Color color) {
    if (icon == null) {
      return null;
    }
    return HugeIcon(
      icon: icon!,
      color: color,
      size: IconSizes.small,
      strokeWidth: 1.6,
    );
  }
}

Widget shareChevron(BuildContext context) {
  return Icon(
    Icons.chevron_right_rounded,
    color: context.componentColors.textLight,
    size: IconSizes.medium,
  );
}

Widget shareCheck(BuildContext context) {
  return const CollectionSelectedBadge();
}

Widget shareIcon(
  BuildContext context,
  List<List<dynamic>> icon, {
  Color? color,
}) {
  return HugeIcon(
    icon: icon,
    color: color ?? context.componentColors.textLight,
    size: IconSizes.small,
    strokeWidth: 1.6,
  );
}
