import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.controller,
    this.onTitleTap,
    this.onTitleDoubleTap,
    this.onTitleLongPress,
    this.bottomNavigationBar,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final ScrollController? controller;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleDoubleTap;
  final VoidCallback? onTitleLongPress;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      bottomNavigationBar: bottomNavigationBar,
      body: AppBarComponent(
        title: title,
        subtitle: subtitle,
        actions: actions,
        controller: controller,
        onTitleTap: onTitleTap,
        onTitleDoubleTap: onTitleDoubleTap,
        onTitleLongPress: onTitleLongPress,
        slivers: [
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: padding,
              sliver: SliverList.list(children: children),
            ),
          ),
        ],
      ),
    );
  }
}
