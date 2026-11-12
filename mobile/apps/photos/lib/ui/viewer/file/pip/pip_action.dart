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

// Publishes the player's Picture-in-Picture action to the viewer menu.
//
// Uses the same owner token as `VideoStreamChangeController`, so a retiring
// player can't clear a newer player's action.
class VideoPipController extends ValueNotifier<VideoPipState?> {
  VideoPipController() : super(null);

  Object? _owner;

  void update(Object owner, VideoPipState state) {
    _owner = owner;
    value = state;
  }

  void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    value = null;
  }
}
