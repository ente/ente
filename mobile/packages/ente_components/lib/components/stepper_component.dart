import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show IconButton;

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=57-6281&m=dev
class StepperComponent extends StatelessWidget {
  const StepperComponent({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.strokeFaint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            enabled: onChanged != null && value > min,
            onPressed: () => onChanged?.call(value - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Text(
              '$value',
              style: TextStyles.bodyBold.copyWith(color: colors.textBase),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            enabled: onChanged != null && value < max,
            onPressed: () => onChanged?.call(value + 1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return material.IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: IconSizes.small),
      color: colors.textBase,
      disabledColor: colors.textLighter,
    );
  }
}
