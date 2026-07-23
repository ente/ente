import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/models/typedefs.dart';
import 'package:photos/ui/components/buttons/button_widget_v2.dart';

class DynamicFAB extends StatelessWidget {
  final bool? isKeypadOpen;
  final bool? isFormValid;
  final String? buttonText;
  final FutureVoidCallback? onPressedFunction;

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
            FloatingActionButton(
              heroTag: 'FAB',
              backgroundColor: Theme.of(
                context,
              ).colorScheme.dynamicFABBackgroundColor,
              foregroundColor: Theme.of(
                context,
              ).colorScheme.dynamicFABTextColor,
              onPressed: isFormValid!
                  ? () {
                      onPressedFunction!();
                    }
                  : () {
                      FocusScope.of(context).unfocus();
                    },
              child: Transform.rotate(
                angle: isFormValid! ? 0 : math.pi / 2,
                child: const Icon(Icons.chevron_right, size: 36),
              ), //keypad down here
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: buttonText!,
          isDisabled: !isFormValid!,
          onTap: isFormValid! ? onPressedFunction : null,
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
