import 'package:ente_base/typedefs.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_ui/components/menu_item_child_widgets.dart';
import 'package:ente_ui/models/execution_states.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import "package:expandable/expandable.dart";
import 'package:flutter/material.dart';

class MenuItemWidgetV2 extends StatefulWidget {
  final Widget captionedTextWidget;
  final bool isExpandable;

  /// leading icon can be passed without specifing size of icon,
  /// this component sets size to 24x24 irrespective of passed icon's size
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  final Widget? leadingIconWidget;

  // leadIconSize deafult value is 24.
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
  final bool alignCaptionedTextToLeft;

  // singleBorderRadius is applied to the border when it's a standalone menu item.
  // Widget will apply singleBorderRadius if value of both isTopBorderRadiusRemoved
  // and isBottomBorderRadiusRemoved is false. Otherwise, multipleBorderRadius will
  // be applied
  final double singleBorderRadius;
  final double multipleBorderRadius;
  final Color? pressedColor;
  final ExpandableController? expandableController;
  final bool isBottomBorderRadiusRemoved;
  final bool isTopBorderRadiusRemoved;

  final bool isFirstItem;

  final bool isLastItem;

  /// disable gesture detector if not used
  final bool isGestureDetectorDisabled;

  ///Success state will not be shown if this flag is set to true, only idle and
  ///loading state
  final bool showOnlyLoadingState;

  final bool surfaceExecutionStates;

  ///To show success state even when execution time < debouce time, set this
  ///flag to true. If the loading state needs to be shown and success state not,
  ///set the showOnlyLoadingState flag to true, setting this flag to false won't
  ///help.
  final bool alwaysShowSuccessState;

  const MenuItemWidgetV2({
    required this.captionedTextWidget,
    this.isExpandable = false,
    this.leadingIcon,
    this.leadingIconColor,
    this.leadingIconSize = 24.0,
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
    this.alignCaptionedTextToLeft = false,
    this.singleBorderRadius = 16.0,
    this.multipleBorderRadius = 20.0,
    this.pressedColor,
    this.expandableController,
    this.isBottomBorderRadiusRemoved = false,
    this.isTopBorderRadiusRemoved = false,
    this.isFirstItem = false,
    this.isLastItem = false,
    this.isGestureDetectorDisabled = false,
    this.showOnlyLoadingState = false,
    this.surfaceExecutionStates = true,
    this.alwaysShowSuccessState = false,
    super.key,
  });

  @override
  State<MenuItemWidgetV2> createState() => _MenuItemWidgetV2State();
}

class _MenuItemWidgetV2State extends State<MenuItemWidgetV2> {
  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  ValueNotifier<ExecutionState> executionStateNotifier = ValueNotifier(
    ExecutionState.idle,
  );

  Color? menuItemColor;
  late double borderRadius;

  @override
  void initState() {
    menuItemColor = widget.menuItemColor;
    borderRadius =
        (widget.isBottomBorderRadiusRemoved || widget.isTopBorderRadiusRemoved)
        ? widget.multipleBorderRadius
        : widget.singleBorderRadius;
    if (widget.expandableController != null) {
      widget.expandableController!.addListener(() {
        setState(() {});
      });
    }
    super.initState();
  }

  @override
  void didChangeDependencies() {
    menuItemColor = widget.menuItemColor;
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant MenuItemWidgetV2 oldWidget) {
    menuItemColor = widget.menuItemColor;
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    if (widget.expandableController != null) {
      widget.expandableController!.dispose();
    }
    executionStateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isExpandable || widget.isGestureDetectorDisabled
        ? menuItemWidget(context)
        : GestureDetector(
            onTap: _onTap,
            onDoubleTap: widget.onDoubleTap,
            onLongPress: widget.onLongPress,
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onCancel,
            child: menuItemWidget(context),
          );
  }

