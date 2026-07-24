import 'dart:async';

import 'package:ente_components/models/component_execution_state.dart';
import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum ButtonComponentVariant {
  primary,
  secondary,
  neutral,
  critical,
  tertiaryCritical,
  link,
}

enum ButtonComponentSize { small, large }

enum ButtonComponentDensity {
  regular,

  /// Opt-in 48px Button Large treatment used by the Memory sharing sheet.
  /// Source: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=18629-312441&m=dev
  compact,
}

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2207-41578&m=dev
/// Section: Buttons / Button Small
/// Specs: 52px height, 20px radius, 24px horizontal padding.
/// States: default, hover, pressed, disabled, loading, success.
class ButtonComponent extends StatefulWidget {
  const ButtonComponent({
    super.key,
    required this.label,
    this.onTap,
    this.variant = ButtonComponentVariant.primary,
    this.size = ButtonComponentSize.large,
    this.density = ButtonComponentDensity.regular,
    this.isDisabled = false,
    this.shouldSurfaceExecutionStates = true,
    this.shouldShowSuccessState = true,
    this.shouldShowSuccessConfirmation = false,
    this.progressStatus,
    this.leading,
    this.dismissModalOnSuccess = false,
  });

  final String label;
  final FutureOr<void> Function()? onTap;
  final ButtonComponentVariant variant;
  final ButtonComponentSize size;
  final ButtonComponentDensity density;
  final bool isDisabled;
  final bool shouldSurfaceExecutionStates;
  final bool shouldShowSuccessState;
  final bool shouldShowSuccessConfirmation;
  final ValueListenable<String>? progressStatus;
  final Widget? leading;

  /// Dismisses the current modal route after [onTap] completes without throwing.
  ///
  /// This only applies to popup routes such as dialogs and bottom sheets. Normal
  /// page routes are not dismissed.
  final bool dismissModalOnSuccess;

  @override
  State<ButtonComponent> createState() => _ButtonComponentState();
}

