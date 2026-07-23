import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/button_result.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";

const _loadingSurfaceDelay = Duration(milliseconds: 300);
const _successDisplayDuration = Duration(seconds: 1);

/// Compatibility bridge from legacy Photos [ButtonWidget] actions to
/// ente_components [ButtonComponent].
///
/// Used by legacy dialog/action-sheet adapters. Prefer [ButtonComponent]
/// directly for new bottom sheet actions.
class ButtonComponentAdapter extends StatelessWidget {
  const ButtonComponentAdapter({required this.button, super.key});

  final ButtonWidget button;

  @override
  Widget build(BuildContext context) {
    return ButtonComponent(
      label: button.labelText ?? '',
      leading: _icon,
      onTap: button.isDisabled ? null : () => _handleTap(context),
      variant: _variantFor(button.buttonType),
      size: _sizeFor(button.buttonSize),
      isDisabled: button.isDisabled,
      shouldSurfaceExecutionStates: button.shouldSurfaceExecutionStates,
      shouldShowSuccessConfirmation: button.shouldShowSuccessConfirmation,
      progressStatus: button.progressStatus,
    );
  }

  Widget? get _icon {
    if (button.iconWidget != null) {
      return button.iconWidget;
    }
    if (button.icon == null) {
      return null;
    }
    return Icon(button.icon, color: button.iconColor);
  }

  Future<void> _handleTap(BuildContext context) async {
    final stopwatch = Stopwatch()..start();
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
    } finally {
      stopwatch.stop();
    }

    if (!button.isInAlert) {
      return;
    }

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
  if (!button.shouldSurfaceExecutionStates) {
    return Duration.zero;
  }
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

int sheetCancelButtonIndex(BuildContext context, List<ButtonWidget> buttons) {
  final cancelLabels = {AppLocalizations.of(context).cancel, 'Cancel'};
  return buttons.indexWhere(
    (button) =>
        button.isInAlert &&
        !button.isDisabled &&
        cancelLabels.contains(button.labelText),
  );
}

ButtonResult sheetCloseResult(ButtonWidget button) {
  return ButtonResult(button.buttonAction);
}

Future<void> sheetCloseAction(BuildContext context, ButtonWidget button) async {
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
