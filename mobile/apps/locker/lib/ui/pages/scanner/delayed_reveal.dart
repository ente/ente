import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

class DelayedReveal extends StatefulWidget {
  const DelayedReveal({
    super.key,
    required this.visible,
    required this.child,
    required this.delay,
  });

  final bool visible;
  final Widget child;
  final Duration delay;

  @override
  State<DelayedReveal> createState() => _DelayedRevealState();
}

class _DelayedRevealState extends State<DelayedReveal> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DelayedReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (widget.visible) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    } else if (_shown) {
      setState(() => _shown = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.standard,
      curve: Curves.easeInOut,
      child: _shown
          ? AnimatedOpacity(
              opacity: 1,
              duration: Motion.standard,
              child: widget.child,
            )
          : const SizedBox.shrink(),
    );
  }
}
