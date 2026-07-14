import 'dart:async';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:logging/logging.dart";
import 'package:photos/models/execution_states.dart';
import 'package:photos/models/typedefs.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/utils/separators_util.dart';

///To show wrong password state, throw an exception with the message
///"Incorrect password" in onSubmit.
class TextInputWidget extends StatefulWidget {
  final String? label;
  final String? message;
  final String? hintText;
  final IconData? prefixIcon;
  final String? initialValue;
  final Alignment? alignMessage;
  final bool? autoFocus;
  final int? maxLength;
  final double borderRadius;

  ///TextInputWidget will listen to this notifier and executes onSubmit when
  ///notified. Value of this notifier is irrelevant.
  final ValueNotifier? submitNotifier;

  ///TextInputWidget will listen to this notifier and clears and unfocuses the
  ///textFiled when notified.
  final ValueNotifier? cancelNotifier;
  final bool alwaysShowSuccessState;
  final bool showOnlyLoadingState;
  final FutureVoidCallbackParamStr? onSubmit;
  final VoidCallbackParamStr? onChange;
  final bool popNavAfterSubmission;
  final bool shouldSurfaceExecutionStates;
  final TextCapitalization? textCapitalization;

  /// WARNING: Do not use this widget for password input. Create a separate PasswordInputWidget. This widget is becoming bloated and hard to maintain, so will create a PasswordInputWidget and remove this field from this widget in future
  final bool isPasswordInput;

  ///Clear comes in the form of a suffix icon. It is unrelated to onCancel.
  final bool isClearable;
  final bool shouldUnfocusOnClearOrSubmit;
  final FocusNode? focusNode;
  final VoidCallback? onCancel;
  final TextEditingController? textEditingController;
  final ValueNotifier? isEmptyNotifier;
  final List<TextInputFormatter>? textInputFormatter;
  final TextInputType? keyboardType;
  final bool enableFillColor;
  final bool autoCorrect;
  const TextInputWidget({
    this.onSubmit,
    this.onChange,
    this.label,
    this.message,
    this.hintText,
    this.prefixIcon,
    this.initialValue,
    this.alignMessage,
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
    this.borderRadius = 8,
    this.focusNode,
    this.onCancel,
    this.textEditingController,
    this.isEmptyNotifier,
    this.textInputFormatter,
    this.keyboardType,
    this.enableFillColor = true,
    this.autoCorrect = true,
    super.key,
  });

  @override
  State<TextInputWidget> createState() => _TextInputWidgetState();
}

class _TextInputWidgetState extends State<TextInputWidget> {
  final _logger = Logger("TextInputWidget");
  ExecutionState executionState = ExecutionState.idle;
  late final TextEditingController _textController;
  late final bool _ownsTextController;
  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  late final ValueNotifier<bool> _obscureTextNotifier;
  VoidCallback? _onChangeListener;
  VoidCallback? _isEmptyListener;

  ///This is to pass if the TextInputWidget is in a dialog and an error is
  ///thrown in executing onSubmit by passing it as arg in Navigator.pop()
  Exception? _exception;
  bool _incorrectPassword = false;

  @override
  void initState() {
    super.initState();
    widget.submitNotifier?.addListener(_onSubmit);
    widget.cancelNotifier?.addListener(_onCancel);
    _ownsTextController = widget.textEditingController == null;
    _textController = widget.textEditingController ?? TextEditingController();

    _setInitialValue();

    if (widget.onChange != null) {
      _onChangeListener = () {
        widget.onChange!.call(_textController.text);
      };
      _textController.addListener(_onChangeListener!);
    }
    _obscureTextNotifier = ValueNotifier(widget.isPasswordInput);
    _obscureTextNotifier.addListener(_safeRefresh);

    if (widget.isEmptyNotifier != null) {
      _isEmptyListener = () {
        widget.isEmptyNotifier!.value = _textController.text.isEmpty;
      };
      _textController.addListener(_isEmptyListener!);
    }
  }

