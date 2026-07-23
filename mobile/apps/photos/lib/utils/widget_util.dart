import "dart:async";

import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";

// Warning: This can get expensive depending on the widget passed.
// Read: https://api.flutter.dev/flutter/widgets/IntrinsicHeight-class.html
// From: https://stackoverflow.com/a/75714610/17561985
Future<Size> getIntrinsicSizeOfWidget(Widget widget, BuildContext context) {
  final Completer<Size> completer = Completer<Size>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Center(
      child: WidgetSizeGetterTempWidget(
        onDone: (Size s) {
          entry.remove();
          completer.complete(s);
        },
        child: Opacity(
          opacity: 0,
          child: IntrinsicHeight(child: IntrinsicWidth(child: widget)),
        ),
      ),
    ),
  );
  Future.delayed(const Duration(milliseconds: 0), () {
    if (context.mounted) {
      Overlay.of(context).insert(entry);
    }
  });

  return completer.future;
}

class WidgetSizeGetterTempWidget extends StatefulWidget {
  final Widget child;
  final Function onDone;

  const WidgetSizeGetterTempWidget({
    super.key,
    required this.onDone,
    required this.child,
  });

  @override
  // ignore: library_private_types_in_public_api
  _WidgetSizeGetterTempWidgetState createState() =>
      _WidgetSizeGetterTempWidgetState();
}

class _WidgetSizeGetterTempWidgetState
    extends State<WidgetSizeGetterTempWidget> {
  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback(postFrameCallback);
    return Container(key: widgetKey, child: widget.child);
  }

  var widgetKey = GlobalKey();
  Size? oldSize;

  void postFrameCallback(_) {
    final context = widgetKey.currentContext;
    if (context == null) return;

    final newSize = context.size;
    if (oldSize == newSize) return;

    oldSize = newSize;
    widget.onDone(newSize);
  }
}