  Widget menuItemWidget(BuildContext context) {
    final circularRadius = Radius.circular(borderRadius);
    final isExpanded = widget.expandableController?.value;
    final bottomBorderRadius =
        (isExpanded != null && isExpanded) || widget.isBottomBorderRadiusRemoved
        ? const Radius.circular(0)
        : circularRadius;
    final topBorderRadius = widget.isTopBorderRadiusRemoved
        ? const Radius.circular(0)
        : circularRadius;
    final isFirst = widget.isFirstItem || !widget.isTopBorderRadiusRemoved;
    final isLast = widget.isLastItem || !widget.isBottomBorderRadiusRemoved;
    final topPadding = isFirst ? 2.0 : 0.0;
    final bottomPadding = isLast ? 2.0 : 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 20),
      width: double.infinity,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: topPadding,
        bottom: bottomPadding,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: topBorderRadius,
          topRight: topBorderRadius,
          bottomLeft: bottomBorderRadius,
          bottomRight: bottomBorderRadius,
        ),
        color: menuItemColor,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            widget.alignCaptionedTextToLeft && widget.leadingIcon == null
                ? const SizedBox.shrink()
                : LeadingWidgetV2(
                    leadingIconSize: widget.leadingIconSize,
                    leadingIcon: widget.leadingIcon,
                    leadingIconColor: widget.leadingIconColor,
                    leadingIconWidget: widget.leadingIconWidget,
                  ),
            widget.captionedTextWidget,
            if (widget.expandableController != null)
              ExpansionTrailingIcon(
                isExpanded: isExpanded!,
                trailingIcon: widget.trailingIcon,
                trailingIconColor: widget.trailingIconColor,
              )
            else
              TrailingWidget(
                executionStateNotifier: executionStateNotifier,
                trailingIcon: widget.trailingIcon,
                trailingIconColor: widget.trailingIconColor,
                trailingWidget: widget.trailingWidget,
                trailingIconIsMuted: widget.trailingIconIsMuted,
                trailingExtraMargin: widget.trailingExtraMargin,
                showExecutionStates: widget.surfaceExecutionStates,
                key: ValueKey(widget.trailingIcon.hashCode),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap() async {
    if (executionStateNotifier.value == ExecutionState.inProgress ||
        executionStateNotifier.value == ExecutionState.successful) {
      return;
    }
    _debouncer.run(
      () => Future(() {
        executionStateNotifier.value = ExecutionState.inProgress;
      }),
    );
    await widget.onTap?.call().then((value) {
      widget.alwaysShowSuccessState
          ? executionStateNotifier.value = ExecutionState.successful
          : null;
    }, onError: (error, stackTrace) => _debouncer.cancelDebounce());
    _debouncer.cancelDebounce();
    if (widget.alwaysShowSuccessState) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          executionStateNotifier.value = ExecutionState.idle;
        }
      });
      return;
    }
    if (executionStateNotifier.value == ExecutionState.inProgress) {
      if (widget.showOnlyLoadingState) {
        executionStateNotifier.value = ExecutionState.idle;
      } else {
        executionStateNotifier.value = ExecutionState.successful;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            executionStateNotifier.value = ExecutionState.idle;
          }
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
        hasPassedGestureCallbacks()
            ? menuItemColor = getEnteColorScheme(context).fillFaintPressed
            : menuItemColor = widget.menuItemColor;
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
    setState(() {
      menuItemColor = widget.menuItemColor;
    });
  }
}

class LeadingWidgetV2 extends StatelessWidget {
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  final Widget? leadingIconWidget;
  // leadIconSize deafult value is 24.
  final double leadingIconSize;
  const LeadingWidgetV2({
    super.key,
    required this.leadingIconSize,
    this.leadingIcon,
    this.leadingIconColor,
    this.leadingIconWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        height: leadingIconSize,
        width: leadingIconSize,
        child: leadingIcon == null
            ? (leadingIconWidget != null
                  ? FittedBox(fit: BoxFit.contain, child: leadingIconWidget)
                  : const SizedBox.shrink())
            : FittedBox(
                fit: BoxFit.contain,
                child: Icon(
                  leadingIcon,
                  color:
                      leadingIconColor ??
                      getEnteColorScheme(context).strokeBase,
                ),
              ),
      ),
    );
  }
}
