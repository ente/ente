import "dart:async";
import "dart:ui";

import "package:flutter/scheduler.dart";

class RewindFrameStepper {
  RewindFrameStepper(this.frameRate);

  final int frameRate;
  final _binding = SchedulerBinding.instance;
  final _dispatcher = PlatformDispatcher.instance;
  FrameCallback? _beginFrame;
  VoidCallback? _drawFrame;
  Completer<void>? _pending;
  var _origin = Duration.zero;
  var _frame = 0;
  var _installed = false;
  var _drawing = false;

  void install() {
    if (_installed) return;
    _installed = true;
    _beginFrame = _dispatcher.onBeginFrame;
    _drawFrame = _dispatcher.onDrawFrame;
    _origin = _binding.currentSystemFrameTimeStamp;
    _dispatcher
      ..onBeginFrame = _onBeginFrame
      ..onDrawFrame = _onDrawFrame;
  }

  Future<void> step() {
    final pending = _pending = Completer<void>();
    _dispatcher.scheduleFrame();
    return pending.future;
  }

  void resume() {
    if (_installed && _pending != null) _dispatcher.scheduleFrame();
  }

  void uninstall() {
    if (!_installed) return;
    _installed = false;
    _dispatcher
      ..onBeginFrame = _beginFrame
      ..onDrawFrame = _drawFrame;
    _pending = null;
    _binding.resetEpoch();
    _dispatcher.scheduleFrame();
  }

  void _onBeginFrame(Duration _) {
    if (_pending == null || _drawing) return;
    _drawing = true;
    _frame++;
    _binding.handleBeginFrame(
      _origin +
          Duration(
            microseconds: (_frame * Duration.microsecondsPerSecond / frameRate)
                .round(),
          ),
    );
  }

  void _onDrawFrame() {
    if (!_drawing) return;
    _drawing = false;
    _binding.handleDrawFrame();
    final pending = _pending;
    _pending = null;
    pending?.complete();
  }
}
