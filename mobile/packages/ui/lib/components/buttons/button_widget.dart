import 'package:ente_base/typedefs.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_ui/components/buttons/models/button_result.dart';
import 'package:ente_ui/components/buttons/models/button_type.dart';
import 'package:ente_ui/components/buttons/models/custom_button_style.dart';
import 'package:ente_ui/components/loading_widget.dart';
import 'package:ente_ui/models/execution_states.dart';
import 'package:ente_ui/theme/colors.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/theme/text_style.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum ButtonSize { small, large }

enum ButtonAction { first, second, third, fourth, cancel, error }

class ButtonWidget extends StatelessWidget {
  final IconData? icon;
  final String? labelText;
  final ButtonType buttonType;
  final FutureVoidCallback? onTap;
  final bool isDisabled;
  final ButtonSize buttonSize;

  final bool shouldShowSuccessConfirmation;

  final bool shouldSurfaceExecutionStates;

  final Color? iconColor;

  final ButtonAction? buttonAction;

  final bool shouldStickToDarkTheme;

  final bool isInAlert;

  final ValueNotifier<String>? progressStatus;

  const ButtonWidget({
    super.key,
    required this.buttonType,
    this.buttonSize = ButtonSize.large,
    this.icon,
    this.labelText,
    this.onTap,
    this.shouldStickToDarkTheme = false,
    this.isDisabled = false,
    this.buttonAction,
    this.isInAlert = false,
    this.iconColor,
    this.shouldSurfaceExecutionStates = true,
    this.progressStatus,
    this.shouldShowSuccessConfirmation = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = shouldStickToDarkTheme
        ? darkScheme
        : getEnteColorScheme(context);
    final inverseColorScheme = shouldStickToDarkTheme
        ? lightScheme
        : getEnteColorScheme(context, inverse: true);
    final textTheme = shouldStickToDarkTheme
        ? darkTextTheme
        : getEnteTextTheme(context);
    final inverseTextTheme = shouldStickToDarkTheme
        ? lightTextTheme
        : getEnteTextTheme(context, inverse: true);
    final buttonStyle = CustomButtonStyle(
      defaultButtonColor: Colors.transparent,
      defaultBorderColor: Colors.transparent,
      defaultIconColor: Colors.transparent,
      defaultLabelStyle: textTheme.body,
    );
    buttonStyle.defaultButtonColor = buttonType.defaultButtonColor(colorScheme);
    buttonStyle.pressedButtonColor = buttonType.pressedButtonColor(colorScheme);
    buttonStyle.disabledButtonColor = buttonType.disabledButtonColor(
      colorScheme,
      buttonSize,
    );
    buttonStyle.defaultBorderColor = buttonType.defaultBorderColor(
      colorScheme,
      buttonSize,
    );
    buttonStyle.pressedBorderColor = buttonType.pressedBorderColor(
      colorScheme: colorScheme,
      buttonSize: buttonSize,
    );
    buttonStyle.disabledBorderColor = buttonType.disabledBorderColor(
      colorScheme,
      buttonSize,
    );
    buttonStyle.defaultIconColor =
        iconColor ??
        buttonType.defaultIconColor(
          colorScheme: colorScheme,
          inverseColorScheme: inverseColorScheme,
        );
    buttonStyle.pressedIconColor = buttonType.pressedIconColor(
      colorScheme,
      buttonSize,
    );
    buttonStyle.disabledIconColor = buttonType.disabledIconColor(
      colorScheme,
      buttonSize,
    );
    buttonStyle.defaultLabelStyle = buttonType.defaultLabelStyle(
      textTheme: textTheme,
      inverseTextTheme: inverseTextTheme,
    );
    buttonStyle.pressedLabelStyle = buttonType.pressedLabelStyle(
      textTheme,
      colorScheme,
      buttonSize,
    );
    buttonStyle.disabledLabelStyle = buttonType.disabledLabelStyle(
      textTheme,
      colorScheme,
    );
    buttonStyle.checkIconColor = buttonType.checkIconColor(colorScheme);

    return ButtonChildWidget(
      buttonStyle: buttonStyle,
      buttonType: buttonType,
      isDisabled: isDisabled,
      buttonSize: buttonSize,
      isInAlert: isInAlert,
      onTap: onTap,
      labelText: labelText,
      icon: icon,
      buttonAction: buttonAction,
      shouldSurfaceExecutionStates: shouldSurfaceExecutionStates,
      progressStatus: progressStatus,
      shouldShowSuccessConfirmation: shouldShowSuccessConfirmation,
    );
  }
}

class ButtonChildWidget extends StatefulWidget {
  final CustomButtonStyle buttonStyle;
  final FutureVoidCallback? onTap;
  final ButtonType buttonType;
  final String? labelText;
  final IconData? icon;
  final bool isDisabled;
  final ButtonSize buttonSize;
  final ButtonAction? buttonAction;
  final bool isInAlert;
  final bool shouldSurfaceExecutionStates;
  final ValueNotifier<String>? progressStatus;
  final bool shouldShowSuccessConfirmation;

