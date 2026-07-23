import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:photos/models/execution_states.dart';
import 'package:photos/models/typedefs.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/menu_item_widget/menu_item_child_widgets.dart';

/// A menu item widget with the new design system.
/// Features:
/// - 20px border radius
/// - 16px horizontal padding
/// - Background color: Light #FFFFFF, Dark #212121
class MenuItemWidgetNew extends StatefulWidget {
  final String title;
  final String? subText;
  final int titleMaxLines;
  final int subTextMaxLines;
  final TextStyle? subTextStyle;
  final double titleToSubTextSpacing;

  /// Color for the title text
  final Color? titleColor;

  /// leading icon can be passed without specifing size of icon,
  /// this component sets size to 20x20 irrespective of passed icon's size
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  final Widget? leadingIconWidget;

  // leadIconSize default value is 20.
  final double leadingIconSize;

  /// trailing icon can be passed without size as default size set by
  /// flutter is what this component expects
  final IconData? trailingIcon;
  final Color? trailingIconColor;
  final Widget? trailingWidget;
  final bool trailingIconIsMuted;

  /// If provided, add this much extra spacing to the right of the trailing icon.
  final double trailingExtraMargin;
  final FutureVoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final Color? menuItemColor;

  /// Border radius for the menu item, defaults to 20
  final double borderRadius;

  /// Inner padding for the menu item.
  final EdgeInsetsGeometry padding;

  final Color? pressedColor;

  /// disable gesture detector if not used
  final bool isGestureDetectorDisabled;

  /// Success state will not be shown if this flag is set to true, only idle and
  /// loading state
  final bool showOnlyLoadingState;

  final bool surfaceExecutionStates;

  /// To show success state even when execution time < debounce time, set this
  /// flag to true.
  final bool alwaysShowSuccessState;

  const MenuItemWidgetNew({
    required this.title,
    this.subText,
    this.titleMaxLines = 2,
    this.subTextMaxLines = 1,
    this.subTextStyle,
    this.titleToSubTextSpacing = 0.0,
    this.titleColor,
    this.leadingIcon,
    this.leadingIconColor,
    this.leadingIconSize = 20.0,
    this.leadingIconWidget,
    this.trailingIcon,
    this.trailingIconColor,
    this.trailingWidget,
    this.trailingIconIsMuted = false,
    this.trailingExtraMargin = 0.0,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.menuItemColor,
    this.borderRadius = 20.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    this.pressedColor,
    this.isGestureDetectorDisabled = false,
    this.showOnlyLoadingState = false,
    this.surfaceExecutionStates = false,
    this.alwaysShowSuccessState = false,
    super.key,
  });

  @override
  State<MenuItemWidgetNew> createState() => _MenuItemWidgetNewState();
}

class _MenuItemWidgetNewState extends State<MenuItemWidgetNew> {
  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  ValueNotifier<ExecutionState> executionStateNotifier = ValueNotifier(
    ExecutionState.idle,
  );

  Color? menuItemColor;

  @override
  void initState() {
    menuItemColor = widget.menuItemColor;
    super.initState();
  }

