import "package:flutter/foundation.dart";

@immutable
class VideoPipState {
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback? onMenuOpened;

  const VideoPipState({
    required this.canStart,
    required this.onStart,
    this.onMenuOpened,
  });
}

class VideoPipController extends ValueNotifier<VideoPipState?> {
  VideoPipController() : super(null);

  Object? _owner;

  void update(Object owner, VideoPipState state) {
    _owner = owner;
    value = state;
  }

  void clear(Object owner) {
    // Teardown may arrive after the replacement publishes its action.
    if (!identical(_owner, owner)) return;
    _owner = null;
    value = null;
  }
}
