import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";

String formatLegacyKitNoticePeriod(BuildContext context, int hours) {
  if (hours == 0) {
    return context.strings.immediate;
  }
  if (hours % 24 == 0) {
    return context.strings.nDays(hours ~/ 24);
  }
  return context.strings.nHours(hours);
}

Future<int?> showLegacyKitRecoveryWaitTimeSheet(
  BuildContext context, {
  required int selectedDays,
  bool showCancellationWarning = true,
  bool requireChange = true,
}) {
  return showBottomSheetComponent<int>(
    context: context,
    builder: (context) => _LegacyKitRecoveryWaitSheet(
      selectedDays: selectedDays,
      showCancellationWarning: showCancellationWarning,
      requireChange: requireChange,
    ),
  );
}

class _LegacyKitRecoveryWaitSheet extends StatefulWidget {
  final int selectedDays;
  final bool showCancellationWarning;
  final bool requireChange;

  const _LegacyKitRecoveryWaitSheet({
    required this.selectedDays,
    required this.showCancellationWarning,
    required this.requireChange,
  });

  @override
  State<_LegacyKitRecoveryWaitSheet> createState() =>
      _LegacyKitRecoveryWaitSheetState();
}

class _LegacyKitRecoveryWaitSheetState
    extends State<_LegacyKitRecoveryWaitSheet> {
  static const List<int> _dayOptions = [0, 1, 7, 15, 30];
  late int _selectedDays = widget.selectedDays;

  bool get _canContinue =>
      !widget.requireChange || _selectedDays != widget.selectedDays;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: context.strings.recoveryWaitTime,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.strings.recoveryWaitTimeDescription,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          if (widget.showCancellationWarning) ...[
            const SizedBox(height: Spacing.md),
            Text(
              context.strings.recoveryWaitTimeChangeWarning,
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          for (var index = 0; index < _dayOptions.length; index++) ...[
            _WaitTimeOption(
              label: formatLegacyKitNoticePeriod(
                context,
                _dayOptions[index] * 24,
              ),
              selected: _selectedDays == _dayOptions[index],
              onTap: () => setState(() => _selectedDays = _dayOptions[index]),
            ),
            if (index < _dayOptions.length - 1)
              const SizedBox(height: Spacing.sm),
          ],
        ],
      ),
      actions: [
        ButtonComponent(
          label: context.strings.confirm,
          size: ButtonComponentSize.large,
          isDisabled: !_canContinue,
          onTap: () => Navigator.of(context).pop(_selectedDays),
        ),
      ],
    );
  }
}

class _WaitTimeOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WaitTimeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return MenuComponent(
      title: label,
      selected: selected,
      onTap: onTap,
      trailing: selected
          ? Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 14, color: colors.specialWhite),
            )
          : null,
    );
  }
}
