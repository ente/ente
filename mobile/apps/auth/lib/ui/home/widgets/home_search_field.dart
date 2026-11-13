import 'package:flutter/material.dart';

// Return false so the platform text input also receives the triggering key.
bool activateHomeSearchFromKeyEvent({
  required VoidCallback showSearch,
  required FocusNode focusNode,
}) {
  showSearch();
  focusNode.requestFocus();
  FocusManager.instance.applyFocusChangesIfNeeded();
  return false;
}

class PersistentSearchField extends StatelessWidget {
  const PersistentSearchField({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      descendantsAreTraversable: visible,
      child: Visibility(
        visible: visible,
        maintainState: true,
        maintainFocusability: true,
        child: child,
      ),
    );
  }
}
