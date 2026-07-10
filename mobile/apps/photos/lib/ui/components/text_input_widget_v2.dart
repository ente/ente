import 'dart:async';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/execution_states.dart';
import 'package:photos/models/typedefs.dart';
import 'package:photos/theme/colors.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/theme/text_style.dart';
import 'package:photos/ui/components/models/text_input_type_v2.dart';

/// A styled text input widget with built-in support for submission states,
/// password visibility toggling, clearable input, and validation messages.
///
/// To show a wrong-password state, throw an exception containing
/// "Incorrect password" in [onSubmit].
class TextInputWidgetV2 extends StatefulWidget {
  final String? label;
  final String? message;
  final String? hintText;
  final String? initialValue;
  final bool? autoFocus;
  final int? maxLength;

  /// The widget listens to this notifier and executes [onSubmit] when notified.
  /// The value of this notifier is irrelevant.
  final ValueNotifier? submitNotifier;

  /// The widget listens to this notifier and clears and unfocuses the
  /// text field when notified.
  final ValueNotifier? cancelNotifier;
  final bool alwaysShowSuccessState;
  final bool showOnlyLoadingState;
  final FutureVoidCallbackParamStr? onSubmit;
  final VoidCallbackParamStr? onChange;
  final bool popNavAfterSubmission;
  final bool shouldSurfaceExecutionStates;
  final TextCapitalization? textCapitalization;
  final bool isPasswordInput;

  /// Shows a clear (x) icon as a trailing widget. Unrelated to [onCancel].
  final bool isClearable;
  final bool shouldUnfocusOnClearOrSubmit;
  final FocusNode? focusNode;
  final VoidCallback? onCancel;
  final TextEditingController? textEditingController;
  final ValueNotifier<bool>? isEmptyNotifier;
  final List<TextInputFormatter>? textInputFormatter;
  final TextInputType? keyboardType;
  final bool enableFillColor;
  final bool autoCorrect;
  final bool isRequired;
  final Widget? leadingWidget;
  final Widget? trailingWidget;
  final TextInputMessageType messageType;
  final IconData? messageIcon;
  final bool isDisabled;
  final bool shouldStickToDarkTheme;
  final List<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final bool finishAutofillContextOnEditingComplete;

  const TextInputWidgetV2({
    this.onSubmit,
    this.onChange,
    this.label,
    this.message,
    this.hintText,
    this.initialValue,
    this.autoFocus,
    this.maxLength,
    this.submitNotifier,
    this.cancelNotifier,
    this.alwaysShowSuccessState = false,
    this.showOnlyLoadingState = false,
    this.popNavAfterSubmission = false,
    this.shouldSurfaceExecutionStates = true,
    this.textCapitalization = TextCapitalization.none,
    this.isPasswordInput = false,
    this.isClearable = false,
    this.shouldUnfocusOnClearOrSubmit = false,
    this.focusNode,
    this.onCancel,
    this.textEditingController,
    this.isEmptyNotifier,
    this.textInputFormatter,
    this.keyboardType,
    this.enableFillColor = true,
    this.autoCorrect = true,
    this.isRequired = false,
    this.leadingWidget,
    this.trailingWidget,
    this.messageType = TextInputMessageType.guide,
    this.messageIcon,
    this.isDisabled = false,
    this.shouldStickToDarkTheme = false,
    this.autofillHints,
    this.maxLines,
    this.minLines,
    this.finishAutofillContextOnEditingComplete = false,
    super.key,
  });

  @override
  State<TextInputWidgetV2> createState() => _TextInputWidgetV2State();
}

