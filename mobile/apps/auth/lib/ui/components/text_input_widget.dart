import 'package:ente_auth/models/execution_states.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/common/loading_widget.dart';
import 'package:ente_auth/ui/components/separators.dart';
import 'package:ente_auth/utils/debouncer.dart';
import 'package:ente_base/typedefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class TextInputWidget extends StatefulWidget {
  final String? label;
  final String? message;
  final String? hintText;
  final IconData? prefixIcon;
  final String? initialValue;
  final Alignment? alignMessage;
  final bool? autoFocus;
  final int? maxLength;

  ///TextInputWidget will listen to this notifier and executes onSubmit when
  ///notified.
  final ValueNotifier? submitNotifier;
  final bool alwaysShowSuccessState;
  final bool showOnlyLoadingState;
  final FutureVoidCallbackParamStr? onSubmit;
  final VoidCallbackParamStr? onChange;
  final bool popNavAfterSubmission;
  final bool shouldSurfaceExecutionStates;
  final TextCapitalization? textCapitalization;
  final bool isPasswordInput;
  final Iterable<String>? autofillHints;
  final bool cancellable;
  final bool shouldUnfocusOnCancelOrSubmit;
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
    this.alwaysShowSuccessState = false,
    this.showOnlyLoadingState = false,
    this.popNavAfterSubmission = false,
    this.shouldSurfaceExecutionStates = true,
    this.textCapitalization = TextCapitalization.none,
    this.isPasswordInput = false,
    this.autofillHints,
    this.cancellable = false,
    this.shouldUnfocusOnCancelOrSubmit = false,
    super.key,
  });

  @override
  State<TextInputWidget> createState() => _TextInputWidgetState();
}

class _TextInputWidgetState extends State<TextInputWidget> {
  final _logger = Logger("TextInputWidget");
  ExecutionState executionState = ExecutionState.idle;
  final _textController = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  late final ValueNotifier<bool> _obscureTextNotifier;

  ///This is to pass if the TextInputWidget is in a dialog and an error is
  ///thrown in executing onSubmit by passing it as arg in Navigator.pop()
  Exception? _exception;
  bool _incorrectPassword = false;
  @override
  void initState() {
    widget.submitNotifier?.addListener(_onSubmit);

    if (widget.initialValue != null) {
      _textController.value = TextEditingValue(
        text: widget.initialValue!,
        selection: TextSelection.collapsed(offset: widget.initialValue!.length),
      );
    }
    if (widget.onChange != null) {
      _textController.addListener(() {
        widget.onChange!.call(_textController.text);
      });
    }
    _obscureTextNotifier = ValueNotifier(widget.isPasswordInput);
    _obscureTextNotifier.addListener(_safeRefresh);
    super.initState();
  }

  @override
  void dispose() {
    widget.submitNotifier?.removeListener(_onSubmit);
    _obscureTextNotifier.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (executionState == ExecutionState.successful) {
      Future.delayed(
        Duration(seconds: widget.popNavAfterSubmission ? 1 : 2),
        () {
          setState(() {
            executionState = ExecutionState.idle;
          });
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
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: Material(
          child: TextFormField(
            textCapitalization: widget.textCapitalization!,
            autofocus: widget.autoFocus ?? false,
            controller: _textController,
            inputFormatters: widget.maxLength != null
                ? [LengthLimitingTextInputFormatter(50)]
                : null,
            autofillHints:
                widget.autofillHints ??
                (widget.isPasswordInput
                    ? const [AutofillHints.password]
                    : null),
            obscureText: _obscureTextNotifier.value,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: textTheme.body.copyWith(color: colorScheme.textMuted),
              filled: true,
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
              suffixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 175),
                  switchInCurve: Curves.easeInExpo,
                  switchOutCurve: Curves.easeOutExpo,
                  child: SuffixIconWidget(
                    key: ValueKey(executionState),
                    executionState: executionState,
                    shouldSurfaceExecutionStates:
                        widget.shouldSurfaceExecutionStates,
                    obscureTextNotifier: _obscureTextNotifier,
                    isPasswordInput: widget.isPasswordInput,
                    textController: _textController,
                    isCancellable: widget.cancellable,
                    shouldUnfocusOnCancelOrSubmit:
                        widget.shouldUnfocusOnCancelOrSubmit,
                  ),
                ),
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
                minHeight: 24,
                minWidth: 48,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon, color: colorScheme.strokeMuted)
                  : null,
            ),
            onEditingComplete: () {
              _onSubmit();
            },
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
        setState(() {
          executionState = ExecutionState.inProgress;
        });
      }),
    );
    if (widget.shouldUnfocusOnCancelOrSubmit) {
      FocusScope.of(context).unfocus();
    }
    try {
      await widget.onSubmit!.call(_textController.text);
    } catch (e) {
      executionState = ExecutionState.error;
      _debouncer.cancelDebounce();
      _exception = e as Exception;
      if (e.toString().contains("Incorrect password")) {
        _logger.warning("Incorrect password");
        _surfaceWrongPasswordState();
      }
      if (!widget.popNavAfterSubmission) {
        rethrow;
      }
    }
    widget.alwaysShowSuccessState && _debouncer.isActive()
        ? executionState = ExecutionState.successful
        : null;
    _debouncer.cancelDebounce();
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
      if (!mounted) return;
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
          widget.popNavAfterSubmission
              ? Future.delayed(const Duration(seconds: 0), () {
                  if (!mounted) return;
                  _popNavigatorStack(context, e: _exception);
                })
              : null;
        });
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

  void _popNavigatorStack(BuildContext context, {Exception? e}) {
    Navigator.of(context).canPop() ? Navigator.of(context).pop(e) : null;
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
  final bool isCancellable;
  final bool shouldUnfocusOnCancelOrSubmit;

  const SuffixIconWidget({
    required this.executionState,
    required this.shouldSurfaceExecutionStates,
    required this.textController,
    this.obscureTextNotifier,
    this.isPasswordInput = false,
    this.isCancellable = false,
    this.shouldUnfocusOnCancelOrSubmit = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final Widget trailingWidget;
    final colorScheme = getEnteColorScheme(context);
    if (executionState == ExecutionState.idle ||
        !shouldSurfaceExecutionStates) {
      if (isCancellable) {
        trailingWidget = GestureDetector(
          onTap: () {
            textController.clear();
            if (shouldUnfocusOnCancelOrSubmit) {
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
        trailingWidget = const SizedBox.shrink();
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
      trailingWidget = const SizedBox.shrink();
    }
    return trailingWidget;
  }
}
