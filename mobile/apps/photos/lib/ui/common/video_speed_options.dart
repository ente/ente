import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

const videoSpeedOptions = [0.25, 0.5, 1.0, 1.5, 2.0];

class VideoSpeedOptions extends StatelessWidget {
  const VideoSpeedOptions({
    super.key,
    required this.currentSpeed,
    required this.onSpeedSelected,
  });

  final double currentSpeed;
  final ValueChanged<double> onSpeedSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < videoSpeedOptions.length; i++) ...[
          Expanded(
            child: _SpeedChip(
              speed: videoSpeedOptions[i],
              isSelected: currentSpeed == videoSpeedOptions[i],
              onTap: () => onSpeedSelected(videoSpeedOptions[i]),
            ),
          ),
          if (i < videoSpeedOptions.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.speed,
    required this.isSelected,
    required this.onTap,
  });

  final double speed;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final label = speed == 1.0 ? '1x' : '${speed}x';
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? colors.fillBase.withValues(alpha: 0.9)
                : colors.fillLight,
            borderRadius: BorderRadius.circular(25),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: TextStyles.body.copyWith(
              color: isSelected ? colors.textReverse : colors.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
