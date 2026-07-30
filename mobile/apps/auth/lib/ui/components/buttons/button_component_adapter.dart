import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

const _loadingSurfaceDelay = Duration(milliseconds: 300);
const _successDisplayDuration = Duration(seconds: 1);

/// Preserves legacy Auth button behavior while rendering an Ente component.
class ButtonComponentAdapter extends StatelessWidget {
  const ButtonComponentAdapter({required this.button, super.key});

  final ButtonWidget button;

  @override
  Widget build(BuildContext context) {
    return ButtonComponent(
      label: button.labelText ?? '',
      leading: button.icon == null
          ? null
          : Icon(button.icon, color: button.iconColor),
      onTap: button.isDisabled ? null : () => _handleTap(context),
      variant: _variantFor(button.buttonType),
      size: _sizeFor(button.buttonSize),
      isDisabled: button.isDisabled,
      shouldSurfaceExecutionStates: button.shouldSurfaceExecutionStates,
      shouldShowSuccessConfirmation: button.shouldShowSuccessConfirmation,
      progressStatus: button.progressStatus,
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _invokeButtonAction(context, button);
    } finally {
      stopwatch.stop();
    }

    if (!button.isInAlert) return;

    final delay = _popDelay(button, stopwatch.elapsed);
    unawaited(
      Future<void>.delayed(delay, () {
        if (context.mounted) {
          _popWithResult(context, ButtonResult(button.buttonAction));
        }
      }),
    );
  }
}

ButtonComponentVariant _variantFor(ButtonType buttonType) {
  return switch (buttonType) {
    ButtonType.primary ||
    ButtonType.trailingIconPrimary => ButtonComponentVariant.primary,
    ButtonType.secondary ||
    ButtonType.trailingIconSecondary => ButtonComponentVariant.secondary,
    ButtonType.critical => ButtonComponentVariant.critical,
    ButtonType.tertiaryCritical => ButtonComponentVariant.tertiaryCritical,
    ButtonType.tertiary => ButtonComponentVariant.link,
    ButtonType.neutral ||
    ButtonType.trailingIcon => ButtonComponentVariant.neutral,
  };
}

ButtonComponentSize _sizeFor(ButtonSize buttonSize) {
  return switch (buttonSize) {
    ButtonSize.small => ButtonComponentSize.small,
    ButtonSize.large => ButtonComponentSize.large,
  };
}

Duration _popDelay(ButtonWidget button, Duration elapsed) {
  if (!button.shouldSurfaceExecutionStates) return Duration.zero;
  if (button.shouldShowSuccessConfirmation || elapsed >= _loadingSurfaceDelay) {
    return _successDisplayDuration;
  }
  return Duration.zero;
}

void _popWithResult(BuildContext context, ButtonResult result) {
  final route = ModalRoute.of(context);
  if (route != null &&
      route.isCurrent &&
      (route is PopupRoute || route is ModalSheetRoute)) {
    Navigator.of(context).pop(result);
  }
}

Exception _toException(Object error) {
  return error is Exception ? error : Exception(error.toString());
}

Future<void> _invokeButtonAction(
  BuildContext context,
  ButtonWidget button,
) async {
  try {
    await button.onTap?.call();
  } catch (error) {
    if (button.isInAlert && context.mounted) {
      _popWithResult(
        context,
        ButtonResult(ButtonAction.error, _toException(error)),
      );
    }
    rethrow;
  }
}

class LegacySheetButtonConfiguration {
  LegacySheetButtonConfiguration._({
    required this.actions,
    required this.cancelButton,
  });

  factory LegacySheetButtonConfiguration.from(
    BuildContext context,
    List<ButtonWidget> buttons,
  ) {
    final cancelLabels = {context.l10n.cancel, 'Cancel'};
    final cancelButtonIndex = buttons.indexWhere(
      (button) =>
          button.isInAlert &&
          !button.isDisabled &&
          cancelLabels.contains(button.labelText),
    );
    return LegacySheetButtonConfiguration._(
      actions: [
        for (var index = 0; index < buttons.length; index++)
          if (index != cancelButtonIndex)
            ButtonComponentAdapter(button: buttons[index]),
      ],
      cancelButton: cancelButtonIndex == -1 ? null : buttons[cancelButtonIndex],
    );
  }

  final List<Widget> actions;
  final ButtonWidget? cancelButton;

  bool get showCloseButton => cancelButton != null;

  ButtonResult? get closeResult {
    final button = cancelButton;
    return button == null ? null : ButtonResult(button.buttonAction);
  }

  FutureOr<void> Function()? onClose(BuildContext context) {
    final button = cancelButton;
    return button == null ? null : () => _invokeButtonAction(context, button);
  }
}
