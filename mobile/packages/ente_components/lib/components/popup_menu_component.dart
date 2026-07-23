import 'dart:async';

import 'package:ente_components/components/buttons/icon_button_component.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2513-52763&m=dev
/// Section: Dropdown menu
/// Specs: 196px menu, 52px rows, 20px radius, optional leading/trailing icons,
/// optional secondary label, faint dividers, and Inter mini typography.
class EntePopupMenuOption<T> {
  const EntePopupMenuOption({
    required this.value,
    required this.label,
    this.secondaryLabel,
    this.secondaryTrailingWidget,
    this.labelColor,
    this.leadingWidget,
    this.isActive = false,
    this.trailingWidget,
    this.activeTrailingWidget,
    this.showDivider = true,
  });

  final T value;
  final String label;
  final String? secondaryLabel;
  final Widget? secondaryTrailingWidget;
  final Color? labelColor;
  final Widget? leadingWidget;
  final bool isActive;
  final Widget? trailingWidget;
  final Widget? activeTrailingWidget;
  final bool showDivider;
}

class EntePopupMenuButton<T> extends StatelessWidget {
  const EntePopupMenuButton({
    required this.optionsBuilder,
    required this.onSelected,
    this.child,
    this.menuWidth = 196.0,
    this.itemHeight = 52.0,
    this.borderRadius = Radii.button,
    this.elevation = 0.0,
    this.itemHorizontalPadding = Spacing.lg,
    super.key,
  });

  final FutureOr<List<EntePopupMenuOption<T>>> Function() optionsBuilder;
  final FutureOr<void> Function(T value) onSelected;
  final Widget? child;
  final double menuWidth;
  final double itemHeight;
  final double borderRadius;
  final double elevation;
  final double itemHorizontalPadding;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    if (child == null) {
      return IconButtonComponent(
        variant: IconButtonComponentVariant.primary,
        shouldSurfaceExecutionStates: false,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
        onTap: () => _showMenu(context),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showMenu(context),
      child: child,
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final options = await optionsBuilder();
    if (!context.mounted || options.isEmpty) {
      return;
    }

    final selected = await showEntePopupMenu<T>(
      context: context,
      options: options,
      menuWidth: menuWidth,
      itemHeight: itemHeight,
      borderRadius: borderRadius,
      elevation: elevation,
      itemHorizontalPadding: itemHorizontalPadding,
    );
    if (!context.mounted || selected == null) return;
    await onSelected(selected);
  }
}

Future<T?> showEntePopupMenu<T>({
  required BuildContext context,
  required List<EntePopupMenuOption<T>> options,
  double menuWidth = 196.0,
  double itemHeight = 52.0,
  double borderRadius = Radii.button,
  double elevation = 0.0,
  double itemHorizontalPadding = Spacing.lg,
}) {
  final colors = context.componentColors;
  final menuStrokeColor = colors.strokeFaint;
  final button = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  // Anchor the menu to the button's bottom edge so it drops below the button
  // instead of opening on top of it when there is enough room below.
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(
        button.size.bottomLeft(Offset.zero),
        ancestor: overlay,
      ),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );

  return showMenu<T>(
    context: context,
    color: colors.fillLight,
    elevation: elevation,
    surfaceTintColor: Colors.transparent,
    menuPadding: EdgeInsets.zero,
    constraints: BoxConstraints.tightFor(width: menuWidth),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: BorderSide(color: menuStrokeColor),
    ),
    clipBehavior: Clip.antiAlias,
    position: position,
    items: List.generate(options.length, (index) {
      final option = options[index];
      return PopupMenuItem<T>(
        value: option.value,
        padding: EdgeInsets.zero,
        height: itemHeight,
        child: Container(
          key: ValueKey('ente-popup-menu-item-$index'),
          height: itemHeight,
          padding: EdgeInsets.symmetric(horizontal: itemHorizontalPadding),
          decoration: BoxDecoration(
            border: option.showDivider && index != options.length - 1
                ? Border(bottom: BorderSide(color: menuStrokeColor))
                : null,
          ),
          child: _EntePopupMenuRow(option: option),
        ),
      );
    }),
  );
}

class _EntePopupMenuRow<T> extends StatelessWidget {
  const _EntePopupMenuRow({required this.option});

  final EntePopupMenuOption<T> option;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final mutedStyle = TextStyles.mini.copyWith(color: colors.textLight);
    final titleStyle = TextStyles.mini.copyWith(
      color: option.labelColor ?? colors.textBase,
    );
    final title = option.secondaryLabel == null
        ? Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          )
        : Row(
            children: [
              Flexible(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 6),
              Text('•', style: mutedStyle),
              const SizedBox(width: 6),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        option.secondaryLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mutedStyle,
                      ),
                    ),
                    if (option.secondaryTrailingWidget != null) ...[
                      const SizedBox(width: Spacing.xs),
                      option.secondaryTrailingWidget!,
                    ],
                  ],
                ),
              ),
            ],
          );

    return Row(
      children: [
        if (option.leadingWidget != null) ...[
          SizedBox.square(
            dimension: 24,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(
                  color: colors.textLight,
                  size: IconSizes.small,
                ),
                child: option.leadingWidget!,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(child: title),
        if (option.trailingWidget != null)
          option.trailingWidget!
        else if (option.activeTrailingWidget != null)
          option.isActive
              ? option.activeTrailingWidget!
              : const SizedBox(width: Spacing.md),
      ],
    );
  }
}
