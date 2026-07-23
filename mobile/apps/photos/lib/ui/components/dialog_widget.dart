import 'dart:async';

import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/button_result.dart';
import 'package:photos/models/typedefs.dart';
import "package:photos/ui/components/buttons/button_component_adapter.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';

/// Compatibility adapter for legacy Photos dialogs.
///
/// Preserves existing [ButtonWidget]/[ButtonResult] behavior while rendering
/// through [BottomSheetComponent]. Prefer [BottomSheetComponent] directly for
/// new sheets.
Future<ButtonResult?> showDialogWidget({
  required BuildContext context,
  required String title,
  String? body,
  required List<ButtonWidget> buttons,
  IconData? icon,
  bool isDismissible = true,
  bool useRootNavigator = false,
}) {
  return showBottomSheetComponent<ButtonResult>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    useRootNavigator: useRootNavigator,
    builder: (_) {
      return LegacyDialogWidget(
        title: title,
        body: body,
        buttons: buttons,
        icon: icon,
      );
    },
  );
}

class LegacyDialogWidget extends StatelessWidget {
  final String title;
  final String? body;
  final List<ButtonWidget> buttons;
  final IconData? icon;
  const LegacyDialogWidget({
    required this.title,
    this.body,
    required this.buttons,
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasTitle = title.isNotEmpty;
    final hasBody = body?.isNotEmpty == true;
    final hasContent = hasTitle || hasBody || icon != null;
    final cancelButtonIndex = sheetCancelButtonIndex(context, buttons);
    final cancelButton = cancelButtonIndex == -1
        ? null
        : buttons[cancelButtonIndex];
    final visibleButtons = [
      for (var index = 0; index < buttons.length; index++)
        if (index != cancelButtonIndex) buttons[index],
    ];

    return BottomSheetComponent(
      title: hasTitle ? title : null,
      illustration: icon == null
          ? null
          : Icon(icon, size: 48, color: colors.iconColor),
      content: hasBody ? _LegacyDialogBody(body!) : null,
      actions: [
        for (final button in visibleButtons)
          ButtonComponentAdapter(button: button),
      ],
      showCloseButton: cancelButton != null,
      closeTooltip: AppLocalizations.of(context).close,
      closeResult: cancelButton == null ? null : sheetCloseResult(cancelButton),
      onClose: cancelButton == null
          ? null
          : () => sheetCloseAction(context, cancelButton),
      actionsTopSpacing: hasContent ? Spacing.xl : 0,
    );
  }
}

class _LegacyDialogBody extends StatelessWidget {
  const _LegacyDialogBody(this.body);

  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.45;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Text(
          body,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
      ),
    );
  }
}

class LegacyTextInputDialog extends StatefulWidget {
  final String title;
  final String? body;
  final String submitButtonLabel;
  final IconData? icon;
  final String? label;
  final String? message;
  final FutureVoidCallbackParamStr onSubmit;
  final String? hintText;
  final IconData? prefixIcon;
  final String? initialValue;
  final Alignment? alignMessage;
  final int? maxLength;
  final bool showOnlyLoadingState;
  final TextCapitalization? textCapitalization;
  final bool alwaysShowSuccessState;
  final bool isPasswordInput;
  final TextEditingController? textEditingController;
  final List<TextInputFormatter>? textInputFormatter;
  final TextInputType? textInputType;
  final bool popnavAfterSubmission;
  const LegacyTextInputDialog({
    required this.title,
    this.body,
    required this.submitButtonLabel,
    required this.onSubmit,
    this.icon,
    this.label,
    this.message,
    this.hintText,
    this.prefixIcon,
    this.initialValue,
    this.alignMessage,
    this.maxLength,
    this.textCapitalization,
    this.showOnlyLoadingState = false,
    this.alwaysShowSuccessState = false,
    this.isPasswordInput = false,
    this.textEditingController,
    this.textInputFormatter,
    this.textInputType,
    this.popnavAfterSubmission = true,
    super.key,
  });

  @override
  State<LegacyTextInputDialog> createState() => _LegacyTextInputDialogState();
}

class _LegacyTextInputDialogState extends State<LegacyTextInputDialog> {
  static const _loadingSurfaceDelay = Duration(milliseconds: 300);
  static const _successDisplayDuration = Duration(seconds: 1);

