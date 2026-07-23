import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:photos/models/execution_states.dart';
import 'package:photos/models/typedefs.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/menu_item_widget/menu_item_child_widgets.dart';

class MenuItemWidget extends StatefulWidget {
  final Widget captionedTextWidget;
  final bool isExpandable;

  /// leading icon can be passed without specifing size of icon,
  /// this component sets size to 20x20 irrespective of passed icon's size
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  final Widget? leadingIconWidget;

  // leadIconSize deafult value is 20.
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

  final EdgeInsets? padding;

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

  const MenuItemWidget({
    required this.captionedTextWidget,
    this.isExpandable = false,
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
    this.alignCaptionedTextToLeft = false,
    this.singleBorderRadius = 4.0,
    this.multipleBorderRadius = 8.0,
    this.pressedColor,
    this.expandableController,
    this.isBottomBorderRadiusRemoved = false,
    this.isTopBorderRadiusRemoved = false,
    this.isGestureDetectorDisabled = false,
    this.showOnlyLoadingState = false,
    this.surfaceExecutionStates = false,
    this.alwaysShowSuccessState = false,
    this.padding,
    super.key,
  });

  @override
  State<MenuItemWidget> createState() => _MenuItemWidgetState();
}

class _MenuItemWidgetState extends State<MenuItemWidget> {
  final _debouncer = Debouncer(const Duration(milliseconds: 300));
  ValueNotifier<ExecutionState> executionStateNotifier = ValueNotifier(
    ExecutionState.idle,
  );
  VoidCallback? _expandableControllerListener;

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
      _expandableControllerListener = () {
        setState(() {});
      };
      widget.expandableController!.addListener(_expandableControllerListener!);
    }
    super.initState();
  }

  @override
  void didChangeDependencies() {
    menuItemColor = widget.menuItemColor;
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant MenuItemWidget oldWidget) {
    menuItemColor = widget.menuItemColor;
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    if (widget.expandableController != null) {
      if (_expandableControllerListener != null) {
        widget.expandableController!.removeListener(
          _expandableControllerListener!,
        );
      }
      widget.expandableController!.dispose();
    }
    _debouncer.cancelDebounceTimer();
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 20),
      width: double.infinity,
      padding: widget.padding ?? const EdgeInsets.only(left: 16, right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: topBorderRadius,
          topRight: topBorderRadius,
          bottomLeft: bottomBorderRadius,
          bottomRight: bottomBorderRadius,
        ),
        color: menuItemColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!widget.alignCaptionedTextToLeft || widget.leadingIcon != null)
            LeadingWidget(
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
    }, onError: (error, stackTrace) => _debouncer.cancelDebounceTimer());
    _debouncer.cancelDebounceTimer();
    if (widget.alwaysShowSuccessState) {
      Future.delayed(const Duration(seconds: 2), () {
        executionStateNotifier.value = ExecutionState.idle;
      });
      return;
    }
    if (executionStateNotifier.value == ExecutionState.inProgress) {
      if (widget.showOnlyLoadingState) {
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
      if (!mounted) {
        return;
      }
      setState(() {
        menuItemColor = widget.menuItemColor;
      });
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
