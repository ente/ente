import 'dart:async';

import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TextInputComponentMessageType { helper, error, alert, success }

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2275-11526&m=dev
/// Section: Textfield / Text Input
/// Specs: 388px design width, 52px field height, 81px with label, 100px with helper.
/// States: default, disabled, focused, error, success.
///
/// Multiline variant:
/// https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2275-11746&m=dev

class TextInputComponent extends StatefulWidget {
  const TextInputComponent({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.message,
    this.hintText,
    this.initialValue,
    this.autofocus = false,
    this.maxLength,
    this.submitNotifier,
    this.cancelNotifier,
    this.onSubmit,
    this.onChanged,
    this.onCancel,
    this.popNavAfterSubmission = false,
    this.textCapitalization = TextCapitalization.none,
    this.isPasswordInput = false,
    this.isClearable = false,
    this.shouldUnfocusOnClearOrSubmit = false,
    this.isEmptyNotifier,
    this.inputFormatters,
    this.keyboardType,
    this.textInputAction,
    this.enableFillColor = true,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.isRequired = false,
    this.prefix,
    this.suffix,
    this.onSuffixTap,
    this.messageType = TextInputComponentMessageType.helper,
    this.messageIcon,
    this.isDisabled = false,
    this.readOnly = false,
    this.autofillHints,
    this.maxLines,
    this.minLines,
    this.finishAutofillContextOnEditingComplete = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? message;
  final String? hintText;
  final String? initialValue;
  final bool autofocus;
  final int? maxLength;

  /// Executes [onSubmit] when the notifier changes. Duplicate submissions are
  /// ignored while a submit is in flight.
  final ValueNotifier<dynamic>? submitNotifier;

  /// Clears and unfocuses the field when the notifier changes, unless [onCancel]
  /// is provided.
  final ValueNotifier<dynamic>? cancelNotifier;

  /// Called by [submitNotifier] or the platform editing-complete action.
  final FutureOr<void> Function(String value)? onSubmit;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCancel;
  final bool popNavAfterSubmission;
  final TextCapitalization textCapitalization;
  final bool isPasswordInput;
  final bool isClearable;
  final bool shouldUnfocusOnClearOrSubmit;
  final ValueNotifier<bool>? isEmptyNotifier;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;

  /// Platform IME action. When set to [TextInputAction.next], completing the
  /// field moves focus to the next node instead of doing nothing.
  final TextInputAction? textInputAction;
  final bool enableFillColor;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool isRequired;

  /// Caller-owned leading widget. Pass explicit color and size when needed.
  final Widget? prefix;

  /// Caller-owned trailing widget. Sits in an icon slot that is at least
  /// [IconSizes.medium] square and grows to fit wider content (e.g. a row of
  /// affordances). Multiline fields pin this slot to the top.
  final Widget? suffix;

  /// Optional tap handler for [suffix]. When provided, the trailing affordance
  /// gets a 48px tap target without changing the field's visual layout.
  final VoidCallback? onSuffixTap;
  final TextInputComponentMessageType messageType;
  final IconData? messageIcon;
  final bool isDisabled;

  /// When true the field is non-editable but keeps the enabled visual style
  /// (unlike [isDisabled], which also mutes the text and disables the suffix
  /// tap). Text stays selectable and the soft keyboard is suppressed.
  final bool readOnly;
  final Iterable<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final bool finishAutofillContextOnEditingComplete;

  @override
  State<TextInputComponent> createState() => _TextInputComponentState();
}

class _TextInputComponentState extends State<TextInputComponent> {
  static const _kHeight = 52.0;
  static const _kIconContainerSize = IconSizes.medium;
  static const _kSuffixTapTargetSize = 48.0;

  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;
  Timer? _wrongPasswordResetTimer;
  late bool _obscureText;
  bool _hasText = false;
  bool _incorrectPassword = false;
  bool _isSubmitting = false;

  TextEditingController get _controller =>
      widget.controller ?? _internalController!;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureGroupId();
    widget.submitNotifier?.addListener(_handleSubmitRequested);
    widget.cancelNotifier?.addListener(_handleCancel);
    _internalController = widget.controller == null
        ? TextEditingController()
        : null;
    _internalFocusNode = widget.focusNode == null ? FocusNode() : null;
    _obscureText = widget.isPasswordInput;
    _setInitialValue();
    _hasText = _controller.text.isNotEmpty;
    widget.isEmptyNotifier?.value = !_hasText;
    _controller.addListener(_handleControllerChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant TextInputComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.submitNotifier != widget.submitNotifier) {
      oldWidget.submitNotifier?.removeListener(_handleSubmitRequested);
      widget.submitNotifier?.addListener(_handleSubmitRequested);
    }
    if (oldWidget.cancelNotifier != widget.cancelNotifier) {
      oldWidget.cancelNotifier?.removeListener(_handleCancel);
      widget.cancelNotifier?.addListener(_handleCancel);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerChanged);
      _internalController?.removeListener(_handleControllerChanged);
      if (oldWidget.controller == null) {
        _internalController?.dispose();
      }
      _internalController = widget.controller == null
          ? TextEditingController()
          : null;
      _setInitialValue();
      _controller.addListener(_handleControllerChanged);
      _hasText = _controller.text.isNotEmpty;
      widget.isEmptyNotifier?.value = !_hasText;
    } else if (oldWidget.initialValue != widget.initialValue) {
      _setInitialValue();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      _internalFocusNode?.removeListener(_handleFocusChanged);
      if (oldWidget.focusNode == null) {
        _internalFocusNode?.dispose();
      }
      _internalFocusNode = widget.focusNode == null ? FocusNode() : null;
      _focusNode.addListener(_handleFocusChanged);
    }
    if (oldWidget.isPasswordInput != widget.isPasswordInput) {
      _obscureText = widget.isPasswordInput;
    }
  }