  late final TextEditingController _textEditingController;
  late final bool _ownsTextEditingController;
  late final VoidCallback _textEditingControllerListener;
  Timer? _inputErrorResetTimer;
  var _hasInput = false;
  var _hasInputError = false;
  var _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _ownsTextEditingController = widget.textEditingController == null;
    _textEditingController =
        widget.textEditingController ?? TextEditingController();
    if (widget.initialValue != null) {
      final initialText = _formatInitialValue(widget.initialValue!);
      _textEditingController.value = TextEditingValue(
        text: initialText,
        selection: TextSelection.collapsed(offset: initialText.length),
      );
    }
    _hasInput = _textEditingController.text.isNotEmpty;
    _textEditingControllerListener = () {
      final hasInput = _textEditingController.text.isNotEmpty;
      if (hasInput != _hasInput || _hasInputError) {
        setState(() {
          _hasInput = hasInput;
          _hasInputError = false;
        });
      }
    };
    _textEditingController.addListener(_textEditingControllerListener);
  }

  @override
  void dispose() {
    _inputErrorResetTimer?.cancel();
    _textEditingController.removeListener(_textEditingControllerListener);
    if (_ownsTextEditingController) {
      _textEditingController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: widget.title,
      illustration: widget.icon == null
          ? null
          : Icon(widget.icon, size: 48, color: colors.iconColor),
      content: _LegacyTextInputDialogContent(
        body: widget.body,
        input: TextInputComponent(
          controller: _textEditingController,
          label: widget.label,
          message: widget.alignMessage == null ? widget.message : null,
          messageType: _hasInputError
              ? TextInputComponentMessageType.error
              : TextInputComponentMessageType.helper,
          hintText: widget.hintText,
          autofocus: true,
          maxLength: widget.maxLength,
          onSubmit: (_) => _submit(),
          textCapitalization:
              widget.textCapitalization ?? TextCapitalization.none,
          isPasswordInput: widget.isPasswordInput,
          isClearable: !widget.isPasswordInput,
          inputFormatters: widget.textInputFormatter,
          keyboardType: widget.textInputType,
          prefix: widget.prefixIcon == null
              ? null
              : Icon(widget.prefixIcon, size: IconSizes.small),
        ),
        alignedMessage: widget.alignMessage == null ? null : widget.message,
        alignedMessageAlignment: widget.alignMessage,
      ),
      actions: [
        ButtonComponent(
          label: widget.submitButtonLabel,
          isDisabled: !_hasInput,
          shouldShowSuccessState: !widget.showOnlyLoadingState,
          shouldShowSuccessConfirmation:
              !widget.showOnlyLoadingState && widget.alwaysShowSuccessState,
          onTap: _hasInput ? () => _submit(throwOnError: true) : null,
        ),
      ],
      isKeyboardAware: true,
      showCloseButton: true,
      closeTooltip: AppLocalizations.of(context).close,
      closeResult: ButtonResult(),
    );
  }

  Future<void> _submit({bool throwOnError = false}) async {
    if (_isSubmitting || !_hasInput) {
      return;
    }

    _isSubmitting = true;
    final stopwatch = Stopwatch()..start();
    try {
      await widget.onSubmit(_textEditingController.text);
    } catch (error) {
      final exception = error is Exception
          ? error
          : Exception(error.toString());
      _isSubmitting = false;
      if (error.toString().contains("Incorrect password") && mounted) {
        _surfaceInputError();
      }
      if (widget.popnavAfterSubmission && mounted) {
        Navigator.of(context).pop(exception);
      }
      if (throwOnError) {
        throw exception;
      }
      return;
    } finally {
      stopwatch.stop();
    }

    if (!mounted) {
      _isSubmitting = false;
      return;
    }
    if (!widget.popnavAfterSubmission) {
      _isSubmitting = false;
      return;
    }

    unawaited(
      Future<void>.delayed(_popDelay(stopwatch.elapsed), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }),
    );
  }

  Duration _popDelay(Duration elapsed) {
    if (widget.showOnlyLoadingState) {
      return Duration.zero;
    }
    if (widget.alwaysShowSuccessState || elapsed >= _loadingSurfaceDelay) {
      return _successDisplayDuration;
    }
    return Duration.zero;
  }

  void _surfaceInputError() {
    HapticFeedback.vibrate();
    setState(() => _hasInputError = true);
    _inputErrorResetTimer?.cancel();
    _inputErrorResetTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _hasInputError = false);
      }
    });
  }

  String _formatInitialValue(String initialValue) {
    var formattedValue = initialValue;
    final formatters = widget.textInputFormatter;
    if (formatters == null) {
      return formattedValue;
    }
    for (final formatter in formatters) {
      formattedValue = formatter
          .formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: formattedValue),
          )
          .text;
    }
    return formattedValue;
  }
}

class _LegacyTextInputDialogContent extends StatelessWidget {
  const _LegacyTextInputDialogContent({
    required this.input,
    this.body,
    this.alignedMessage,
    this.alignedMessageAlignment,
  });

  final Widget input;
  final String? body;
  final String? alignedMessage;
  final Alignment? alignedMessageAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (body != null) ...[
          Text(body!, style: TextStyles.body.copyWith(color: colors.textLight)),
          const SizedBox(height: Spacing.lg),
        ],
        input,
        if (alignedMessage != null) ...[
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: alignedMessageAlignment ?? Alignment.centerLeft,
            child: Text(
              alignedMessage!,
              style: TextStyles.mini.copyWith(color: colors.textLight),
            ),
          ),
        ],
      ],
    );
  }
}
