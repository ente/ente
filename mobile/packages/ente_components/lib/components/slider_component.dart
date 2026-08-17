import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show Slider;

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=57-6281&m=dev
class SliderComponent extends StatelessWidget {
  const SliderComponent({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.strokeFaint,
        thumbColor: colors.primary,
        overlayColor: colors.primaryLight,
      ),
      child: material.Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}
