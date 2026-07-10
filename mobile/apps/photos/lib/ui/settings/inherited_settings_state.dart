import 'package:ente_pure_utils/ente_pure_utils.dart';
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
  bool _isSubpageOpen = false;

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

  Future<T?> pushPage<T extends Object>(
    BuildContext context,
    Widget page, {
    bool isTopLevel = false,
    bool useFadeTransition = false,
  }) async {
    final shouldSlideSettingsPage = isTopLevel && !useFadeTransition;
    if (shouldSlideSettingsPage) {
      setState(() {
        _isSubpageOpen = true;
      });
    }
    try {
      return await routeToPage<T>(
        context,
        page,
        isTopLevel: isTopLevel,
        useFadeTransition: useFadeTransition,
      );
    } finally {
      if (shouldSlideSettingsPage && mounted) {
        setState(() {
          _isSubpageOpen = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InheritedSettingsState(
      expandedSectionCount: _expandedSectionCount,
      increment: increment,
      decrement: decrement,
      pushPage: pushPage,
      child: AnimatedSlide(
        offset: _isSubpageOpen ? const Offset(-1.0 / 3.0, 0) : Offset.zero,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linearToEaseOut,
        child: widget.child,
      ),
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
  final Future<T?> Function<T extends Object>(
    BuildContext,
    Widget, {
    bool isTopLevel,
    bool useFadeTransition,
  })
  pushPage;

  const InheritedSettingsState({
    super.key,
    required this.expandedSectionCount,
    required this.increment,
    required this.decrement,
    required this.pushPage,
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