  @override
  void dispose() {
    widget.submitNotifier?.removeListener(_handleSubmitRequested);
    widget.cancelNotifier?.removeListener(_handleCancel);
    _wrongPasswordResetTimer?.cancel();
    _controller.removeListener(_handleControllerChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  Object? _groupId;
  final _defaultGroupId = Object();
  final _disabledGroupId = Object();

  @override
  void didChangeDependencies() {
    _configureGroupId();
    super.didChangeDependencies();
  }

  void _configureGroupId() {
    _groupId = _defaultGroupId;
    if (widget.isDisabled) {
      _groupId = _disabledGroupId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final message = widget.message;
    final messageColor = _messageColor(colors);
    final prefix = _buildPrefix();
    final suffix = _buildSuffix(colors);
    final suffixTap = _suffixTapHandler;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label!,
                style: TextStyles.bodyBold.copyWith(color: _labelColor(colors)),
              ),
              if (widget.isRequired) ...[
                const SizedBox(width: 2),
                Text(
                  '*',
                  style: TextStyles.bodyBold.copyWith(color: colors.warning),
                ),
              ],
            ],
          ),
          const SizedBox(height: Spacing.sm),
        ],
        TextFieldTapRegion(
          groupId: _groupId,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.isDisabled ? null : _focusNode.requestFocus,
            child: Container(
              height: _isMultiline ? null : _kHeight,
              constraints: _isMultiline
                  ? const BoxConstraints(minHeight: _kHeight)
                  : null,
              decoration: BoxDecoration(
                color: _backgroundColor(colors),
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: _borderColor(colors)),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                fit: _isMultiline ? StackFit.loose : StackFit.expand,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: _isMultiline ? Spacing.lg : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: _isMultiline
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        if (prefix != null) ...[
                          prefix,
                          const SizedBox(width: Spacing.sm),
                        ],
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            enabled: !widget.isDisabled,
                            readOnly: widget.readOnly,
                            autofocus: widget.autofocus,
                            obscureText: _obscureText,
                            maxLines: widget.isPasswordInput
                                ? 1
                                : widget.maxLines ?? (_isMultiline ? null : 1),
                            minLines: widget.isPasswordInput
                                ? null
                                : widget.minLines,
                            keyboardType: widget.keyboardType,
                            textInputAction: widget.textInputAction,
                            textCapitalization: widget.textCapitalization,
                            inputFormatters: _inputFormatters,
                            autofillHints:
                                widget.autofillHints ??
                                (widget.isPasswordInput
                                    ? const [AutofillHints.password]
                                    : const []),
                            autocorrect:
                                widget.autocorrect && !widget.isPasswordInput,
                            enableSuggestions:
                                widget.enableSuggestions &&
                                !widget.isPasswordInput,
                            textAlignVertical: _isMultiline
                                ? TextAlignVertical.top
                                : TextAlignVertical.center,
                            onEditingComplete: _handleEditingComplete,
                            onTapOutside: (_) => _focusNode.unfocus(),
                            style: TextStyles.body.copyWith(
                              color: _textColor(colors),
                            ),
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              hintStyle: TextStyles.body.copyWith(
                                color: _hintColor(colors),
                              ),
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (suffix != null) ...[
                          const SizedBox(width: Spacing.sm),
                          suffix,
                        ],
                      ],
                    ),
                  ),
                  if (suffixTap != null) _suffixTapTarget(suffixTap),
                ],
              ),
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: Spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_messageIcon(messageColor) != null) ...[
                _messageIcon(messageColor)!,
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: Text(
                  message,
                  style: TextStyles.mini.copyWith(color: messageColor),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  bool get _isMultiline =>
      !widget.isPasswordInput &&
      ((widget.maxLines != null && widget.maxLines! > 1) ||
          (widget.minLines != null && widget.minLines! > 1));

  bool get _isError =>
      _incorrectPassword ||
      widget.messageType == TextInputComponentMessageType.error ||
      widget.messageType == TextInputComponentMessageType.alert;

  bool get _hasSuccess =>
      widget.messageType == TextInputComponentMessageType.success;

  List<TextInputFormatter>? get _inputFormatters {
    if (widget.inputFormatters != null) {
      return widget.inputFormatters;
    }
    if (widget.maxLength != null) {
      return [LengthLimitingTextInputFormatter(widget.maxLength)];
    }
    return null;
  }

  Color _backgroundColor(ColorTokens colors) {
    if (!widget.enableFillColor) {
      return Colors.transparent;
    }
    if (widget.isDisabled) {
      return colors.fillDark;
    }
    return colors.fillLight;
  }

  Color _borderColor(ColorTokens colors) {
    if (_isError) {
      return colors.warning;
    }
    if (_hasSuccess) {
      return colors.primary;
    }
    if (_focusNode.hasFocus) {
      return colors.textLighter;
    }
    return colors.strokeFaint;
  }

  Color _textColor(ColorTokens colors) {
    return widget.isDisabled ? colors.textLightest : colors.textBase;
  }

  Color _hintColor(ColorTokens colors) {
    return widget.isDisabled ? colors.textLightest : colors.textLighter;
  }

  Color _labelColor(ColorTokens colors) {
    return widget.isDisabled ? colors.textLightest : colors.textBase;
  }

  Color _messageColor(ColorTokens colors) {
    return switch (widget.messageType) {
      TextInputComponentMessageType.error ||
      TextInputComponentMessageType.alert => colors.warning,
      TextInputComponentMessageType.success => colors.primary,
      TextInputComponentMessageType.helper => colors.textLight,
    };
  }

  Widget? _buildPrefix() {
    if (widget.prefix == null) return null;
    return _slot(widget.prefix!);
  }

  Widget? _buildSuffix(ColorTokens colors) {
    final Widget child;
    if (widget.isPasswordInput) {
      child = Icon(
        _obscureText
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        size: IconSizes.small,
        color: colors.textLighter,
      );
    } else if (widget.isClearable && _hasText) {
      child = Icon(
        Icons.close_rounded,
        size: IconSizes.small,
        color: colors.textLighter,
      );
    } else if (widget.suffix != null) {
      child = widget.suffix!;
    } else {
      return null;
    }

    return _slot(child);
  }

  VoidCallback? get _suffixTapHandler {
    if (widget.isDisabled) return null;
    if (widget.isPasswordInput) {
      return () => setState(() => _obscureText = !_obscureText);
    }
    if (widget.isClearable && _hasText) {
      return () {
        _controller.clear();
        if (widget.shouldUnfocusOnClearOrSubmit) {
          FocusScope.of(context).unfocus();
        }
      };
    }
    return widget.onSuffixTap;
  }

  Widget _suffixTapTarget(VoidCallback onTap) {
    return PositionedDirectional(
      top: _suffixTapTargetTop,
      end: Spacing.lg - (_kSuffixTapTargetSize - _kIconContainerSize) / 2,
      width: _kSuffixTapTargetSize,
      height: _kSuffixTapTargetSize,
      child: GestureDetector(
        key: _suffixTapTargetKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    );
  }

  double get _suffixTapTargetTop {
    if (_isMultiline) {
      return Spacing.lg - (_kSuffixTapTargetSize - _kIconContainerSize) / 2;
    }
    return (_kHeight - _kSuffixTapTargetSize) / 2;
  }

  Key? get _suffixTapTargetKey {
    if (widget.isPasswordInput) {
      return const ValueKey('text-field-password-toggle');
    }
    if (widget.isClearable && _hasText) {
      return const ValueKey('text-field-clear');
    }
    return null;
  }

  Widget? _messageIcon(Color color) {
    if (widget.messageIcon != null) {
      return Icon(widget.messageIcon, size: IconSizes.small, color: color);
    }
    return switch (widget.messageType) {
      TextInputComponentMessageType.alert => Icon(
        Icons.warning_amber_rounded,
        size: IconSizes.small,
        color: color,
      ),
      TextInputComponentMessageType.success => Icon(
        Icons.check_circle_outline_rounded,
        size: IconSizes.small,
        color: color,
      ),
      TextInputComponentMessageType.error ||
      TextInputComponentMessageType.helper => null,
    };
  }

  Widget _slot(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _kIconContainerSize,
        minHeight: _kIconContainerSize,
      ),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }

  void _handleControllerChanged() {
    widget.onChanged?.call(_controller.text);

    final hasText = _controller.text.isNotEmpty;
    if (widget.isEmptyNotifier != null &&
        widget.isEmptyNotifier!.value == hasText) {
      widget.isEmptyNotifier!.value = !hasText;
    }
    if (_incorrectPassword && hasText) {
      setState(() {
        _incorrectPassword = false;
        _hasText = hasText;
      });
      return;
    }
    if (_hasText != hasText && mounted) {
      setState(() => _hasText = hasText);
    }
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleEditingComplete() {
    if (widget.finishAutofillContextOnEditingComplete) {
      TextInput.finishAutofillContext();
    }
    if (widget.onSubmit == null) {
      if (widget.textInputAction == TextInputAction.next) {
        _focusNode.nextFocus();
      } else if (widget.shouldUnfocusOnClearOrSubmit) {
        FocusScope.of(context).unfocus();
      }
      return;
    }
    _handleSubmitRequested();
  }

  void _handleSubmitRequested() {
    unawaited(_handleSubmit());
  }

  Future<void> _handleSubmit() async {
    if (widget.onSubmit == null || widget.isDisabled || _isSubmitting) {
      return;
    }
    final popNavAfterSubmission = widget.popNavAfterSubmission;

    setState(() {
      _isSubmitting = true;
    });

    if (widget.shouldUnfocusOnClearOrSubmit) {
      FocusScope.of(context).unfocus();
    }

    try {
      await widget.onSubmit!.call(_controller.text);
    } catch (error) {
      if (mounted) {
        if (error.toString().contains('Incorrect password')) {
          _surfaceWrongPasswordState();
        }
        setState(() => _isSubmitting = false);
        if (popNavAfterSubmission) {
          _popNavigatorStack(
            context,
            e: error is Exception ? error : Exception(error.toString()),
          );
        }
      }
      if (!popNavAfterSubmission) {
        rethrow;
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (widget.popNavAfterSubmission) _popNavigatorStack(context);
  }

  void _handleCancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
      return;
    }
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  void _popNavigatorStack(BuildContext context, {Exception? e}) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(e);
    }
  }

  void _setInitialValue() {
    if (widget.initialValue == null) return;

    final formattedInitialValue = _formatInitialValue(
      widget.initialValue!,
      widget.inputFormatters,
    );
    _controller.value = TextEditingValue(
      text: formattedInitialValue,
      selection: TextSelection.collapsed(offset: formattedInitialValue.length),
    );
  }

  String _formatInitialValue(
    String initialValue,
    List<TextInputFormatter>? formatters,
  ) {
    if (formatters == null || formatters.isEmpty) return initialValue;

    var formattedValue = initialValue;
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

  void _surfaceWrongPasswordState() {
    setState(() {
      _incorrectPassword = true;
      HapticFeedback.vibrate();
    });
    _wrongPasswordResetTimer?.cancel();
    _wrongPasswordResetTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _incorrectPassword = false);
      }
    });
  }
}
