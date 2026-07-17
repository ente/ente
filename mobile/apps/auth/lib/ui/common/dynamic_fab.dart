import 'dart:math' as math;

import 'package:ente_auth/ente_theme_data.dart';
import 'package:flutter/material.dart';

class DynamicFAB extends StatelessWidget {
  final bool? isKeypadOpen;
  final bool? isFormValid;
  final String? buttonText;
  final Function? onPressedFunction;

  const DynamicFAB({
    super.key,
    this.isKeypadOpen,
    this.buttonText,
    this.isFormValid,
    this.onPressedFunction,
  });

  @override
  Widget build(BuildContext context) {
    if (isKeypadOpen!) {
      return Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.surface,
              spreadRadius: 200,
              blurRadius: 100,
              offset: const Offset(0, 230),
            ),
          ],
        ),
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Semantics(
              button: true,
              container: true,
              excludeSemantics: true,
              identifier: 'auth_dynamic_fab',
              label: buttonText,
              child: FloatingActionButton(
                heroTag: 'FAB',
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.dynamicFABBackgroundColor,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.dynamicFABTextColor,
                onPressed: isFormValid!
                    ? onPressedFunction as void Function()?
                    : () {
                        FocusScope.of(context).unfocus();
                      },
                child: Transform.rotate(
                  angle: isFormValid! ? 0 : math.pi / 2,
                  child: const Icon(Icons.chevron_right, size: 36),
                ), //keypad down here
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        width: double.infinity,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OutlinedButton(
          onPressed: isFormValid!
              ? onPressedFunction as void Function()?
              : null,
          child: Text(buttonText!),
        ),
      );
    }
  }
}

class NoScalingAnimation extends FloatingActionButtonAnimator {
  @override
  Offset getOffset({Offset? begin, required Offset end, double? progress}) {
    return end;
  }

  @override
  Animation<double> getRotationAnimation({required Animation<double> parent}) {
    return Tween<double>(begin: 1.0, end: 1.0).animate(parent);
  }

  @override
  Animation<double> getScaleAnimation({required Animation<double> parent}) {
    return Tween<double>(begin: 1.0, end: 1.0).animate(parent);
  }
}