  @override
  void didChangeDependencies() {
    menuItemColor = widget.menuItemColor;
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant MenuItemWidgetNew oldWidget) {
    menuItemColor = widget.menuItemColor;
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    executionStateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isGestureDetectorDisabled || !hasPassedGestureCallbacks()
        ? _buildMenuItemContainer(context)
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap == null ? null : _onTap,
            onDoubleTap: widget.onDoubleTap,
            onLongPress: widget.onLongPress,
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onCancel,
            child: _buildMenuItemContainer(context),
          );
  }

  Widget _buildMenuItemContainer(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final circularRadius = Radius.circular(widget.borderRadius);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Figma colors: Light #FFFFFF, Dark #212121
    final defaultMenuItemColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFFFFFFF);

    final effectiveMenuItemColor = menuItemColor ?? defaultMenuItemColor;
    final bool hasSubText =
        widget.subText != null && widget.subText!.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 20),
      width: double.infinity,
      clipBehavior: Clip.none,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(circularRadius),
        color: effectiveMenuItemColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (widget.leadingIcon != null || widget.leadingIconWidget != null)
            LeadingWidget(
              leadingIconSize: widget.leadingIconSize,
              leadingIcon: widget.leadingIcon,
              leadingIconColor: widget.leadingIconColor,
              leadingIconWidget: widget.leadingIconWidget,
            ),
          Expanded(
            child: hasSubText
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: widget.titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: widget.titleColor != null
                            ? textTheme.small.copyWith(color: widget.titleColor)
                            : textTheme.small,
                      ),
                      if (widget.titleToSubTextSpacing > 0)
                        SizedBox(height: widget.titleToSubTextSpacing),
                      Text(
                        widget.subText!,
                        maxLines: widget.subTextMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style:
                            widget.subTextStyle ??
                            textTheme.tinyMuted.copyWith(height: 17 / 10),
                      ),
                    ],
                  )
                : Text(
                    widget.title,
                    maxLines: widget.titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: widget.titleColor != null
                        ? textTheme.small.copyWith(color: widget.titleColor)
                        : textTheme.small,
                  ),
          ),
          TrailingWidget(
            executionStateNotifier: executionStateNotifier,
            trailingIcon: widget.trailingIcon,
            trailingIconColor: widget.trailingIconColor,
            trailingWidget: widget.trailingWidget,
            trailingIconIsMuted: widget.trailingIconIsMuted,
            trailingExtraMargin: widget.trailingExtraMargin,
            showExecutionStates: widget.surfaceExecutionStates,
          ),
        ],
      ),
    );
  }

  Future<void> _onTap() async {
    if (executionStateNotifier.value == ExecutionState.inProgress ||
        executionStateNotifier.value == ExecutionState.successful) {
      return;
    }
    final shouldSurfaceExecutionStates =
        widget.surfaceExecutionStates || widget.alwaysShowSuccessState;
    _debouncer.run(
      () => Future(() {
        executionStateNotifier.value = ExecutionState.inProgress;
      }),
    );
    final onTapResult = widget.onTap?.call();
    if (onTapResult != null) {
      await onTapResult.then((value) {
        widget.alwaysShowSuccessState
            ? executionStateNotifier.value = ExecutionState.successful
            : null;
      }, onError: (error, stackTrace) => _debouncer.cancelDebounceTimer());
    }
    _debouncer.cancelDebounceTimer();
    if (widget.alwaysShowSuccessState) {
      Future.delayed(const Duration(seconds: 2), () {
        executionStateNotifier.value = ExecutionState.idle;
      });
      return;
    }
    if (executionStateNotifier.value == ExecutionState.inProgress) {
      if (widget.showOnlyLoadingState || !shouldSurfaceExecutionStates) {
        executionStateNotifier.value = ExecutionState.idle;
      } else {
        executionStateNotifier.value = ExecutionState.successful;
        Future.delayed(const Duration(seconds: 2), () {
          executionStateNotifier.value = ExecutionState.idle;
        });
      }
    }
  }

  void _onTapDown(TapDownDetails details) {
    if (executionStateNotifier.value == ExecutionState.inProgress ||
        executionStateNotifier.value == ExecutionState.successful) {
      return;
    }
    setState(() {
      if (widget.pressedColor == null) {
        if (hasPassedGestureCallbacks()) {
          final isDarkMode = Theme.of(context).brightness == Brightness.dark;
          // Pressed color: Light #F5F5F5, Dark #2C2C2C
          // These are the result of overlaying fillFaintPressed on the base color
          menuItemColor = isDarkMode
              ? const Color(0xFF2C2C2C)
              : const Color(0xFFF5F5F5);
        } else {
          menuItemColor = widget.menuItemColor;
        }
      } else {
        menuItemColor = widget.pressedColor;
      }
    });
  }

  bool hasPassedGestureCallbacks() {
    return widget.onDoubleTap != null ||
        widget.onTap != null ||
        widget.onLongPress != null;
  }

  void _onTapUp(TapUpDetails details) {
    if (executionStateNotifier.value == ExecutionState.inProgress ||
        executionStateNotifier.value == ExecutionState.successful) {
      return;
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          menuItemColor = widget.menuItemColor;
        });
      }
    });
  }

  void _onCancel() {
    if (executionStateNotifier.value == ExecutionState.inProgress ||
        executionStateNotifier.value == ExecutionState.successful) {
      return;
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          menuItemColor = widget.menuItemColor;
        });
      }
    });
  }
}