  const ButtonChildWidget({
    super.key,
    required this.buttonStyle,
    required this.buttonType,
    required this.isDisabled,
    required this.buttonSize,
    required this.isInAlert,
    required this.shouldSurfaceExecutionStates,
    required this.shouldShowSuccessConfirmation,
    this.progressStatus,
    this.onTap,
    this.labelText,
    this.icon,
    this.buttonAction,
  });

  @override
  State<ButtonChildWidget> createState() => _ButtonChildWidgetState();
}

class _ButtonChildWidgetState extends State<ButtonChildWidget> {
  late Color buttonColor;
  late Color borderColor;
  late Color iconColor;
  late TextStyle labelStyle;
  late Color checkIconColor;
  late Color loadingIconColor;
  ValueNotifier<String>? progressStatus;

  double? widthOfButton;
  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  ExecutionState executionState = ExecutionState.idle;
  Exception? _exception;

  @override
  void initState() {
    _setButtonTheme();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant ButtonChildWidget oldWidget) {
    _setButtonTheme();
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    if (executionState == ExecutionState.successful) {
      Future.delayed(Duration(seconds: widget.isInAlert ? 1 : 2), () {
        setState(() {
          executionState = ExecutionState.idle;
        });
      });
    }
    return GestureDetector(
      onTap: _shouldRegisterGestures ? _onTap : null,
      onTapDown: _shouldRegisterGestures ? _onTapDown : null,
      onTapUp: _shouldRegisterGestures ? _onTapUp : null,
      onTapCancel: _shouldRegisterGestures ? _onTapCancel : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          border: widget.buttonType == ButtonType.tertiaryCritical
              ? Border.all(color: borderColor)
              : null,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 16),
          width: widget.buttonSize == ButtonSize.large ? double.infinity : null,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            color: buttonColor,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 175),
              switchInCurve: Curves.easeInOutExpo,
              switchOutCurve: Curves.easeInOutExpo,
              child:
                  executionState == ExecutionState.idle ||
                      !widget.shouldSurfaceExecutionStates
                  ? widget.buttonType.hasTrailingIcon
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              widget.labelText == null
                                  ? const SizedBox.shrink()
                                  : Flexible(
                                      child: Padding(
                                        padding: widget.icon == null
                                            ? const EdgeInsets.symmetric(
                                                horizontal: 8,
                                              )
                                            : const EdgeInsets.only(right: 16),
                                        child: Text(
                                          widget.labelText!,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                          style: labelStyle,
                                        ),
                                      ),
                                    ),
                              widget.icon == null
                                  ? const SizedBox.shrink()
                                  : Icon(
                                      widget.icon,
                                      size: 20,
                                      color: iconColor,
                                    ),
                            ],
                          )
                        : Builder(
                            builder: (context) {
                              SchedulerBinding.instance.addPostFrameCallback((
                                timeStamp,
                              ) {
                                final box =
                                    context.findRenderObject() as RenderBox;
                                widthOfButton = box.size.width;
                              });
                              return Row(
                                mainAxisSize:
                                    widget.buttonSize == ButtonSize.large
                                    ? MainAxisSize.max
                                    : MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  widget.icon == null
                                      ? const SizedBox.shrink()
                                      : Icon(
                                          widget.icon,
                                          size: 20,
                                          color: iconColor,
                                        ),
                                  widget.icon == null ||
                                          widget.labelText == null
                                      ? const SizedBox.shrink()
                                      : const SizedBox(width: 8),
                                  widget.labelText == null
                                      ? const SizedBox.shrink()
                                      : Flexible(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Text(
                                              widget.labelText!,
                                              style: labelStyle,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                ],
                              );
                            },
                          )
                  : executionState == ExecutionState.inProgress
                  ? SizedBox(
                      width: widthOfButton,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          progressStatus == null
                              ? const SizedBox.shrink()
                              : ValueListenableBuilder<String>(
                                  valueListenable: progressStatus!,
                                  builder:
                                      (
                                        BuildContext context,
                                        String value,
                                        Widget? child,
                                      ) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8.0,
                                          ),
                                          child: Text(
                                            value,
                                            style: lightTextTheme.smallBold,
                                          ),
                                        );
                                      },
                                ),
                          EnteLoadingWidget(
                            padding: 3,
                            color: loadingIconColor,
                          ),
                        ],
                      ),
                    )
                  : executionState == ExecutionState.successful
                  ? SizedBox(
                      width: widthOfButton,
                      child: Icon(
                        Icons.check_outlined,
                        size: 20,
                        color: checkIconColor,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  void _setButtonTheme() {
    progressStatus = widget.progressStatus;
    checkIconColor =
        widget.buttonStyle.checkIconColor ??
        widget.buttonStyle.defaultIconColor;
    loadingIconColor = widget.buttonStyle.defaultIconColor;
    if (widget.isDisabled) {
      buttonColor =
          widget.buttonStyle.disabledButtonColor ??
          widget.buttonStyle.defaultButtonColor;
      borderColor =
          widget.buttonStyle.disabledBorderColor ??
          widget.buttonStyle.defaultBorderColor;
      iconColor =
          widget.buttonStyle.disabledIconColor ??
          widget.buttonStyle.defaultIconColor;
      labelStyle =
          widget.buttonStyle.disabledLabelStyle ??
          widget.buttonStyle.defaultLabelStyle;
    } else {
      buttonColor = widget.buttonStyle.defaultButtonColor;
      borderColor = widget.buttonStyle.defaultBorderColor;
      iconColor = widget.buttonStyle.defaultIconColor;
      labelStyle = widget.buttonStyle.defaultLabelStyle;
    }
  }

  bool get _shouldRegisterGestures =>
      !widget.isDisabled && executionState == ExecutionState.idle;

  void _onTap() async {
    if (widget.onTap != null) {
      _debouncer.run(
        () => Future(() {
          if (mounted) {
            setState(() {
              executionState = ExecutionState.inProgress;
            });
          }
        }),
      );
      await widget.onTap!.call().then(
        (value) {
          _exception = null;
        },
        onError: (error, stackTrace) {
          executionState = ExecutionState.error;
          _exception = error as Exception;
          _debouncer.cancelDebounce();
        },
      );
      if (!mounted) {
        _debouncer.cancelDebounce();
        return;
      }
      widget.shouldShowSuccessConfirmation && _debouncer.isActive()
          ? executionState = ExecutionState.successful
          : null;
      _debouncer.cancelDebounce();
      if (executionState == ExecutionState.successful) {
        setState(() {});
      }

      // Let the debounced callback finish before checking its execution state.
      await Future.delayed(const Duration(milliseconds: 5));
    }
    if (!mounted) {
      return;
    }
    if (executionState == ExecutionState.inProgress ||
        executionState == ExecutionState.error) {
      if (executionState == ExecutionState.inProgress) {
        if (mounted) {
          setState(() {
            executionState = ExecutionState.successful;
            Future.delayed(
              Duration(
                seconds: widget.shouldSurfaceExecutionStates
                    ? (widget.isInAlert ? 1 : 2)
                    : 0,
              ),
              () {
                if (!mounted) {
                  return;
                }
                widget.isInAlert
                    ? _popWithButtonAction(
                        context,
                        buttonAction: widget.buttonAction,
                      )
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
      if (executionState == ExecutionState.error) {
        setState(() {
          executionState = ExecutionState.idle;
          widget.isInAlert
              ? Future.delayed(const Duration(seconds: 0), () {
                  if (!mounted) {
                    return;
                  }
                  _popWithButtonAction(
                    context,
                    buttonAction: ButtonAction.error,
                    exception: _exception,
                  );
                })
              : null;
        });
      }
    } else {
      if (widget.isInAlert) {
        Future.delayed(
          Duration(seconds: widget.shouldShowSuccessConfirmation ? 1 : 0),
          () {
            if (!mounted) {
              return;
            }
            _popWithButtonAction(context, buttonAction: widget.buttonAction);
          },
        );
      }
    }
  }

  void _popWithButtonAction(
    BuildContext context, {
    required ButtonAction? buttonAction,
    Exception? exception,
  }) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(ButtonResult(widget.buttonAction, exception));
    } else if (exception != null) {
      // Surface failures even if the dialog was dismissed mid-operation.
      showGenericErrorDialog(context: context, error: exception);
    }
  }

  void _onTapDown(TapDownDetails details) {
    setState(() {
      buttonColor =
          widget.buttonStyle.pressedButtonColor ??
          widget.buttonStyle.defaultButtonColor;
      borderColor =
          widget.buttonStyle.pressedBorderColor ??
          widget.buttonStyle.defaultBorderColor;
      iconColor =
          widget.buttonStyle.pressedIconColor ??
          widget.buttonStyle.defaultIconColor;
      labelStyle =
          widget.buttonStyle.pressedLabelStyle ??
          widget.buttonStyle.defaultLabelStyle;
    });
  }

  void _onTapUp(TapUpDetails details) {
    Future.delayed(
      const Duration(milliseconds: 84),
      () => setState(() {
        setAllStylesToDefault();
      }),
    );
  }

  void _onTapCancel() {
    setState(() {
      setAllStylesToDefault();
    });
  }

  void setAllStylesToDefault() {
    buttonColor = widget.buttonStyle.defaultButtonColor;
    borderColor = widget.buttonStyle.defaultBorderColor;
    iconColor = widget.buttonStyle.defaultIconColor;
    labelStyle = widget.buttonStyle.defaultLabelStyle;
  }
}
