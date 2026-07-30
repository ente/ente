import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2513-47857&m=dev
/// Section: Radio buttons, toggles and checkboxes / CheckboxComponent
/// Specs: 16px checkbox, selected and disabled variants.
class CheckboxComponent extends StatelessWidget {
  const CheckboxComponent({
    super.key,
    required this.selected,
    required this.onChanged,
    this.selectedColor,
  });

  final bool selected;
  final ValueChanged<bool>? onChanged;

  /// Fill and border color when [selected] and enabled.
  /// Defaults to the theme's primary color.
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final enabled = onChanged != null;
    final fill = selected
        ? (enabled ? (selectedColor ?? colors.primary) : colors.fillDarkest)
        : Colors.transparent;
    final stroke = enabled ? colors.textLight : colors.strokeFaint;

    return InkWell(
      onTap: enabled ? () => onChanged!(!selected) : null,
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: Motion.quick,
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? fill : stroke),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: IconSizes.tiny,
                color: colors.specialWhite,
              )
            : null,
      ),
    );
  }
}
