import 'dart:async';
import 'dart:math' as math;

import 'package:ente_components/models/component_execution_state.dart';
import 'package:ente_components/src/components/menu_component_surface_style.dart';
import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

const double _menuItemVerticalPadding = 9;
const double _leadingSlotSize = 36;
const double _trailingSlotSize = 36;
const Duration _loadingDelay = Duration(milliseconds: 300);
const Duration _successDisplayDuration = Duration(seconds: 1);
const int _maxTitleLines = 2;
const int _maxCombinedTextLines = 3;

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=4055-18734&m=dev
/// Section: List items / Menu Item
/// Specs: 336px by typography-derived menu item, optional leading icon, subtitle, trailing item, hover and selected states.
class MenuComponent extends StatefulWidget {
  const MenuComponent({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.isDisabled = false,
    this.showOnlyLoadingState = false,
    this.shouldSurfaceExecutionStates = false,
    this.shouldShowSuccessConfirmation = false,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 2,
    this.titleColor,
    this.iconColor,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final FutureOr<void> Function()? onTap;
  final FutureOr<void> Function()? onDoubleTap;
  final VoidCallback? onLongPress;
  final bool isDisabled;
  final bool showOnlyLoadingState;
  final bool shouldSurfaceExecutionStates;
  final bool shouldShowSuccessConfirmation;
  final int titleMaxLines;
  final int subtitleMaxLines;
  final Color? titleColor;
  final Color? iconColor;

  @override
  State<MenuComponent> createState() => _MenuComponentState();
}

class _MenuComponentState extends State<MenuComponent> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _loadingVisible = false;
  Timer? _loadingTimer;
  ComponentExecutionState _executionState = ComponentExecutionState.idle;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final enabled = _canHandleGestures;
    final trailing = _trailing(colors);
    final shouldReserveTrailingSlot = _shouldReserveTrailingSlot;
    final surfaceStyle = MenuComponentSurfaceStyle.maybeOf(context);
    final borderRadius =
        surfaceStyle?.borderRadius ?? BorderRadius.circular(Radii.button);
    return UnconstrainedBox(
      alignment: Alignment.topLeft,
      constrainedAxis: Axis.horizontal,
      child: Material(
        color: Colors.transparent,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: enabled ? (_) => _setHovered(true) : null,
          onExit: enabled ? (_) => _setHovered(false) : null,
          child: InkWell(
            onTap: enabled && widget.onTap != null ? _handleTap : null,
            onDoubleTap: enabled && widget.onDoubleTap != null
                ? _handleDoubleTap
                : null,
            onLongPress: enabled ? widget.onLongPress : null,
            onHighlightChanged: enabled ? _setPressed : null,
            borderRadius: borderRadius,
            child: AnimatedContainer(
              key: const ValueKey('menu-item-surface'),
              duration: Motion.quick,
              decoration: BoxDecoration(
                color: _backgroundColor(
                  colors,
                  enabled,
                  surfaceStyle?.backgroundColor,
                ),
                border: Border.all(
                  color: widget.selected
                      ? colors.strokeDark
                      : Colors.transparent,
                ),
                borderRadius: borderRadius,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: _minimumHeight()),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: widget.leading == null ? Spacing.lg : Spacing.md,
                    right: Spacing.md,
                    top: _menuItemVerticalPadding,
                    bottom: _menuItemVerticalPadding,
                  ),
                  child: Row(
                    children: [
                      if (widget.leading != null) ...[
                        SizedBox.square(
                          dimension: _leadingSlotSize,
                          child: Center(
                            child: IconTheme.merge(
                              data: IconThemeData(
                                color: widget.iconColor ?? colors.textLight,
                                size: IconSizes.small,
                              ),
                              child: widget.leading!,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                      ],
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final titleMaxLines = _effectiveTitleMaxLines;
                            final subtitleMaxLines = _effectiveSubtitleMaxLines(
                              context,
                              constraints.maxWidth,
                              titleMaxLines,
                            );
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: titleMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyles.body.copyWith(
                                    color: widget.titleColor ?? colors.textBase,
                                  ),
                                ),
                                if (widget.subtitle != null) ...[
                                  const SizedBox(height: Spacing.xs),
                                  Text(
                                    widget.subtitle!,
                                    maxLines: subtitleMaxLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyles.mini.copyWith(
                                      color: colors.textLight,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                      if (shouldReserveTrailingSlot) ...[
                        const SizedBox(width: Spacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: _trailingSlotSize,
                            minHeight: _trailingSlotSize,
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: Motion.quick,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child:
                                  trailing ??
                                  const SizedBox.shrink(
                                    key: ValueKey('menu-item-empty-trailing'),
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  bool get _canHandleGestures {
    return !widget.isDisabled && _hasGestureCallbacks && !_isBusy;
  }

  bool get _hasGestureCallbacks {
    return widget.onTap != null ||
        widget.onDoubleTap != null ||
        widget.onLongPress != null;
  }

  bool get _isBusy => _executionState == ComponentExecutionState.inProgress;

  int get _effectiveTitleMaxLines {
    return math.min(_positiveLineCount(widget.titleMaxLines), _maxTitleLines);
  }

  int _effectiveSubtitleMaxLines(
    BuildContext context,
    double maxWidth,
    int titleMaxLines,
  ) {
    if (widget.subtitle == null) {
      return 0;
    }
    final requestedSubtitleLines = _positiveLineCount(widget.subtitleMaxLines);
    final titleLineCount = _measuredTitleLineCount(
      context,
      maxWidth,
      titleMaxLines,
    );
    final remainingLines = _maxCombinedTextLines - titleLineCount;
    return math.min(requestedSubtitleLines, math.max(1, remainingLines));
  }

  int _measuredTitleLineCount(
    BuildContext context,
    double maxWidth,
    int titleMaxLines,
  ) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return titleMaxLines;
    }

    final painter = TextPainter(
      text: TextSpan(text: widget.title, style: TextStyles.body),
      maxLines: titleMaxLines,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    return math.max(
      1,
      math.min(titleMaxLines, painter.computeLineMetrics().length),
    );
  }

  int _positiveLineCount(int value) {
    return math.max(1, value);
  }

  void _handleDoubleTap() {
    final onDoubleTap = widget.onDoubleTap;
    if (onDoubleTap == null) {
      return;
    }

    unawaited(Future.sync(onDoubleTap));
  }

  bool get _showsLoading =>
      _executionState == ComponentExecutionState.inProgress && _loadingVisible;

  bool get _showsSuccess =>
      _executionState == ComponentExecutionState.successful;

  bool get _shouldSurfaceExecutionState {
    return widget.shouldSurfaceExecutionStates || widget.showOnlyLoadingState;
  }

  bool get _shouldReserveTrailingSlot {
    return widget.trailing != null ||
        (!widget.isDisabled &&
            widget.onTap != null &&
            _shouldSurfaceExecutionState);
  }

  Color _backgroundColor(
    ColorTokens colors,
    bool enabled,
    Color? backgroundColor,
  ) {
    if (_isPressed) {
      return colors.fillDarker;
    }
    if (_isHovered && enabled) {
      return colors.fillDark;
    }
    return backgroundColor ?? colors.fillLight;
  }

  Widget? _trailing(ColorTokens colors) {
    if (_showsLoading && _shouldSurfaceExecutionState) {
      return SizedBox.square(
        key: const ValueKey('menu-item-loading'),
        dimension: IconSizes.small,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(colors.textLight),
        ),
      );
    }
    if (_showsSuccess && _shouldShowSuccess) {
      return Icon(
        key: const ValueKey('menu-item-success'),
        Icons.check_rounded,
        color: colors.primary,
        size: IconSizes.small,
      );
    }
    return widget.trailing;
  }

  bool get _shouldShowSuccess {
    return widget.shouldSurfaceExecutionStates && !widget.showOnlyLoadingState;
  }

  double _minimumHeight() {
    final textHeight =
        _lineHeight(TextStyles.body) +
        Spacing.xs +
        _lineHeight(TextStyles.mini);
    final contentHeight = textHeight > _leadingSlotSize
        ? textHeight
        : _leadingSlotSize;
    return contentHeight + (_menuItemVerticalPadding * 2);
  }

  double _lineHeight(TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    final height = style.height ?? 1;
    return fontSize * height;
  }

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() => _isHovered = value);
  }

  void _setPressed(bool value) {
    if (_isPressed == value) {
      return;
    }
    setState(() => _isPressed = value);
  }

  Future<void> _handleTap() async {
    if (!_canHandleGestures) {
      return;
    }

    var loadingWasShown = false;
    _loadingTimer?.cancel();
    setState(() {
      _executionState = ComponentExecutionState.inProgress;
      _loadingVisible = false;
    });
    _loadingTimer = Timer(_loadingDelay, () {
      if (!mounted || !_isBusy) {
        return;
      }
      loadingWasShown = true;
      setState(() => _loadingVisible = true);
    });

    try {
      await widget.onTap?.call();
      if (!mounted) {
        return;
      }

      final loadingPending = _loadingTimer?.isActive ?? false;
      _loadingTimer?.cancel();
      _loadingTimer = null;

      final shouldShowSuccess =
          _shouldShowSuccess &&
          (loadingWasShown ||
              (loadingPending && widget.shouldShowSuccessConfirmation));
      if (shouldShowSuccess) {
        await _showSuccessThenReset();
        return;
      }

      _resetExecutionState();
    } catch (_) {
      _loadingTimer?.cancel();
      _loadingTimer = null;
      if (mounted) {
        _resetExecutionState();
      }
    }
  }

  Future<void> _showSuccessThenReset() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _executionState = ComponentExecutionState.successful;
      _loadingVisible = false;
    });
    await Future<void>.delayed(_successDisplayDuration);
    if (mounted) {
      _resetExecutionState();
    }
  }

  void _resetExecutionState() {
    _loadingTimer?.cancel();
    setState(() {
      _executionState = ComponentExecutionState.idle;
      _isPressed = false;
      _loadingVisible = false;
    });
  }
}
