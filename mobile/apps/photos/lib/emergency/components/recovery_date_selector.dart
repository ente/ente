import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";

class RecoveryDateSelector extends StatelessWidget {
  final int selectedDays;
  final ValueChanged<int> onDaysChanged;

  const RecoveryDateSelector({
    required this.selectedDays,
    required this.onDaysChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _DayChip(
          label: context.strings.trashDaysLeft(count: 7),
          isSelected: selectedDays == 7,
          onTap: () => onDaysChanged(7),
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(width: 12),
        _DayChip(
          label: context.strings.trashDaysLeft(count: 14),
          isSelected: selectedDays == 14,
          onTap: () => onDaysChanged(14),
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(width: 12),
        _DayChip(
          label: context.strings.trashDaysLeft(count: 30),
          isSelected: selectedDays == 30,
          onTap: () => onDaysChanged(30),
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  const _DayChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.greenBase : colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: textTheme.bodyBold.copyWith(
            color: isSelected ? Colors.white : colorScheme.textBase,
          ),
        ),
      ),
    );
  }
}
