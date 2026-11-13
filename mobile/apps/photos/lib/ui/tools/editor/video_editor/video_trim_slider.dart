import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path/path.dart' as path;
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';

class VideoTrimSlider extends StatefulWidget {
  const VideoTrimSlider({
    super.key,
    required this.controller,
    this.height = 60,
    this.horizontalMargin = 15,
  });

  final VideoEditorController controller;
  final double height;
  final double horizontalMargin;

  @override
  State<VideoTrimSlider> createState() => _VideoTrimSliderState();
}

enum _TrimDrag { start, end, seek }

class _VideoTrimSliderState extends State<VideoTrimSlider> {
  static const _handleHitRadius = 28.0;

  Directory? _directory;
  List<File> _frames = const [];
  String? _requestId;
  int _requestedFrameCount = 0;
  _TrimDrag? _drag;
  bool _resumeAfterDrag = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = math.max(
            1.0,
            constraints.maxWidth - widget.horizontalMargin * 2,
          );
          _ensureFrames(trackWidth);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.horizontalMargin),
            child: AnimatedBuilder(
              animation: Listenable.merge([
                widget.controller,
                widget.controller.video,
              ]),
              builder: (_, _) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    _seek(details.localPosition.dx, trackWidth),
                onHorizontalDragStart: (details) =>
                    _startDrag(details.localPosition.dx, trackWidth),
                onHorizontalDragUpdate: (details) =>
                    _updateDrag(details.localPosition.dx, trackWidth),
                onHorizontalDragEnd: (_) => _finishDrag(),
                onHorizontalDragCancel: _finishDrag,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildFrames(),
                      ..._buildSelection(trackWidth, context),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFrames() {
    if (_frames.isEmpty) {
      return const ColoredBox(color: Color(0xFF292929));
    }
    return Row(
      children: [
        for (final frame in _frames)
          Expanded(
            child: Image.file(
              frame,
              fit: BoxFit.cover,
              height: widget.height,
              gaplessPlayback: true,
            ),
          ),
      ],
    );
  }

  List<Widget> _buildSelection(double width, BuildContext context) {
    final durationMs = widget.controller.videoDuration.inMilliseconds;
    if (durationMs <= 0) return const [];
    final start =
        widget.controller.startTrim.inMilliseconds / durationMs * width;
    final end = widget.controller.endTrim.inMilliseconds / durationMs * width;
    final position =
        widget.controller.videoPosition.inMilliseconds.clamp(0, durationMs) /
        durationMs *
        width;
    final accent = Theme.of(context).colorScheme.primary;
    return [
      Positioned(
        left: 0,
        width: start,
        top: 0,
        bottom: 0,
        child: const ColoredBox(color: Colors.black54),
      ),
      Positioned(
        left: end,
        right: 0,
        top: 0,
        bottom: 0,
        child: const ColoredBox(color: Colors.black54),
      ),
      Positioned(
        left: start,
        width: math.max(0, end - start),
        top: 0,
        bottom: 0,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: accent, width: 3),
              ),
            ),
          ),
        ),
      ),
      _handle(start - 7, accent),
      _handle(end - 7, accent),
      Positioned(
        left: (position - 1).clamp(0, width - 2),
        width: 2,
        top: 4,
        bottom: 4,
        child: const ColoredBox(color: Colors.white),
      ),
    ];
  }

  Widget _handle(double left, Color color) => Positioned(
    left: left,
    width: 14,
    top: 0,
    bottom: 0,
    child: ColoredBox(
      color: color,
      child: const Icon(Icons.drag_handle, size: 12, color: Colors.white),
    ),
  );

  void _startDrag(double x, double width) {
    _resumeAfterDrag = widget.controller.isPlaying;
    if (_resumeAfterDrag) {
      unawaited(widget.controller.video.pause());
    }
    final start = _durationToPixels(widget.controller.startTrim, width);
    final end = _durationToPixels(widget.controller.endTrim, width);
    final startDistance = (x - start).abs();
    final endDistance = (x - end).abs();
    if (startDistance <= _handleHitRadius || endDistance <= _handleHitRadius) {
      _drag = startDistance <= endDistance ? _TrimDrag.start : _TrimDrag.end;
    } else {
      _drag = _TrimDrag.seek;
      _seek(x, width);
    }
  }

  void _finishDrag() {
    _drag = null;
    if (_resumeAfterDrag) {
      _resumeAfterDrag = false;
      unawaited(widget.controller.video.play());
    }
  }

  void _updateDrag(double x, double width) {
    final value = _pixelsToDuration(x, width);
    switch (_drag) {
      case _TrimDrag.start:
        final latest =
            widget.controller.endTrim - widget.controller.minDuration;
        widget.controller.updateTrim(
          value > latest ? latest : value,
          widget.controller.endTrim,
        );
      case _TrimDrag.end:
        final earliest =
            widget.controller.startTrim + widget.controller.minDuration;
        widget.controller.updateTrim(
          widget.controller.startTrim,
          value < earliest ? earliest : value,
        );
      case _TrimDrag.seek:
        _seek(x, width);
      case null:
        break;
    }
  }

  void _seek(double x, double width) {
    var position = _pixelsToDuration(x, width);
    if (position < widget.controller.startTrim) {
      position = widget.controller.startTrim;
    } else if (position > widget.controller.endTrim) {
      position = widget.controller.endTrim;
    }
    unawaited(widget.controller.video.seekTo(position));
  }

  double _durationToPixels(Duration duration, double width) =>
      duration.inMicroseconds /
      widget.controller.videoDuration.inMicroseconds *
      width;

  Duration _pixelsToDuration(double pixels, double width) {
    final fraction = (pixels / width).clamp(0.0, 1.0);
    return Duration(
      microseconds: (widget.controller.videoDuration.inMicroseconds * fraction)
          .round(),
    );
  }

  void _ensureFrames(double width) {
    final count = (width / 72).ceil().clamp(4, 12);
    if (_requestedFrameCount == count) return;
    _requestedFrameCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_extractFrames(count));
    });
  }

  Future<void> _extractFrames(int count) async {
    final requestId =
        'timeline-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    final oldRequest = _requestId;
    _requestId = requestId;
    if (oldRequest != null) {
      await NativeVideoEditor.cancelFrameExtraction(oldRequest);
    }
    if (!mounted || _requestId != requestId) return;

    final directory = await Directory.systemTemp.createTemp(
      'ente-video-timeline-',
    );
    if (!mounted || _requestId != requestId) {
      await directory.delete(recursive: true);
      return;
    }
    final oldDirectory = _directory;
    _directory = directory;
    if (_frames.isNotEmpty) {
      setState(() => _frames = const []);
    }
    unawaited(_deleteDirectory(oldDirectory));
    final durationUs = widget.controller.videoDuration.inMicroseconds;
    final positions = List<Duration>.generate(
      count,
      (index) =>
          Duration(microseconds: (durationUs * (index + 0.5) / count).round()),
    );
    final outputPaths = List<String>.generate(
      count,
      (index) => path.join(directory.path, 'tile-$index.jpg'),
    );
    try {
      final extraction = await NativeVideoEditor.extractTimeline(
        VideoTimelineRequest(
          requestId: requestId,
          inputPath: widget.controller.file.path,
          outputPaths: outputPaths,
          positions: positions,
          maxWidth: 144,
          maxHeight: 120,
          quality: 72,
          policy: VideoFramePolicy.precise,
        ),
      );
      if (!mounted || _requestId != requestId) return;
      setState(() {
        _frames = extraction.frames
            .map((frame) => File(frame.outputPath))
            .toList(growable: false);
      });
    } on NativeVideoEditorException catch (error) {
      if (error.code != 'FRAME_CANCELLED' &&
          mounted &&
          _requestId == requestId) {
        setState(() => _frames = const []);
      }
    }
  }

  @override
  void dispose() {
    final requestId = _requestId;
    final directory = _directory;
    _requestId = null;
    _directory = null;
    unawaited(_cancelAndDelete(requestId, directory));
    super.dispose();
  }

  Future<void> _cancelAndDelete(String? requestId, Directory? directory) async {
    try {
      if (requestId != null) {
        await NativeVideoEditor.cancelFrameExtraction(requestId);
      }
    } on NativeVideoEditorException {
      // The widget is already disposed; only local cleanup remains actionable.
    } finally {
      await _deleteDirectory(directory);
    }
  }

  Future<void> _deleteDirectory(Directory? directory) async {
    if (directory != null && await directory.exists()) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Temporary timeline files are best-effort cleanup.
      }
    }
  }
}
