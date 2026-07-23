import 'package:flutter/widgets.dart';

class KeyboardOverlay {
  static OverlayEntry? _overlayEntry;

  static void showOverlay(BuildContext context, Widget child) {
    if (_overlayEntry != null) {
      return;
    }

    final OverlayState overlayState = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          right: 0.0,
          left: 0.0,
          child: child,
        );
      },
    );

    overlayState.insert(_overlayEntry!);
  }

  static void removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
  }
}
