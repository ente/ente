import 'dart:async';

import 'package:ente_components/models/component_execution_state.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum IconButtonComponentVariant {
  primary,
  critical,
  unfilled,
  secondary,
  green,
  circular,
}

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2207-42075&m=dev
/// Section: Buttons / Icon Button
/// Specs: 36px square, compact icon affordance with default, hover, pressed,
/// disabled, loading, and success states.
class IconButtonComponent extends StatefulWidget {
  const IconButtonComponent({
    super.key,
    required this.icon,
    this.onTap,
    this.onTapDown,
    this.variant = IconButtonComponentVariant.secondary,
    this.shouldSurfaceExecutionStates = true,
    this.shouldShowSuccessConfirmation = false,
    this.tooltip,
  });

  final Widget icon;
  final FutureOr<void> Function()? onTap;
  final void Function(TapDownDetails details)? onTapDown;
  final IconButtonComponentVariant variant;
  final bool shouldSurfaceExecutionStates;
  final bool shouldShowSuccessConfirmation;
  final String? tooltip;

  @override
  State<IconButtonComponent> createState() => _IconButtonComponentState();
}

class _IconButtonComponentState extends State<IconButtonComponent>
    with SingleTickerProviderStateMixin {
  static const Duration _loadingDelay = Duration(milliseconds: 300);
  static const Duration _successDisplayDuration = Duration(seconds: 1);

  late final AnimationController _loadingController;
  bool _isHovered = false;
  bool _isPressed = false;
  Timer? _loadingTimer;
  Timer? _successResetTimer;
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
  void didUpdateWidget(covariant IconButtonComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncLoadingController();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _successResetTimer?.cancel();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _canHandleGestures;
    final colors = _colors(context);
    final radius = widget.variant == IconButtonComponentVariant.circular
        ? BorderRadius.circular(35)
        : BorderRadius.circular(Radii.md);

    Widget button = SizedBox(
      width: _buttonSize,
      height: _buttonSize,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled && widget.onTap != null ? _handleTap : null,
          onTapDown: enabled ? _handleTapDown : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          child: AnimatedScale(
            scale: enabled && _isPressed ? 0.98 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              key: const ValueKey('icon-button-surface'),
              duration: Motion.quick,
              curve: Curves.easeInOutCubic,
              width: _buttonSize,
              height: _buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: radius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: AnimatedSwitcher(
                  duration: Motion.quick,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _content(colors.foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
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
    setState(() => _isPressed = value);
  }

  Widget _content(Color foreground) {
    if (_showLoading) {
      return RotationTransition(
        key: const ValueKey('loading'),
        turns: _loadingController,
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedLoading03,
          size: _iconSize,
          color: foreground,
        ),
      );
    }
    if (_showSuccess) {
      return HugeIcon(
        key: const ValueKey('success'),
        icon: HugeIcons.strokeRoundedTick02,
        size: _iconSize,
        color: foreground,
      );
    }
    return IconTheme.merge(
      key: const ValueKey('icon'),
      data: IconThemeData(size: _iconSize, color: foreground),
      child: widget.icon,
    );
  }

  bool get _canHandleGestures {
    return _hasGestureCallback && !_isExecuting && !_isSuccessful;
  }

  bool get _hasGestureCallback =>
      widget.onTap != null || widget.onTapDown != null;

  bool get _isExecuting =>
      _executionState == ComponentExecutionState.inProgress;

  bool get _isSuccessful =>
      _executionState == ComponentExecutionState.successful;

  bool get _showLoading {
    return widget.shouldSurfaceExecutionStates &&
        _isExecuting &&
        _loadingVisible;
  }

  bool get _showSuccess {
    return widget.shouldSurfaceExecutionStates && _isSuccessful;
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

  Future<void> _handleTap() async {
    final callback = widget.onTap;
    if (callback == null) return;

    _successResetTimer?.cancel();
    _successResetTimer = null;
    _cancelLoadingTimer();
    setState(() {
      _executionState = ComponentExecutionState.inProgress;
      _loadingVisible = false;
      _isPressed = false;
    });
    _loadingTimer = Timer(_loadingDelay, () {
      if (!mounted) return;
      setState(() {
        _loadingVisible = true;
        _isPressed = false;
      });
      _syncLoadingController();
    });

    try {
      await Future.sync(callback);
      if (!mounted) {
        return;
      }

      final loadingPending = _loadingTimer?.isActive ?? false;
      final shouldShowSuccess =
          widget.shouldSurfaceExecutionStates &&
          (_loadingVisible ||
              (loadingPending && widget.shouldShowSuccessConfirmation));

      _cancelLoadingTimer();

      if (shouldShowSuccess) {
        _showSuccessForDuration();
      } else {
        _clearExecutionState();
      }
    } catch (_) {
      if (mounted) {
        _cancelLoadingTimer();
        _clearExecutionState();
      }
    }
  }

  void _handleTapDown(TapDownDetails details) {
    widget.onTapDown?.call(details);
    _setPressed(true);
  }

  void _cancelLoadingTimer() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
  }

  void _clearExecutionState() {
    setState(() {
      _executionState = ComponentExecutionState.idle;
      _loadingVisible = false;
      _isPressed = false;
    });
    _syncLoadingController();
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
      setState(() {
        _executionState = ComponentExecutionState.idle;
        _loadingVisible = false;
      });
      _syncLoadingController();
    });
  }

  _ResolvedIconButtonColors _colors(BuildContext context) {
    if (_showLoading) {
      return _ResolvedIconButtonColors(
        background: _executionBackground(context),
        foreground: _foreground(context),
      );
    }
    if (_showSuccess) {
      return _ResolvedIconButtonColors(
        background: _executionBackground(context),
        foreground: _foreground(context, isSuccess: true),
      );
    }
    if (!_hasGestureCallback) {
      return _ResolvedIconButtonColors(
        background: _disabledBackground(context),
        foreground: _foreground(context, isDisabled: true),
      );
    }

    return _ResolvedIconButtonColors(
      background: _isPressed
          ? _pressedBackground(context)
          : _isHovered
          ? _hoverBackground(context)
          : _background(context),
      foreground: _foreground(context),
    );
  }

  Color _background(BuildContext context) {
    final colors = context.componentColors;
    final transparent = colors.specialScrim.withAlpha(0);

    return switch (widget.variant) {
      IconButtonComponentVariant.unfilled ||
      IconButtonComponentVariant.secondary => transparent,
      IconButtonComponentVariant.primary => colors.fillLight,
      IconButtonComponentVariant.critical => colors.fillDark,
      IconButtonComponentVariant.green => colors.primary,
      IconButtonComponentVariant.circular => colors.fillLight,
    };
  }

  Color _hoverBackground(BuildContext context) {
    final colors = context.componentColors;
    final transparent = colors.specialScrim.withAlpha(0);

    return switch (widget.variant) {
      IconButtonComponentVariant.unfilled ||
      IconButtonComponentVariant.secondary => transparent,
      IconButtonComponentVariant.primary => colors.fillDark,
      IconButtonComponentVariant.critical => colors.fillDarker,
      IconButtonComponentVariant.green => colors.primaryDark,
      IconButtonComponentVariant.circular => colors.fillDark,
    };
  }

  Color _pressedBackground(BuildContext context) {
    final colors = context.componentColors;
    final transparent = colors.specialScrim.withAlpha(0);

    return switch (widget.variant) {
      IconButtonComponentVariant.unfilled ||
      IconButtonComponentVariant.secondary => transparent,
      IconButtonComponentVariant.primary => colors.fillDarker,
      IconButtonComponentVariant.critical => colors.fillDarkest,
      IconButtonComponentVariant.green => colors.primaryDarker,
      IconButtonComponentVariant.circular => colors.fillDarker,
    };
  }

  Color _disabledBackground(BuildContext context) {
    final colors = context.componentColors;
    final transparent = colors.specialScrim.withAlpha(0);

    return switch (widget.variant) {
      IconButtonComponentVariant.unfilled ||
      IconButtonComponentVariant.secondary => transparent,
      IconButtonComponentVariant.primary ||
      IconButtonComponentVariant.critical ||
      IconButtonComponentVariant.green ||
      IconButtonComponentVariant.circular => colors.fillDark,
    };
  }

  Color _executionBackground(BuildContext context) {
    final colors = context.componentColors;
    final transparent = colors.specialScrim.withAlpha(0);

    return switch (widget.variant) {
      IconButtonComponentVariant.unfilled ||
      IconButtonComponentVariant.secondary => transparent,
      IconButtonComponentVariant.primary ||
      IconButtonComponentVariant.critical => colors.fillDark,
      IconButtonComponentVariant.green => colors.primary,
      IconButtonComponentVariant.circular => colors.fillLight,
    };
  }

  Color _foreground(
    BuildContext context, {
    bool isSuccess = false,
    bool isDisabled = false,
  }) {
    final colors = context.componentColors;
    if (isDisabled) {
      return colors.textLighter;
    }
    if (isSuccess && widget.variant != IconButtonComponentVariant.green) {
      return colors.primary;
    }
    if (widget.variant == IconButtonComponentVariant.green && !isDisabled) {
      return colors.specialWhite;
    }
    if (widget.variant == IconButtonComponentVariant.unfilled ||
        widget.variant == IconButtonComponentVariant.secondary) {
      return colors.iconColor;
    }
    return colors.textBase;
  }
}

const double _buttonSize = 36;
const double _iconSize = IconSizes.small;

class _ResolvedIconButtonColors {
  const _ResolvedIconButtonColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
