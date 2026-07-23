import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/components/buttons/button_component_adapter.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_base/typedefs.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

///Will return null if dismissed by tapping outside
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
      return DialogWidget(
        title: title,
        body: body,
        buttons: buttons,
        icon: icon,
      );
    },
  );
}

class DialogWidget extends StatelessWidget {
  final String title;
  final String? body;
  final List<ButtonWidget> buttons;
  final IconData? icon;
  const DialogWidget({
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
    final sheetButtons = LegacySheetButtonConfiguration.from(context, buttons);

    return BottomSheetComponent(
      title: hasTitle ? title : null,
      illustration: icon == null
          ? null
          : Icon(icon, size: 48, color: colors.iconColor),
      content: hasBody ? _DialogBody(body!) : null,
      actions: sheetButtons.actions,
      showCloseButton: sheetButtons.showCloseButton,
      closeTooltip: context.l10n.close,
      closeResult: sheetButtons.closeResult,
      onClose: sheetButtons.onClose(context),
      actionsTopSpacing: hasContent ? Spacing.xl : 0,
    );
  }
}

class _DialogBody extends StatelessWidget {
  const _DialogBody(this.body);

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

class TextInputDialog extends StatefulWidget {
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
  const TextInputDialog({
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
    super.key,
  });

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  static const _loadingSurfaceDelay = Duration(milliseconds: 300);
  static const _successDisplayDuration = Duration(seconds: 1);

  late final TextEditingController _textController;
  Timer? _inputErrorResetTimer;
  var _hasInput = false;
  var _hasInputError = false;
  var _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialValue);
    _hasInput = _textController.text.isNotEmpty;
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _inputErrorResetTimer?.cancel();
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
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
      content: _TextInputDialogContent(
        body: widget.body,
        input: TextInputComponent(
          controller: _textController,
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
      closeTooltip: context.l10n.close,
      closeResult: ButtonResult(),
    );
  }

  void _onTextChanged() {
    final hasInput = _textController.text.isNotEmpty;
    if (hasInput != _hasInput || _hasInputError) {
      setState(() {
        _hasInput = hasInput;
        _hasInputError = false;
      });
    }
  }

  Future<void> _submit({bool throwOnError = false}) async {
    if (_isSubmitting || !_hasInput) return;

    _isSubmitting = true;
    final stopwatch = Stopwatch()..start();
    try {
      await widget.onSubmit(_textController.text);
    } catch (error) {
      final exception = error is Exception
          ? error
          : Exception(error.toString());
      _isSubmitting = false;
      if (error.toString().contains('Incorrect password') && mounted) {
        _surfaceInputError();
      }
      if (mounted) Navigator.of(context).pop(exception);
      if (throwOnError) throw exception;
      return;
    } finally {
      stopwatch.stop();
    }

    if (!mounted) {
      _isSubmitting = false;
      return;
    }

    unawaited(
      Future<void>.delayed(_popDelay(stopwatch.elapsed), () {
        if (mounted) Navigator.of(context).pop();
      }),
    );
  }

  Duration _popDelay(Duration elapsed) {
    if (widget.showOnlyLoadingState) return Duration.zero;
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
      if (mounted) setState(() => _hasInputError = false);
    });
  }
}

class _TextInputDialogContent extends StatelessWidget {
  const _TextInputDialogContent({
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
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
