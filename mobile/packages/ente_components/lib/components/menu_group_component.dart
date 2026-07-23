import 'package:ente_components/components/divider_component.dart';
import 'package:ente_components/src/components/menu_component_surface_style.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

/// Groups related menu rows into one rounded surface.
///
/// The group owns the shared surface and applies first/middle/last row shapes,
/// while each item remains responsible for its own content and interaction.
class MenuGroupComponent extends StatelessWidget {
  const MenuGroupComponent({
    super.key,
    required this.items,
    this.backgroundColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.button)),
    this.clipBehavior = Clip.hardEdge,
    this.showDividers = false,
    this.dividerPadding = EdgeInsets.zero,
    this.dividerColor,
  });

  final List<Widget> items;
  final Color? backgroundColor;
  final BorderRadius borderRadius;
  final Clip clipBehavior;
  final bool showDividers;
  final EdgeInsetsGeometry dividerPadding;
  final Color? dividerColor;

  static BorderRadius itemBorderRadius({
    required int index,
    required int itemCount,
    BorderRadius borderRadius = const BorderRadius.all(
      Radius.circular(Radii.button),
    ),
  }) {
    assert(index >= 0);
    assert(itemCount > 0);
    assert(index < itemCount);

    return BorderRadius.only(
      topLeft: index == 0 ? borderRadius.topLeft : Radius.zero,
      topRight: index == 0 ? borderRadius.topRight : Radius.zero,
      bottomLeft: index == itemCount - 1
          ? borderRadius.bottomLeft
          : Radius.zero,
      bottomRight: index == itemCount - 1
          ? borderRadius.bottomRight
          : Radius.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Container(
      key: const ValueKey('menu-group-surface'),
      width: double.infinity,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.fillLight,
        borderRadius: borderRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _groupedItem(
              items[index],
              index: index,
              itemCount: items.length,
              backgroundColor: backgroundColor ?? colors.fillLight,
            ),
            if (showDividers && index < items.length - 1)
              DividerComponent(color: dividerColor, padding: dividerPadding),
          ],
        ],
      ),
    );
  }

  Widget _groupedItem(
    Widget item, {
    required int index,
    required int itemCount,
    required Color backgroundColor,
  }) {
    return MenuComponentSurfaceStyle(
      borderRadius: itemBorderRadius(
        index: index,
        itemCount: itemCount,
        borderRadius: borderRadius,
      ),
      backgroundColor: backgroundColor,
      child: item,
    );
  }
}
