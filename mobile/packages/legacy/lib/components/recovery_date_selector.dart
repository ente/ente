import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:flutter/material.dart";

class RecoveryDateSelector extends StatelessWidget {
  final int selectedDays;
  final ValueChanged<int> onDaysChanged;
  final List<int> dayOptions;

  const RecoveryDateSelector({
    required this.selectedDays,
    required this.onDaysChanged,
    this.dayOptions = const [7, 14, 30],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return _buildChips(context, colorScheme, textTheme);
  }

  Widget _buildChip(BuildContext context, int days, colorScheme, textTheme) {
    final isSelected = selectedDays == days;
    return GestureDetector(
      onTap: () => onDaysChanged(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26.0, vertical: 18.0),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary700 : colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          days == 0 ? context.strings.immediate : context.strings.nDays(days),
          style: textTheme.bodyBold.copyWith(
            color: isSelected ? Colors.white : colorScheme.primary700,
          ),
        ),
      ),
    );
  }

  Widget _buildChips(BuildContext context, colorScheme, textTheme) {
    final chips = dayOptions
        .map((days) => _buildChip(context, days, colorScheme, textTheme))
        .toList(growable: false);

    if (chips.length == 3) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          chips[0],
          const SizedBox(width: 12),
          chips[1],
          const SizedBox(width: 12),
          chips[2],
        ],
      );
    }

    return Wrap(spacing: 12, runSpacing: 12, children: chips);
  }
}
