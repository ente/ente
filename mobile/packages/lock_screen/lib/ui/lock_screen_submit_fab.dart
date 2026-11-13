import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

class LockScreenSubmitFab extends StatelessWidget {
  const LockScreenSubmitFab({
    super.key,
    required this.label,
    required this.isFormValid,
    required this.onSubmit,
  });

  final String label;
  final ValueListenable<bool> isFormValid;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isFormValid,
      builder: (context, isValid, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ButtonComponent(
            label: label,
            isDisabled: !isValid,
            shouldSurfaceExecutionStates: false,
            onTap: onSubmit,
          ),
        );
      },
    );
  }
}
