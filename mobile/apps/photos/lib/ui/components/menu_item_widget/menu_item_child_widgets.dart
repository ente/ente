import 'package:flutter/material.dart';
import 'package:photos/models/execution_states.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/common/loading_widget.dart';

class TrailingWidget extends StatefulWidget {
  final ValueNotifier executionStateNotifier;
  final IconData? trailingIcon;
  final Color? trailingIconColor;
  final Widget? trailingWidget;
  final bool trailingIconIsMuted;
  final double trailingExtraMargin;
  final bool showExecutionStates;
  const TrailingWidget({
    required this.executionStateNotifier,
    this.trailingIcon,
    this.trailingIconColor,
    this.trailingWidget,
    required this.trailingIconIsMuted,
    required this.trailingExtraMargin,
    required this.showExecutionStates,
    super.key,
  });
  @override
  State<TrailingWidget> createState() => _TrailingWidgetState();
}

class _TrailingWidgetState extends State<TrailingWidget> {
  Widget? trailingWidget;
  bool _listenerAdded = false;
  bool _didInitialize = false;

  @override
  void initState() {
    super.initState();
    if (widget.showExecutionStates) {
      widget.executionStateNotifier.addListener(_executionStateListener);
      _listenerAdded = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitialize) {
      _didInitialize = true;
      _setTrailingIcon();
    }
  }

  @override
  void didUpdateWidget(covariant TrailingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle showExecutionStates flag changes
    if (oldWidget.showExecutionStates && !widget.showExecutionStates) {
      // Was true, now false: remove listener and reset to icon
      if (_listenerAdded) {
        oldWidget.executionStateNotifier.removeListener(
          _executionStateListener,
        );
        _listenerAdded = false;
      }
      _setTrailingIcon();
    } else if (!oldWidget.showExecutionStates && widget.showExecutionStates) {
      // Was false, now true: add listener
      widget.executionStateNotifier.addListener(_executionStateListener);
      _listenerAdded = true;
    } else if (!widget.showExecutionStates) {
      // Still false: update the trailing icon if props changed
      _setTrailingIcon();
    }
  }

  @override
  void dispose() {
    if (_listenerAdded) {
      widget.executionStateNotifier.removeListener(_executionStateListener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 175),
      switchInCurve: Curves.easeInExpo,
      switchOutCurve: Curves.easeOutExpo,
      child: trailingWidget,
    );
  }

  void _executionStateListener() {
    if (!mounted) return;
    final colorScheme = getEnteColorScheme(context);
    setState(() {
      if (widget.executionStateNotifier.value == ExecutionState.idle) {
        _setTrailingIcon();
      } else if (widget.executionStateNotifier.value ==
          ExecutionState.inProgress) {
        trailingWidget = EnteLoadingWidget(
          key: const ValueKey('loading'),
          color: colorScheme.strokeMuted,
        );
      } else if (widget.executionStateNotifier.value ==
          ExecutionState.successful) {
        trailingWidget = Icon(
          Icons.check_outlined,
          key: const ValueKey('success'),
          size: 22,
          color: colorScheme.primary500,
        );
      } else {
        trailingWidget = const SizedBox.shrink(key: ValueKey('empty'));
      }
    });
  }

  void _setTrailingIcon() {
    if (widget.trailingIcon != null) {
      trailingWidget = Padding(
        key: const ValueKey('icon'),
        padding: EdgeInsets.only(right: widget.trailingExtraMargin),
        child: Icon(
          widget.trailingIcon,
          color: widget.trailingIconIsMuted
              ? getEnteColorScheme(context).strokeMuted
              : widget.trailingIconColor,
        ),
      );
    } else {
      trailingWidget =
          widget.trailingWidget ??
          const SizedBox.shrink(key: ValueKey('empty'));
    }
  }
}

class ExpansionTrailingIcon extends StatelessWidget {
  final bool isExpanded;
  final IconData? trailingIcon;
  final Color? trailingIconColor;
  const ExpansionTrailingIcon({
    required this.isExpanded,
    this.trailingIcon,
    this.trailingIconColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
      opacity: isExpanded ? 0 : 1,
      child: AnimatedSwitcher(
        transitionBuilder: (child, animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        child: isExpanded
            ? const SizedBox.shrink()
            : Icon(trailingIcon, color: trailingIconColor),
      ),
    );
  }
}

class LeadingWidget extends StatelessWidget {
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  final Widget? leadingIconWidget;
  // leadIconSize default value is 20.
  final double leadingIconSize;
  const LeadingWidget({
    required this.leadingIconSize,
    this.leadingIcon,
    this.leadingIconColor,
    this.leadingIconWidget,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
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