  @override
  void dispose() {
    widget.submitNotifier?.removeListener(_onSubmit);
    widget.cancelNotifier?.removeListener(_onCancel);
    _debouncer.cancelDebounceTimer();
    if (_onChangeListener != null) {
      _textController.removeListener(_onChangeListener!);
    }
    if (_isEmptyListener != null) {
      _textController.removeListener(_isEmptyListener!);
    }
    _obscureTextNotifier.dispose();
    if (_ownsTextController) {
      _textController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (executionState == ExecutionState.successful) {
      Future.delayed(
        Duration(seconds: widget.popNavAfterSubmission ? 1 : 2),
        () {
          if (mounted) {
            setState(() {
              executionState = ExecutionState.idle;
            });
          }
        },
      );
    }
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    var textInputChildren = <Widget>[];
    if (widget.label != null) {
      textInputChildren.add(Text(widget.label!));
    }
    textInputChildren.add(
      ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(widget.borderRadius)),
        child: Material(
          child: TextFormField(
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization!,
            autofocus: widget.autoFocus ?? false,
            autofillHints: widget.isPasswordInput
                ? [AutofillHints.password]
                : [],
            controller: _textController,
            focusNode: widget.focusNode,
            inputFormatters:
                widget.textInputFormatter ??
                (widget.maxLength != null
                    ? [LengthLimitingTextInputFormatter(50)]
                    : null),
            obscureText: _obscureTextNotifier.value,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: textTheme.body.copyWith(color: colorScheme.textMuted),
              filled: widget.enableFillColor,
              fillColor: colorScheme.fillFaint,
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              border: const UnderlineInputBorder(borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _incorrectPassword
                      ? const Color.fromRGBO(245, 42, 42, 1)
                      : colorScheme.strokeFaint,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: SuffixIconWidget(
                key: ValueKey(executionState),
                executionState: executionState,
                shouldSurfaceExecutionStates:
                    widget.shouldSurfaceExecutionStates,
                obscureTextNotifier: _obscureTextNotifier,
                isPasswordInput: widget.isPasswordInput,
                textController: _textController,
                isClearable: widget.isClearable,
                shouldUnfocusOnClearOrSubmit:
                    widget.shouldUnfocusOnClearOrSubmit,
              ),
              prefixIconConstraints: const BoxConstraints(
                maxHeight: 44,
                maxWidth: 44,
                minHeight: 44,
                minWidth: 44,
              ),
              suffixIconConstraints: const BoxConstraints(
                maxHeight: 24,
                maxWidth: 48,
                minHeight: 0,
                minWidth: 0,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon, color: colorScheme.strokeMuted)
                  : null,
            ),
            onEditingComplete: () {
              _onSubmit();
            },
            autocorrect: widget.autoCorrect,
          ),
        ),
      ),
    );
    if (widget.message != null) {
      textInputChildren.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: widget.alignMessage ?? Alignment.centerLeft,
            child: Text(
              widget.message!,
              style: textTheme.small.copyWith(color: colorScheme.textMuted),
            ),
          ),
        ),
      );
    }
    textInputChildren = addSeparators(
      textInputChildren,
      const SizedBox(height: 4),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: textInputChildren,
    );
  }

  void _safeRefresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onSubmit() async {
    _debouncer.run(
      () => Future(() {
        if (!mounted) return;
        setState(() {
          executionState = ExecutionState.inProgress;
        });
      }),
    );
    if (widget.shouldUnfocusOnClearOrSubmit) {
      FocusScope.of(context).unfocus();
    }
    try {
      await widget.onSubmit!.call(_textController.text);
    } catch (e) {
      executionState = ExecutionState.error;
      _debouncer.cancelDebounceTimer();
      _exception = e is Exception ? e : Exception(e.toString());
      if (e.toString().contains("Incorrect password")) {
        _logger.warning("Incorrect password");
        executionState = ExecutionState.idle;
        _surfaceWrongPasswordState();
        return;
      }
      if (!widget.popNavAfterSubmission) {
        rethrow;
      }
    }
    widget.alwaysShowSuccessState && _debouncer.isActive()
        ? executionState = ExecutionState.successful
        : null;
    _debouncer.cancelDebounceTimer();
    if (executionState == ExecutionState.successful) {
      setState(() {});
    }

    // when the time taken by widget.onSubmit is approximately equal to the debounce
    // time, the callback is getting executed when/after the if condition
    // below is executing/executed which results in execution state stuck at
    // idle state. This Future is for delaying the execution of the if
    // condition so that the calback in the debouncer finishes execution before.
    await Future.delayed(const Duration(milliseconds: 5));
    if (executionState == ExecutionState.inProgress ||
        executionState == ExecutionState.error) {
      if (executionState == ExecutionState.inProgress) {
        if (mounted) {
          if (widget.showOnlyLoadingState) {
            setState(() {
              executionState = ExecutionState.idle;
            });
            _popNavigatorStack(context);
          } else {
            setState(() {
              executionState = ExecutionState.successful;
              Future.delayed(
                Duration(
                  seconds: widget.shouldSurfaceExecutionStates
                      ? (widget.popNavAfterSubmission ? 1 : 2)
                      : 0,
                ),
                () {
                  if (!mounted) return;
                  widget.popNavAfterSubmission
                      ? _popNavigatorStack(context)
                      : null;
                  if (mounted) {
                    setState(() {
                      executionState = ExecutionState.idle;
                    });
                  }
                },
              );
            });
          }
        }
      }
      if (executionState == ExecutionState.error) {
        setState(() {
          executionState = ExecutionState.idle;
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
    } else {
      if (widget.popNavAfterSubmission) {
        Future.delayed(
          Duration(seconds: widget.alwaysShowSuccessState ? 1 : 0),
          () {
            if (!mounted) return;
            _popNavigatorStack(context);
          },
        );
      }
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
    Navigator.of(context).canPop() ? Navigator.of(context).pop(e) : null;
  }

  void _setInitialValue() {
    if (widget.initialValue != null) {
      final formattedInitialValue = _formatInitialValue(
        widget.initialValue!,
        widget.textInputFormatter,
      );
      _textController.value = TextEditingValue(
        text: formattedInitialValue,
        selection: TextSelection.collapsed(
          offset: formattedInitialValue.length,
        ),
      );
    }
  }

  String _formatInitialValue(
    String initialValue,
    List<TextInputFormatter>? formatters,
  ) {
    if (formatters == null || formatters.isEmpty) {
      return initialValue;
    }

    String formattedValue = initialValue;

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
        if (mounted) {
          setState(() {
            _incorrectPassword = false;
          });
        }
      });
    });
  }
}

