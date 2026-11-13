import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class HorizontalScrollArea extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  const HorizontalScrollArea({super.key, required this.builder});

  @override
  State<HorizontalScrollArea> createState() => _HorizontalScrollAreaState();
}

class _HorizontalScrollAreaState extends State<HorizontalScrollArea> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) {
      return;
    }

    if (event.scrollDelta.dx != 0 || event.scrollDelta.dy == 0) {
      return;
    }

    final position = _controller.position;
    final nextOffset = (_controller.offset + event.scrollDelta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (nextOffset == _controller.offset) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _controller.jumpTo(nextOffset);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: ScrollConfiguration(
        behavior: const _HorizontalScrollBehavior(),
        child: widget.builder(context, _controller),
      ),
    );
  }
}

class _HorizontalScrollBehavior extends MaterialScrollBehavior {
  const _HorizontalScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}
