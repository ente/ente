import 'package:ente_components/theme/motion.dart';
import 'package:flutter/material.dart';

class ChipSurface extends StatelessWidget {
  const ChipSurface({
    super.key,
    required this.surfaceKey,
    required this.enabled,
    required this.selected,
    required this.semanticLabel,
    required this.minHeight,
    required this.padding,
    required this.background,
    required this.borderRadius,
    required this.child,
    this.minWidth,
    this.onTap,
    this.tooltip,
  });

  final Key surfaceKey;
  final bool enabled;
  final bool selected;
  final String? semanticLabel;
  final double minHeight;
  final double? minWidth;
  final EdgeInsetsGeometry padding;
  final Color background;
  final BorderRadiusGeometry borderRadius;
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget chip = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          key: surfaceKey,
          duration: Motion.quick,
          curve: Curves.easeInOutCubic,
          constraints: BoxConstraints(
            minWidth: minWidth ?? 0,
            minHeight: minHeight,
          ),
          padding: padding,
          decoration: BoxDecoration(
            color: background,
            borderRadius: borderRadius,
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );

    if (tooltip != null) {
      chip = Tooltip(message: tooltip!, child: chip);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      child: chip,
    );
  }
}

class ChipIconSlot extends StatelessWidget {
  const ChipIconSlot({
    required this.color,
    required this.child,
    required this.size,
    required this.slotSize,
    super.key,
  });

  final Color color;
  final Widget child;
  final double size;
  final double slotSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: slotSize,
      child: Center(
        child: IconTheme.merge(
          data: IconThemeData(color: color, size: size),
          child: child,
        ),
      ),
    );
  }
}
