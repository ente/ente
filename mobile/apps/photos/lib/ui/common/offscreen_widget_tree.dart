import "dart:async";
import "dart:ui" as ui;

import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";

class OffscreenTreeBinding extends WidgetsFlutterBinding {
  static WidgetsBinding ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      return OffscreenTreeBinding();
    }
  }

  @override
  BuildOwner? get buildOwner =>
      OffscreenWidgetTree._current?._builds ?? super.buildOwner;

  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
    bool scheduleNewFrame = true,
  }) =>
      OffscreenWidgetTree._current?._schedule(callback) ??
      super.scheduleFrameCallback(
        callback,
        rescheduling: rescheduling,
        scheduleNewFrame: scheduleNewFrame,
      );

  @override
  void cancelFrameCallbackWithId(int id) {
    if (id < 0) {
      OffscreenWidgetTree._cancel(id);
    } else {
      super.cancelFrameCallbackWithId(id);
    }
  }

  @override
  void addPostFrameCallback(
    FrameCallback callback, {
    String debugLabel = "callback",
  }) {
    final tree = OffscreenWidgetTree._current;
    if (tree == null) {
      super.addPostFrameCallback(callback, debugLabel: debugLabel);
    } else {
      tree._postFrame.add(callback);
    }
  }

  @override
  void scheduleFrame() {
    if (OffscreenWidgetTree._current == null) super.scheduleFrame();
  }

  @override
  void scheduleForcedFrame() {
    if (OffscreenWidgetTree._current == null) super.scheduleForcedFrame();
  }

  @override
  Duration get currentFrameTimeStamp =>
      OffscreenWidgetTree._current?._time ?? super.currentFrameTimeStamp;

  @override
  SchedulerPhase get schedulerPhase =>
      OffscreenWidgetTree._current?._phase ?? super.schedulerPhase;
}

class OffscreenWidgetTree {
  OffscreenWidgetTree({
    required Widget child,
    required Size size,
    required this.pixelRatio,
    required int frameRate,
  }) : _child = child,
       _frameRate = frameRate {
    final view =
        ui.PlatformDispatcher.instance.implicitView ??
        ui.PlatformDispatcher.instance.views.first;
    _view = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        physicalConstraints: BoxConstraints.tight(size * pixelRatio),
        devicePixelRatio: pixelRatio,
      ),
      child: _boundary,
    );
    _pipeline.rootNode = _view;
    _view.prepareInitialFrame();
    _zone = Zone.current.fork(zoneValues: {_zoneKey: this});
  }

  static final _zoneKey = Object();
  static final _owners = <int, OffscreenWidgetTree>{};
  static var _lastId = 0;

  static OffscreenWidgetTree? get _current =>
      Zone.current[_zoneKey] as OffscreenWidgetTree?;

  final double pixelRatio;
  final Widget _child;
  final int _frameRate;
  final _boundary = RenderRepaintBoundary();
  final _pipeline = PipelineOwner();
  final _builds = BuildOwner(focusManager: FocusManager());
  final _removed = <int>{};
  final _postFrame = <FrameCallback>[];
  late final RenderView _view;
  late final Zone _zone;
  var _callbacks = <int, FrameCallback>{};
  RenderObjectToWidgetElement<RenderBox>? _root;
  var _frames = 0;
  var _time = Duration.zero;
  var _phase = SchedulerPhase.idle;
  var _stopped = false;

  Future<void> advance() => _zone.run(() async {
    if (_stopped) return;
    try {
      _time = Duration(
        microseconds: (++_frames * Duration.microsecondsPerSecond / _frameRate)
            .round(),
      );
      _phase = SchedulerPhase.transientCallbacks;
      _runFrameCallbacks();
      _phase = SchedulerPhase.midFrameMicrotasks;
      await Future<void>.delayed(Duration.zero);
      if (_stopped) return;
      _phase = SchedulerPhase.persistentCallbacks;
      _draw();
      _phase = SchedulerPhase.postFrameCallbacks;
      _runPostFrameCallbacks();
    } finally {
      _phase = SchedulerPhase.idle;
    }
  });

  Future<ui.Image> capture() => _boundary.toImage(pixelRatio: pixelRatio);

  void stop() => _stopped = true;

  void dispose() {
    _zone.run(() {
      final root = _root;
      if (root == null) return;
      _phase = SchedulerPhase.persistentCallbacks;
      try {
        RenderObjectToWidgetAdapter<RenderBox>(
          container: _boundary,
        ).attachToRenderTree(_builds, root);
        _builds
          ..buildScope(root)
          ..finalizeTree();
      } finally {
        _phase = SchedulerPhase.idle;
      }
    });
    _callbacks.keys.forEach(_owners.remove);
    _callbacks.clear();
    _postFrame.clear();
    _pipeline.rootNode = null;
    _view.dispose();
    _boundary.dispose();
    _pipeline.dispose();
    _builds.focusManager.dispose();
  }

  int _schedule(FrameCallback callback) {
    final id = --_lastId;
    _owners[id] = this;
    _callbacks[id] = callback;
    return id;
  }

  static void _cancel(int id) {
    final tree = _owners.remove(id);
    if (tree == null) return;
    tree._callbacks.remove(id);
    tree._removed.add(id);
  }

  void _runFrameCallbacks() {
    final callbacks = _callbacks;
    _callbacks = {};
    for (final MapEntry(key: id, value: callback) in callbacks.entries) {
      if (_removed.contains(id)) continue;
      _owners.remove(id);
      _invoke(callback);
    }
    _removed.clear();
  }

  void _runPostFrameCallbacks() {
    final callbacks = List.of(_postFrame);
    _postFrame.clear();
    callbacks.forEach(_invoke);
  }

  void _invoke(FrameCallback callback) {
    try {
      callback(_time);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: "offscreen widget tree",
          context: ErrorDescription(
            "during an offscreen widget tree frame callback",
          ),
        ),
      );
    }
  }

  void _draw() {
    final root = _root;
    if (root == null) {
      _root = RenderObjectToWidgetAdapter<RenderBox>(
        container: _boundary,
        child: _child,
      ).attachToRenderTree(_builds);
    } else {
      _builds.buildScope(root);
    }
    _pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    _builds.finalizeTree();
  }
}
