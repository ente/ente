import 'package:flutter/widgets.dart';

/// StatefulWidget that wraps InheritedSettingsState
class SettingsStateContainer extends StatefulWidget {
  const SettingsStateContainer({super.key, required this.child});
  final Widget child;

  @override
  State<SettingsStateContainer> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsStateContainer> {
  int _expandedSectionCount = 0;

  void increment() {
    setState(() {
      _expandedSectionCount += 1;
    });
  }

  void decrement() {
    setState(() {
      _expandedSectionCount -= 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return InheritedSettingsState(
      expandedSectionCount: _expandedSectionCount,
      increment: increment,
      decrement: decrement,
      child: widget.child,
    );
  }
}

/// Keep track of the number of expanded sections in an entire menu tree.
///
/// Since this is an InheritedWidget, subsections can obtain it from the context
/// and use the current expansion state to style themselves differently if
/// needed.
///
/// Example usage:
///
///     InheritedSettingsState.of(context).increment()
///
class InheritedSettingsState extends InheritedWidget {
  final int expandedSectionCount;
  final void Function() increment;
  final void Function() decrement;

  const InheritedSettingsState({
    super.key,
    required this.expandedSectionCount,
    required this.increment,
    required this.decrement,
    required super.child,
  });

  bool get isAnySectionExpanded => expandedSectionCount > 0;

  static InheritedSettingsState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InheritedSettingsState>()!;

  static InheritedSettingsState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InheritedSettingsState>();

  @override
  bool updateShouldNotify(covariant InheritedSettingsState oldWidget) {
    return isAnySectionExpanded != oldWidget.isAnySectionExpanded;
  }
}
