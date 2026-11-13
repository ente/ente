import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/models/button_result.dart';
import 'package:photos/models/execution_states.dart';
import 'package:photos/models/typedefs.dart';
import 'package:photos/theme/colors.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/theme/text_style.dart';
import 'package:photos/ui/components/buttons/button_widget.dart'
    show ButtonAction;
import 'package:photos/ui/components/models/button_type_v2.dart';
import 'package:photos/utils/dialog_util.dart';

export 'package:photos/ui/components/models/button_type_v2.dart';

class ButtonWidgetV2 extends StatefulWidget {
  final ButtonTypeV2 buttonType;
  final String? labelText;
  final FutureVoidCallback? onTap;
  final bool isDisabled;
  final Widget? trailingWidget;
  final bool shouldSurfaceExecutionStates;
  final bool shouldStickToDarkTheme;
  final bool shouldStickToLightTheme;
  final ButtonSizeV2 buttonSize;
  final Widget? leadingWidget;
  final Color? iconColor;
  final ButtonAction? buttonAction;
  final bool isInAlert;
  final ValueNotifier<String>? progressStatus;
  final bool shouldShowSuccessConfirmation;

  const ButtonWidgetV2({
    required this.buttonType,
    this.labelText,
    this.onTap,
    this.isDisabled = false,
    this.trailingWidget,
    this.shouldSurfaceExecutionStates = true,
    this.shouldStickToDarkTheme = false,
    this.shouldStickToLightTheme = false,
    this.buttonSize = ButtonSizeV2.large,
    this.leadingWidget,
    this.iconColor,
    this.buttonAction,
    this.isInAlert = false,
    this.progressStatus,
    this.shouldShowSuccessConfirmation = false,
    super.key,
  });

  @override
  State<ButtonWidgetV2> createState() => _ButtonWidgetV2State();
}