class _ButtonComponentState extends State<ButtonComponent>
    with SingleTickerProviderStateMixin {
  static const double _executionIconSize = IconSizes.medium;
  static const double _contentMinHeight = 24;
  static const double _regularVerticalPadding = 14;
  static const double _compactVerticalPadding = 12;
  static const Duration _loadingDelay = Duration(milliseconds: 300);
  static const Duration _successDisplayDuration = Duration(seconds: 1);
  static const Duration _minimumPressDuration = Duration(milliseconds: 120);

  late final AnimationController _loadingController;
  bool _isHovered = false;
  bool _isPressed = false;
  int _pressToken = 0;
  DateTime? _tapDownTime;
  Timer? _loadingTimer;
  Timer? _successResetTimer;
  Timer? _pressReleaseTimer;
  bool _loadingVisible = false;
  ComponentExecutionState _executionState = ComponentExecutionState.idle;

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
  void didUpdateWidget(covariant ButtonComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDisabled && !oldWidget.isDisabled) {
      _isPressed = false;
    }
    _syncLoadingController();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _successResetTimer?.cancel();
    _pressReleaseTimer?.cancel();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInlineLink =
        widget.variant == ButtonComponentVariant.link &&
        widget.size == ButtonComponentSize.small;
    final resolvedColors = _colors(context);
    final enabled = _canHandleGestures;
    final verticalPadding = isInlineLink ? Spacing.xs : _buttonVerticalPadding;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? _handleTap : null,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _releasePressed() : null,
        onTapCancel: enabled ? _releasePressed : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: Motion.standard,
            curve: Curves.easeInOutCubic,
            width: widget.size == ButtonComponentSize.large
                ? double.infinity
                : null,
            decoration: BoxDecoration(
              color: resolvedColors.background,
              borderRadius: BorderRadius.circular(
                isInlineLink ? 0 : Radii.button,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isInlineLink ? 0 : Spacing.xl,
                vertical: verticalPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: isInlineLink ? 0 : _contentMinHeight,
                ),
                child: AnimatedSwitcher(
                  duration: Motion.quick,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: _contentTransition,
                  child: _content(context, resolvedColors.foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (!_canHandleGestures || _isHovered == value) {
      return;
    }
    setState(() => _isHovered = value);
  }

  void _setPressed(bool value) {
    if (!_canHandleGestures || _isPressed == value) {
      return;
    }
    if (value) {
      _pressToken++;
      _tapDownTime = DateTime.now();
      setState(() => _isPressed = true);
      return;
    }
    _releasePressed();
  }

  void _releasePressed() {
    final token = _pressToken;
    final tapDownTime = _tapDownTime;
    if (tapDownTime == null) {
      if (mounted) setState(() => _isPressed = false);
      return;
    }

    final elapsed = DateTime.now().difference(tapDownTime);
    final remaining = _minimumPressDuration - elapsed;

    void release() {
      if (!mounted || token != _pressToken) return;
      setState(() => _isPressed = false);
    }

    if (remaining <= Duration.zero) {
      release();
    } else {
      _pressReleaseTimer?.cancel();
      _pressReleaseTimer = Timer(remaining, release);
    }
    _tapDownTime = null;
  }

  Widget _content(BuildContext context, Color foreground) {
    if (_showLoading) {
      return _executionContent(
        key: const ValueKey('loading'),
        child: _loadingContent(foreground),
      );
    }
    if (_showSuccess) {
      return _executionContent(
        key: const ValueKey('success'),
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedTick02,
          size: _executionIconSize,
          color: foreground,
        ),
      );
    }

    return _idleContent(foreground);
  }

  Widget _idleContent(Color foreground) {
    final underlined =
        widget.variant == ButtonComponentVariant.link ||
        widget.variant == ButtonComponentVariant.tertiaryCritical;
    final labelStyle = widget.density == ButtonComponentDensity.compact
        ? TextStyles.body
        : TextStyles.bodyBold;
    final label = Text(
      widget.label,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
      style: labelStyle.copyWith(
        color: foreground,
        decoration: underlined ? TextDecoration.underline : null,
        decorationColor: underlined ? foreground : null,
      ),
    );
    return Row(
      key: const ValueKey('content'),
      mainAxisSize: widget.size == ButtonComponentSize.large
          ? MainAxisSize.max
          : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leading != null) ...[
          IconTheme.merge(
            data: IconThemeData(color: foreground, size: IconSizes.small),
            child: widget.leading!,
          ),
          const SizedBox(width: Spacing.sm),
        ],
        if (widget.variant != ButtonComponentVariant.link)
          Flexible(child: label)
        else
          label,
      ],
    );
  }

  Widget _executionContent({required Key key, required Widget child}) {
    return Stack(
      key: key,
      alignment: Alignment.center,
      children: [
        Visibility(
          visible: false,
          maintainAnimation: true,
          maintainSize: true,
          maintainState: true,
          child: _idleContent(Colors.transparent),
        ),
        child,
      ],
    );
  }

  Widget _contentTransition(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }

  Widget _loadingContent(Color foreground) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.progressStatus != null)
          ValueListenableBuilder<String>(
            valueListenable: widget.progressStatus!,
            builder: (context, value, _) {
              if (value.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: Text(
                  value,
                  style: TextStyles.mini.copyWith(color: foreground),
                ),
              );
            },
          ),
        SizedBox(
          width: _executionIconSize,
          height: _executionIconSize,
          child: Center(
            child: RotationTransition(
              turns: _loadingController,
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedLoading03,
                color: foreground,
                size: _executionIconSize,
              ),
            ),
          ),
        ),
      ],
    );
  }

  double get _buttonVerticalPadding {
    return widget.density == ButtonComponentDensity.compact
        ? _compactVerticalPadding
        : _regularVerticalPadding;
  }

  _ResolvedButtonColors _colors(BuildContext context) {
    if (widget.isDisabled || widget.onTap == null) {
      return _ResolvedButtonColors(
        background: _disabledBackground(context),
        foreground: _componentColors(context).textLightest,
      );
    }

    final isPressed = !_showLoading && !_showSuccess && _isPressed;
    final isHovered = !_showLoading && !_showSuccess && _isHovered;
    return _ResolvedButtonColors(
      background: isPressed
          ? _pressedBackground(context)
          : isHovered
          ? _hoverBackground(context)
          : _background(context),
      foreground: _foreground(
        context,
        isPressed: isPressed,
        isHovered: isHovered,
      ),
    );
  }

  void _syncLoadingController() {
    if (_showLoading) {
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

  bool get _canHandleGestures =>
      !widget.isDisabled &&
      widget.onTap != null &&
      !_isExecuting &&
      !_isSuccessful;

  bool get _isExecuting =>
      _executionState == ComponentExecutionState.inProgress;

  bool get _isSuccessful =>
      _executionState == ComponentExecutionState.successful;

  bool get _showLoading =>
      widget.shouldSurfaceExecutionStates && _isExecuting && _loadingVisible;

  bool get _showSuccess =>
      widget.shouldSurfaceExecutionStates &&
      widget.shouldShowSuccessState &&
      _isSuccessful;

  Future<void> _handleTap() async {
    final callback = widget.onTap;
    if (callback == null) return;

    _successResetTimer?.cancel();
    var loadingSurfaced = false;
    _loadingTimer?.cancel();
    setState(() {
      _executionState = ComponentExecutionState.inProgress;
      _loadingVisible = false;
    });
    _loadingTimer = Timer(_loadingDelay, () {
      if (!mounted) return;
      loadingSurfaced = true;
      setState(() {
        _loadingVisible = true;
        _isPressed = false;
      });
      _syncLoadingController();
    });

    try {
      await Future.sync(callback);
      if (!mounted) return;

      final loadingPending = _loadingTimer?.isActive ?? false;
      _loadingTimer?.cancel();
      _loadingTimer = null;

      final shouldShowSuccess =
          widget.shouldSurfaceExecutionStates &&
          widget.shouldShowSuccessState &&
          (loadingSurfaced ||
              (loadingPending && widget.shouldShowSuccessConfirmation));

      if (shouldShowSuccess) {
        _showSuccessForDuration();
      } else {
        setState(() {
          _executionState = ComponentExecutionState.idle;
          _loadingVisible = false;
          _isPressed = false;
        });
        _syncLoadingController();
        _dismissRouteOnSuccess();
      }
    } catch (_) {
      _loadingTimer?.cancel();
      _loadingTimer = null;
      if (mounted) {
        setState(() {
          _executionState = ComponentExecutionState.idle;
          _loadingVisible = false;
          _isPressed = false;
        });
        _syncLoadingController();
      }
    }
  }

  void _showSuccessForDuration() {
    setState(() {
      _executionState = ComponentExecutionState.successful;
      _loadingVisible = false;
      _isPressed = false;
    });
    _syncLoadingController();
    _successResetTimer?.cancel();
    _successResetTimer = Timer(_successDisplayDuration, () {
      if (!mounted) return;
      if (_dismissRouteOnSuccess()) {
        return;
      }
      setState(() {
        _executionState = ComponentExecutionState.idle;
        _loadingVisible = false;
      });
      _syncLoadingController();
    });
  }

  bool _dismissRouteOnSuccess() {
    if (!widget.dismissModalOnSuccess || !mounted) {
      return false;
    }
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route is! PopupRoute || !route.isCurrent) {
      return false;
    }
    navigator.pop();
    return true;
  }

  Color _background(BuildContext context) {
    final colors = _componentColors(context);
    return switch (widget.variant) {
      ButtonComponentVariant.primary => colors.primary,
      ButtonComponentVariant.secondary => colors.fillDark,
      ButtonComponentVariant.neutral => colors.fillBase,
      ButtonComponentVariant.critical => colors.warning,
      ButtonComponentVariant.tertiaryCritical => Colors.transparent,
      ButtonComponentVariant.link => Colors.transparent,
    };
  }

  Color _hoverBackground(BuildContext context) {
    final colors = _componentColors(context);
    return switch (widget.variant) {
      ButtonComponentVariant.primary => colors.primaryDark,
      ButtonComponentVariant.secondary => colors.fillDarker,
      ButtonComponentVariant.neutral => colors.fillBase,
      ButtonComponentVariant.critical => colors.warningDark,
      ButtonComponentVariant.tertiaryCritical => Colors.transparent,
      ButtonComponentVariant.link => Colors.transparent,
    };
  }

  Color _pressedBackground(BuildContext context) {
    final colors = _componentColors(context);
    return switch (widget.variant) {
      ButtonComponentVariant.primary => colors.primaryDarker,
      ButtonComponentVariant.secondary => colors.fillDarkest,
      ButtonComponentVariant.neutral => colors.fillBase,
      ButtonComponentVariant.critical => colors.warningDarker,
      ButtonComponentVariant.tertiaryCritical => Colors.transparent,
      ButtonComponentVariant.link => Colors.transparent,
    };
  }

  Color _disabledBackground(BuildContext context) {
    final colors = _componentColors(context);
    return switch (widget.variant) {
      ButtonComponentVariant.tertiaryCritical => Colors.transparent,
      ButtonComponentVariant.link => Colors.transparent,
      _ => colors.fillDark,
    };
  }

  Color _foreground(
    BuildContext context, {
    required bool isPressed,
    required bool isHovered,
  }) {
    final colors = _componentColors(context);
    return switch (widget.variant) {
      ButtonComponentVariant.primary => colors.specialWhite,
      ButtonComponentVariant.secondary => colors.textBase,
      ButtonComponentVariant.neutral => colors.textReverse,
      ButtonComponentVariant.critical => colors.specialWhite,
      ButtonComponentVariant.tertiaryCritical =>
        isPressed
            ? colors.warningDarker
            : isHovered
            ? colors.warningDark
            : colors.warning,
      ButtonComponentVariant.link =>
        isPressed
            ? colors.primaryDarker
            : isHovered
            ? colors.primaryDark
            : colors.primary,
    };
  }

  ColorTokens _componentColors(BuildContext context) {
    return context.componentColors;
  }
}

class _ResolvedButtonColors {
  const _ResolvedButtonColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