class _TextInputWidgetV2State extends State<TextInputWidgetV2>
    with SingleTickerProviderStateMixin {
  static const _kHeight = 52.0;
  static const _kRadius = 16.0;
  static const _kHorizontalPadding = 16.0;
  static const _kIconContainerSize = 24.0;

  final _logger = Logger('TextInputWidgetV2');

  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  late final AnimationController _loadingController;

  ExecutionState _executionState = ExecutionState.idle;
  late final ValueNotifier<bool> _obscureTextNotifier;

  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final bool _shouldDisposeTextController;
  late final bool _shouldDisposeFocusNode;

  bool _isFocused = false;
  bool _incorrectPassword = false;

  /// Stored so it can be passed via Navigator.pop() when the widget is used
  /// inside a dialog and [popNavAfterSubmission] is true.
  Exception? _exception;

  @override
  void initState() {
    super.initState();

    widget.submitNotifier?.addListener(_onSubmit);
    widget.cancelNotifier?.addListener(_onCancel);

    _textController = widget.textEditingController ?? TextEditingController();
    _shouldDisposeTextController = widget.textEditingController == null;
    _textController.addListener(_onTextChangedInternal);

    _focusNode = widget.focusNode ?? FocusNode();
    _shouldDisposeFocusNode = widget.focusNode == null;
    _focusNode.addListener(_onFocusChanged);

    _obscureTextNotifier = ValueNotifier(widget.isPasswordInput);
    _obscureTextNotifier.addListener(_safeRefresh);

    _setInitialValue();

    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _syncLoadingController();
  }

  @override
  void didUpdateWidget(covariant TextInputWidgetV2 oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.submitNotifier != widget.submitNotifier) {
      oldWidget.submitNotifier?.removeListener(_onSubmit);
      widget.submitNotifier?.addListener(_onSubmit);
    }
    if (oldWidget.cancelNotifier != widget.cancelNotifier) {
      oldWidget.cancelNotifier?.removeListener(_onCancel);
      widget.cancelNotifier?.addListener(_onCancel);
    }

    if (oldWidget.isPasswordInput != widget.isPasswordInput) {
      _obscureTextNotifier.value = widget.isPasswordInput;
    }

    _syncLoadingController();
  }

  @override
  void dispose() {
    widget.submitNotifier?.removeListener(_onSubmit);
    widget.cancelNotifier?.removeListener(_onCancel);
    _debouncer.cancelDebounceTimer();

    _textController.removeListener(_onTextChangedInternal);
    if (_shouldDisposeTextController) {
      _textController.dispose();
    }

    _focusNode.removeListener(_onFocusChanged);
    if (_shouldDisposeFocusNode) {
      _focusNode.dispose();
    }

    _obscureTextNotifier.removeListener(_safeRefresh);
    _obscureTextNotifier.dispose();

    _loadingController.dispose();
    super.dispose();
  }

  void _syncLoadingController() {
    final showLoading =
        _executionState == ExecutionState.inProgress &&
        widget.shouldSurfaceExecutionStates;
    if (showLoading) {
      if (!_loadingController.isAnimating) {
        _loadingController.repeat();
      }
    } else {
      if (_loadingController.isAnimating) {
        _loadingController.stop();
      }
    }
  }

  void _safeRefresh() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (_isFocused != focused) {
      setState(() => _isFocused = focused);
    }
  }

  void _onTextChangedInternal() {
    widget.onChange?.call(_textController.text);

    final isEmpty = _textController.text.isEmpty;

    if (widget.isEmptyNotifier != null) {
      if (widget.isEmptyNotifier!.value != isEmpty) {
        widget.isEmptyNotifier!.value = isEmpty;
      }
    }

    if (_incorrectPassword && !isEmpty) {
      setState(() => _incorrectPassword = false);
    } else if (widget.isClearable) {
      setState(() {});
    }
  }

  bool get _isError =>
      _incorrectPassword ||
      _executionState == ExecutionState.error ||
      widget.messageType == TextInputMessageType.error ||
      widget.messageType == TextInputMessageType.alert;

  bool get _isSuccess =>
      _executionState == ExecutionState.successful &&
      widget.shouldSurfaceExecutionStates;

  bool get _showLoading =>
      _executionState == ExecutionState.inProgress &&
      widget.shouldSurfaceExecutionStates;

  bool get _showSuccess =>
      _executionState == ExecutionState.successful &&
      widget.shouldSurfaceExecutionStates;

  bool get _isMultiline =>
      !widget.isPasswordInput &&
      ((widget.maxLines != null && widget.maxLines! > 1) ||
          (widget.minLines != null && widget.minLines! > 1));

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.shouldStickToDarkTheme
        ? darkScheme
        : getEnteColorScheme(context);
    final textTheme = widget.shouldStickToDarkTheme
        ? darkTextTheme
        : getEnteTextTheme(context);

    final colors = buildTextInputTheme(colorScheme).resolve(
      enableFillColor: widget.enableFillColor,
      isDisabled: widget.isDisabled,
      isFocused: _isFocused,
      isError: _isError,
      isSuccess:
          _isSuccess || widget.messageType == TextInputMessageType.success,
      messageType: widget.messageType,
    );

    final leading = _buildLeadingWidget(colors);
    final trailing = _buildTrailingWidget(colors, colorScheme);
    final messageRow = _buildMessageRow(colors, textTheme);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label!,
                style: textTheme.smallBold.copyWith(color: colors.labelColor),
              ),
              if (widget.isRequired) ...[
                const SizedBox(width: 2),
                Text(
                  '*',
                  style: textTheme.smallBold.copyWith(
                    color: colorScheme.redBase,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
        ],
        GestureDetector(
          onTap: widget.isDisabled ? null : _focusNode.requestFocus,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: _isMultiline ? null : _kHeight,
            constraints: _isMultiline
                ? const BoxConstraints(minHeight: _kHeight)
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: _kHorizontalPadding,
              vertical: _isMultiline ? 16 : 0,
            ),
            decoration: BoxDecoration(
              color: colors.backgroundColor,
              borderRadius: BorderRadius.circular(_kRadius),
              border: Border.all(color: colors.borderColor, width: 1),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 8)],
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    enabled: !widget.isDisabled,
                    keyboardType: widget.keyboardType,
                    textCapitalization: widget.textCapitalization!,
                    autofocus: widget.autoFocus ?? false,
                    autocorrect: widget.autoCorrect,
                    maxLines: widget.isPasswordInput
                        ? 1
                        : widget.maxLines ?? (_isMultiline ? null : 1),
                    minLines: widget.isPasswordInput ? null : widget.minLines,
                    autofillHints:
                        widget.autofillHints ??
                        (widget.isPasswordInput
                            ? const [AutofillHints.password]
                            : const []),
                    inputFormatters:
                        widget.textInputFormatter ??
                        (widget.maxLength != null
                            ? [
                                LengthLimitingTextInputFormatter(
                                  widget.maxLength,
                                ),
                              ]
                            : null),
                    obscureText: _obscureTextNotifier.value,
                    style: textTheme.body.copyWith(color: colors.textColor),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      hintText: widget.hintText,
                      hintStyle: textTheme.body.copyWith(
                        color: colors.hintColor,
                      ),
                    ),
                    onEditingComplete: _handleEditingComplete,
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
          ),
        ),
        if (messageRow != null) ...[const SizedBox(height: 8), messageRow],
      ],
    );
  }

  Widget? _buildLeadingWidget(TextInputColors colors) {
    if (widget.leadingWidget == null) return null;
    return SizedBox(
      height: _kIconContainerSize,
      width: _kIconContainerSize,
      child: Center(
        child: IconTheme(
          data: IconThemeData(color: colors.iconColor),
          child: widget.leadingWidget!,
        ),
      ),
    );
  }

  Widget? _buildTrailingWidget(
    TextInputColors colors,
    EnteColorScheme colorScheme,
  ) {
    final Widget child;

    if (_showLoading) {
      child = RotationTransition(
        turns: _loadingController,
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedLoading03,
          color: colors.iconColor,
        ),
      );
    } else if (_showSuccess) {
      child = HugeIcon(
        icon: HugeIcons.strokeRoundedTick02,
        color: colorScheme.greenBase,
      );
    } else if (widget.isPasswordInput) {
      child = GestureDetector(
        onTap: widget.isDisabled
            ? null
            : () => _obscureTextNotifier.value = !_obscureTextNotifier.value,
        child: HugeIcon(
          icon: _obscureTextNotifier.value
              ? HugeIcons.strokeRoundedViewOffSlash
              : HugeIcons.strokeRoundedView,
          color: colors.iconColor,
        ),
      );
    } else if (widget.isClearable && _textController.text.isNotEmpty) {
      child = GestureDetector(
        onTap: widget.isDisabled
            ? null
            : () {
                _textController.clear();
                if (widget.shouldUnfocusOnClearOrSubmit) {
                  FocusScope.of(context).unfocus();
                }
              },
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedCancel01,
          color: colors.iconColor,
        ),
      );
    } else if (widget.trailingWidget != null) {
      child = IconTheme(
        data: IconThemeData(color: colors.iconColor),
        child: widget.trailingWidget!,
      );
    } else {
      return null;
    }

    return SizedBox(
      height: _kIconContainerSize,
      width: _kIconContainerSize,
      child: Center(child: child),
    );
  }

  Widget? _buildMessageRow(TextInputColors colors, EnteTextTheme textTheme) {
    if (widget.message == null) return null;

    final messageColor = colors.messageColor;
    final icon = _buildMessageIcon(messageColor);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[icon, const SizedBox(width: 8)],
        Expanded(
          child: Text(
            widget.message!,
            style: textTheme.small.copyWith(color: messageColor),
          ),
        ),
      ],
    );
  }

  Widget? _buildMessageIcon(Color color) {
    if (widget.messageIcon != null) {
      return Icon(widget.messageIcon, size: 18, color: color);
    }

    return switch (widget.messageType) {
      TextInputMessageType.alert => HugeIcon(
        icon: HugeIcons.strokeRoundedAlert02,
        size: 18,
        color: color,
      ),
      TextInputMessageType.success => HugeIcon(
        icon: HugeIcons.strokeRoundedTick02,
        size: 18,
        color: color,
      ),
      TextInputMessageType.error || TextInputMessageType.guide => null,
    };
  }

  void _handleEditingComplete() {
    if (widget.finishAutofillContextOnEditingComplete) {
      TextInput.finishAutofillContext();
    }
    if (widget.onSubmit == null) {
      if (widget.shouldUnfocusOnClearOrSubmit) {
        FocusScope.of(context).unfocus();
      }
      return;
    }
    _onSubmit();
  }

  void _onSubmit() async {
    if (widget.onSubmit == null || widget.isDisabled) return;

    _debouncer.run(
      () => Future(() {
        if (!mounted) return;
        setState(() => _executionState = ExecutionState.inProgress);
        _syncLoadingController();
      }),
    );

    if (widget.shouldUnfocusOnClearOrSubmit) {
      FocusScope.of(context).unfocus();
    }

    try {
      await widget.onSubmit!.call(_textController.text);
    } catch (e) {
      _executionState = ExecutionState.error;
      _debouncer.cancelDebounceTimer();
      _exception = e is Exception ? e : Exception(e.toString());
      if (e.toString().contains('Incorrect password')) {
        _logger.warning('Incorrect password');
        _executionState = ExecutionState.idle;
        _syncLoadingController();
        _surfaceWrongPasswordState();
        return;
      }
      if (!widget.popNavAfterSubmission) {
        rethrow;
      }
    }

    if (widget.alwaysShowSuccessState && _debouncer.isActive()) {
      _executionState = ExecutionState.successful;
    }
    _debouncer.cancelDebounceTimer();

    if (_executionState == ExecutionState.successful) {
      setState(() {});
      _syncLoadingController();
    }

    // When onSubmit takes roughly as long as the debounce duration, the
    // debounce callback can fire during or after the checks below, leaving
    // the state stuck at idle. This short delay lets the debouncer finish
    // first.
    await Future.delayed(const Duration(milliseconds: 5));

    if (_executionState == ExecutionState.inProgress ||
        _executionState == ExecutionState.error) {
      if (_executionState == ExecutionState.inProgress) {
        if (!mounted) return;
        if (widget.showOnlyLoadingState) {
          setState(() => _executionState = ExecutionState.idle);
          _syncLoadingController();
          _popNavigatorStack(context);
        } else {
          setState(() {
            _executionState = ExecutionState.successful;
            _syncLoadingController();
            Future.delayed(
              Duration(
                seconds: widget.shouldSurfaceExecutionStates
                    ? (widget.popNavAfterSubmission ? 1 : 2)
                    : 0,
              ),
              () {
                if (widget.popNavAfterSubmission) {
                  if (!mounted) return;
                  _popNavigatorStack(context);
                }
                if (mounted) {
                  setState(() => _executionState = ExecutionState.idle);
                  _syncLoadingController();
                }
              },
            );
          });
        }
      }

      if (_executionState == ExecutionState.error) {
        setState(() {
          _executionState = ExecutionState.idle;
          _syncLoadingController();
        });
        if (widget.popNavAfterSubmission) {
          unawaited(
            Future.delayed(Duration.zero, () {
              if (!mounted) return;
              _popNavigatorStack(context, e: _exception);
            }),
          );
        }
      }
    } else if (widget.popNavAfterSubmission) {
      unawaited(
        Future.delayed(
          Duration(seconds: widget.alwaysShowSuccessState ? 1 : 0),
          () {
            if (!mounted) return;
            _popNavigatorStack(context);
          },
        ),
      );
    }
  }

  void _onCancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      _textController.clear();
      FocusScope.of(context).unfocus();
    }
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
      widget.textInputFormatter,
    );
    _textController.value = TextEditingValue(
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
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _incorrectPassword = false);
      });
    });
  }
}
