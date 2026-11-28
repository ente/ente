import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

class DeleteAccountBottomActions extends StatelessWidget {
  const DeleteAccountBottomActions({
    super.key,
    required this.isConfirmationStep,
    required this.isActionEnabled,
    required this.onContinue,
    required this.onDelete,
  });

  final bool isConfirmationStep;
  final bool isActionEnabled;
  final VoidCallback onContinue;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperIndicator(isConfirmationStep: isConfirmationStep),
        const SizedBox(height: Spacing.lg),
        ButtonComponent(
          label: isConfirmationStep
              ? context.strings.deleteEnteAccount
              : context.strings.continueLabel,
          variant: isConfirmationStep
              ? ButtonComponentVariant.critical
              : ButtonComponentVariant.primary,
          isDisabled: !isActionEnabled,
          shouldSurfaceExecutionStates: true,
          shouldShowSuccessState: false,
          onTap: isConfirmationStep ? onDelete : onContinue,
        ),
      ],
    );
  }
}

class _StepperIndicator extends StatelessWidget {
  const _StepperIndicator({required this.isConfirmationStep});

  final bool isConfirmationStep;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepDot(isActive: !isConfirmationStep, colors: colors),
        const SizedBox(width: Spacing.md),
        _StepDot(isActive: isConfirmationStep, colors: colors),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.isActive, required this.colors});

  final bool isActive;
  final ColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.quick,
      width: isActive ? 20 : 10,
      height: 10,
      decoration: BoxDecoration(
        color: isActive ? colors.warning : colors.fillDark,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
