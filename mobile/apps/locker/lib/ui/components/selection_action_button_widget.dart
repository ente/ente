import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

class SelectionActionButton extends StatelessWidget {
  final IconData? icon;
  final Widget? hugeIcon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const SelectionActionButton({
    super.key,
    this.icon,
    this.hugeIcon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  }) : assert(
         icon != null || hugeIcon != null,
         'Either icon or hugeIcon must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final color = isDestructive ? colors.warning : colors.textBase;
    final iconWidget = hugeIcon ?? Icon(icon!, color: color, size: 24);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.fillLight,
          borderRadius: BorderRadius.circular(24.0),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 28, height: 28, child: Center(child: iconWidget)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyles.body.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
