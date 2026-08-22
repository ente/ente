import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";

Future<void> showVideoSpeedBottomSheet(
  BuildContext context, {
  required double currentSpeed,
  required void Function(double) onSpeedSelected,
}) async {
  await showBottomSheetComponent<void>(
    context: context,
    builder: (context) => BottomSheetComponent(
      title: context.strings.playbackSpeed,
      content: _VideoSpeedBottomSheetContent(
        currentSpeed: currentSpeed,
        onSpeedSelected: onSpeedSelected,
      ),
    ),
  );
}

class _VideoSpeedBottomSheetContent extends StatelessWidget {
  const _VideoSpeedBottomSheetContent({
    required this.currentSpeed,
    required this.onSpeedSelected,
  });

  final double currentSpeed;
  final void Function(double) onSpeedSelected;

  static const _speeds = [0.25, 0.5, 1.0, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < _speeds.length; i++) ...[
          Expanded(
            child: _SpeedChip(
              label: _speeds[i] == 1.0 ? "1x" : "${_speeds[i]}x",
              isSelected: currentSpeed == _speeds[i],
              onTap: () {
                onSpeedSelected(_speeds[i]);
                Navigator.of(context).pop();
              },
            ),
          ),
          if (i < _speeds.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final selectedBackground = colors.fillBase.withValues(alpha: 0.9);
    final selectedForeground = colors.textReverse;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? selectedBackground : colors.fillLight,
          borderRadius: BorderRadius.circular(25),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyles.body.copyWith(
            color: isSelected ? selectedForeground : colors.iconColor,
          ),
        ),
      ),
    );
  }
}