//todo: Add clear and custom icon for suffic icon
class SuffixIconWidget extends StatelessWidget {
  final ExecutionState executionState;
  final bool shouldSurfaceExecutionStates;
  final TextEditingController textController;
  final ValueNotifier? obscureTextNotifier;
  final bool isPasswordInput;
  final bool isClearable;
  final bool shouldUnfocusOnClearOrSubmit;

  const SuffixIconWidget({
    required this.executionState,
    required this.shouldSurfaceExecutionStates,
    required this.textController,
    this.obscureTextNotifier,
    this.isPasswordInput = false,
    this.isClearable = false,
    this.shouldUnfocusOnClearOrSubmit = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final Widget? trailingWidget;
    final colorScheme = getEnteColorScheme(context);
    if (executionState == ExecutionState.idle ||
        !shouldSurfaceExecutionStates) {
      if (isClearable) {
        trailingWidget = GestureDetector(
          onTap: () {
            textController.clear();
            if (shouldUnfocusOnClearOrSubmit) {
              FocusScope.of(context).unfocus();
            }
          },
          child: Icon(Icons.cancel_rounded, color: colorScheme.strokeMuted),
        );
      } else if (isPasswordInput) {
        assert(obscureTextNotifier != null);
        trailingWidget = GestureDetector(
          onTap: () {
            obscureTextNotifier!.value = !obscureTextNotifier!.value;
          },
          child: Icon(
            obscureTextNotifier!.value
                ? Icons.visibility_off_outlined
                : Icons.visibility,
            color: obscureTextNotifier!.value ? colorScheme.strokeMuted : null,
          ),
        );
      } else {
        trailingWidget = null;
      }
    } else if (executionState == ExecutionState.inProgress) {
      trailingWidget = EnteLoadingWidget(color: colorScheme.strokeMuted);
    } else if (executionState == ExecutionState.successful) {
      trailingWidget = Icon(
        Icons.check_outlined,
        size: 22,
        color: colorScheme.primary500,
      );
    } else {
      trailingWidget = null;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 175),
      switchInCurve: Curves.easeInExpo,
      switchOutCurve: Curves.easeOutExpo,
      child: trailingWidget != null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: trailingWidget,
            )
          : const SizedBox.shrink(),
    );
  }
}