class _ButtonWidgetV2State extends State<ButtonWidgetV2>
    with SingleTickerProviderStateMixin {
  ExecutionState _executionState = ExecutionState.idle;
  bool _isHovered = false;
  bool _isFingerDown = false;
  bool _isPressedVisual = false;
  int _pressToken = 0;

  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  late final AnimationController _loadingController;

  double? _idleWidth;
  Exception? _exception;
  DateTime? _tapDownTime;

  @override
  void initState() {
    super.initState();
    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _syncLoadingController();
  }

  @override
  void didUpdateWidget(covariant ButtonWidgetV2 oldWidget) {
    super.didUpdateWidget(oldWidget);

    final idleContentChanged =
        widget.buttonType != oldWidget.buttonType ||
        widget.labelText != oldWidget.labelText ||
        widget.leadingWidget != oldWidget.leadingWidget ||
        widget.trailingWidget != oldWidget.trailingWidget;

    if (widget.buttonSize != oldWidget.buttonSize ||
        (widget.buttonSize == ButtonSizeV2.small && idleContentChanged)) {
      _idleWidth = null;
    }

    if (widget.isDisabled && !oldWidget.isDisabled) {
      _isFingerDown = false;
      _isPressedVisual = false;
    }

    _syncLoadingController();
  }

  @override
  void dispose() {
    _debouncer.cancelDebounceTimer();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.shouldStickToLightTheme
        ? lightScheme
        : widget.shouldStickToDarkTheme
        ? darkScheme
        : getEnteColorScheme(context);
    final textTheme = widget.shouldStickToLightTheme
        ? lightTextTheme
        : widget.shouldStickToDarkTheme
        ? darkTextTheme
        : getEnteTextTheme(context);

    final showLoading =
        _executionState == ExecutionState.inProgress &&
        widget.shouldSurfaceExecutionStates;
    final showSuccess =
        _executionState == ExecutionState.successful &&
        widget.shouldSurfaceExecutionStates;

    final palette = widget.buttonType.getColorPalette(colorScheme);
    final colors = palette.resolve(
      isDisabled: widget.isDisabled,
      isPressed: _isPressedVisual,
      isHovered: _isHovered,
      isLoading: showLoading,
      isSuccess: showSuccess,
      iconColorOverride: widget.iconColor,
    );

    final isLink = widget.buttonType == ButtonTypeV2.link;
    final isSmall = widget.buttonSize == ButtonSizeV2.small;
    final isScaledDown = _isFingerDown;

    final BoxConstraints? constraints = isLink
        ? null
        : const BoxConstraints(minHeight: 52);
    final double borderRadius = isLink ? 0 : 20;
    final EdgeInsets padding = isLink
        ? const EdgeInsets.symmetric(vertical: 4)
        : const EdgeInsets.symmetric(vertical: 14, horizontal: 24);

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: widget.isDisabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _shouldRegisterGestures ? _onTap : null,
        onTapDown: _shouldRegisterGestures ? (_) => _onTapDown() : null,
        onTapUp: _shouldRegisterGestures ? (_) => _onTapUp() : null,
        onTapCancel: _shouldRegisterGestures ? _onTapCancel : null,
        child: AnimatedScale(
          scale: isScaledDown ? 0.98 : 1.0,
          duration: Duration(milliseconds: isScaledDown ? 120 : 220),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            constraints: constraints,
            width: isSmall ? _idleWidth : (isLink ? null : double.infinity),
            decoration: BoxDecoration(
              color: colors.backgroundColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: colors.borderColor != null
                  ? Border.all(color: colors.borderColor!, width: 1)
                  : null,
            ),
            child: Padding(
              padding: padding,
              child: _buildContent(
                colors,
                textTheme,
                showLoading: showLoading,
                showSuccess: showSuccess,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    ButtonColors colors,
    EnteTextTheme textTheme, {
    required bool showLoading,
    required bool showSuccess,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      child: showLoading
          ? _buildLoadingContent(colors, textTheme)
          : showSuccess
          ? _buildSuccessContent(colors)
          : _buildIdleContent(colors, textTheme),
    );
  }

  Widget _buildLoadingContent(ButtonColors colors, EnteTextTheme textTheme) {
    final spinner = RotationTransition(
      turns: _loadingController,
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedLoading03,
        color: colors.spinnerColor,
        size: 24,
      ),
    );

    if (widget.progressStatus != null) {
      return Row(
        key: const ValueKey('loading'),
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: widget.progressStatus!,
            builder: (context, value, _) {
              if (value.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  value,
                  style: textTheme.smallBold.copyWith(color: colors.textColor),
                ),
              );
            },
          ),
          spinner,
        ],
      );
    }

    return Row(
      key: const ValueKey('loading'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [spinner],
    );
  }

  Widget _buildSuccessContent(ButtonColors colors) {
    return Row(
      key: const ValueKey('success'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        HugeIcon(
          icon: HugeIcons.strokeRoundedTick02,
          color: colors.checkmarkColor,
          size: 24,
        ),
      ],
    );
  }

  Widget _buildIdleContent(ButtonColors colors, EnteTextTheme textTheme) {
    final isSmall = widget.buttonSize == ButtonSizeV2.small;

    if (isSmall && _idleWidth == null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          setState(() {
            _idleWidth = box.size.width;
          });
        }
      });
    }

    final isLink = widget.buttonType == ButtonTypeV2.link;
    final isTertiaryCritical =
        widget.buttonType == ButtonTypeV2.tertiaryCritical;
    final hasUnderline = isLink || isTertiaryCritical;
    final labelStyle = (hasUnderline ? textTheme.body : textTheme.bodyBold)
        .copyWith(
          color: colors.textColor,
          decoration: hasUnderline ? TextDecoration.underline : null,
          decorationColor: hasUnderline ? colors.textColor : null,
        );

    final hasLeading = widget.leadingWidget != null;
    final hasLabel = widget.labelText != null;

    if (widget.trailingWidget != null) {
      return Row(
        key: const ValueKey('idle'),
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: isSmall ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (hasLeading) ...[
            IconTheme(
              data: IconThemeData(color: colors.iconColor, size: 20),
              child: widget.leadingWidget!,
            ),
            if (hasLabel) const SizedBox(width: 8),
          ],
          if (hasLabel)
            Flexible(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hasLeading ? 0 : 8),
                child: Text(
                  widget.labelText!,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ),
          if (widget.trailingWidget != null) ...[
            const SizedBox(width: 12),
            IconTheme(
              data: IconThemeData(color: colors.iconColor, size: 20),
              child: widget.trailingWidget!,
            ),
          ],
        ],
      );
    }

    return Row(
      key: const ValueKey('idle'),
      mainAxisSize: isSmall ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasLeading) ...[
          IconTheme(
            data: IconThemeData(color: colors.iconColor, size: 20),
            child: widget.leadingWidget!,
          ),
          if (hasLabel) const SizedBox(width: 8),
        ],
        if (hasLabel)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                widget.labelText!,
                style: labelStyle,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ),
      ],
    );
  }

  bool get _shouldRegisterGestures =>
      !widget.isDisabled && _executionState == ExecutionState.idle;

  void _setHovered(bool value) {
    if (widget.isDisabled) return;
    if (_isHovered == value) return;
    if (mounted) setState(() => _isHovered = value);
  }

  void _onTapDown() {
    _pressToken++;
    _tapDownTime = DateTime.now();
    if (mounted) {
      setState(() {
        _isFingerDown = true;
        _isPressedVisual = true;
      });
    }
  }

  void _onTapUp() {
    _releaseFingerWithMinDuration();
  }

  void _onTapCancel() {
    _releaseFingerWithMinDuration(cancelled: true);
  }

  void _releaseFingerWithMinDuration({bool cancelled = false}) {
    final tokenAtReleaseRequest = _pressToken;
    if (_tapDownTime == null) {
      if (mounted) {
        setState(() {
          _isFingerDown = false;
          if (cancelled) _isPressedVisual = false;
        });
      }
      return;
    }

    const minScaleDuration = Duration(milliseconds: 120);
    final elapsed = DateTime.now().difference(_tapDownTime!);
    final remaining = minScaleDuration - elapsed;

    void release() {
      if (mounted) {
        if (tokenAtReleaseRequest != _pressToken) return;
        setState(() {
          _isFingerDown = false;
          if (cancelled) _isPressedVisual = false;
        });
      }
    }

    if (remaining.isNegative || remaining == Duration.zero) {
      release();
    } else {
      Future.delayed(remaining, release);
    }
    _tapDownTime = null;
  }

  void _popWithButtonAction(
    BuildContext context, {
    required ButtonAction? buttonAction,
    Exception? exception,
  }) {
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(ButtonResult(buttonAction, exception));
      } else if (exception != null) {
        showGenericErrorDialog(context: context, error: exception).ignore();
      }
    }
  }

  Future<void> _onTap() async {
    if (widget.onTap == null) {
      if (mounted) setState(() => _isPressedVisual = false);
      if (widget.isInAlert) {
        _popWithButtonAction(context, buttonAction: widget.buttonAction);
      }
      return;
    }

    _debouncer.run(
      () => Future(() {
        if (!mounted) return;
        setState(() {
          _executionState = ExecutionState.inProgress;
          _isPressedVisual = false;
        });
        _syncLoadingController();
      }),
    );

    try {
      await widget.onTap!();
      _exception = null;

      final showSuccess =
          widget.shouldShowSuccessConfirmation && _debouncer.isActive();

      _debouncer.cancelDebounceTimer();

      if (mounted) {
        if (showSuccess || _executionState == ExecutionState.inProgress) {
          setState(() {
            _executionState = ExecutionState.successful;
            _isPressedVisual = false;
          });
          _syncLoadingController();

          final successDisplayDuration = Duration(
            seconds: widget.shouldSurfaceExecutionStates
                ? (widget.isInAlert ? 1 : 2)
                : 0,
          );

          await Future.delayed(successDisplayDuration);

          if (widget.isInAlert) {
            if (!mounted) return;
            _popWithButtonAction(context, buttonAction: widget.buttonAction);
          }

          if (mounted) {
            setState(() => _executionState = ExecutionState.idle);
            _syncLoadingController();
          }
        } else {
          setState(() {
            _executionState = ExecutionState.idle;
            _isPressedVisual = false;
          });
          _syncLoadingController();

          if (widget.isInAlert) {
            _popWithButtonAction(context, buttonAction: widget.buttonAction);
          }
        }
      }
    } catch (e) {
      _debouncer.cancelDebounceTimer();
      _exception = e is Exception ? e : Exception(e.toString());

      if (mounted) {
        setState(() {
          _executionState = ExecutionState.idle;
          _isPressedVisual = false;
        });
        _syncLoadingController();

        if (widget.isInAlert) {
          _popWithButtonAction(
            context,
            buttonAction: ButtonAction.error,
            exception: _exception,
          );
        }
      }
    }
  }

  void _syncLoadingController() {
    final shouldAnimate =
        _executionState == ExecutionState.inProgress &&
        widget.shouldSurfaceExecutionStates;

    if (shouldAnimate) {
      if (!_loadingController.isAnimating) {
        _loadingController.repeat();
      }
      return;
    }

    if (_loadingController.isAnimating || _loadingController.value != 0) {
      _loadingController.stop();
      _loadingController.reset();
    }
  }
}
