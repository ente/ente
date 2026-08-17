import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2513-47857&m=dev
class RadioComponent extends StatelessWidget {
  const RadioComponent({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final enabled = onChanged != null;
    final active = enabled ? colors.primary : colors.fillDarkest;

    return InkWell(
      onTap: enabled ? () => onChanged!(!selected) : null,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: Motion.quick,
        width: 16,
        height: 16,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? active : colors.strokeDark,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active,
                ),
              )
            : null,
      ),
    );
  }
}
