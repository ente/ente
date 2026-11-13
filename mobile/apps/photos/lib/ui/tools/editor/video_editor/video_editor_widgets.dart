import 'dart:math' as math;

import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_app_bar.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_player_control.dart';
import 'package:video_player/video_player.dart';

class VideoEditorSubPage extends StatefulWidget {
  const VideoEditorSubPage({
    super.key,
    required this.controller,
    required this.preview,
    required this.actions,
  });

  final VideoEditorController controller;
  final Widget preview;
  final Widget actions;

  @override
  State<VideoEditorSubPage> createState() => _VideoEditorSubPageState();
}

class _VideoEditorSubPageState extends State<VideoEditorSubPage> {
  late final VideoEditorState _initialState;
  bool _keepChanges = false;

  @override
  void initState() {
    super.initState();
    _initialState = widget.controller.snapshot();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_keepChanges) {
          widget.controller.restore(_initialState);
        }
      },
      child: Scaffold(
        backgroundColor: getEnteColorScheme(context).backgroundColour,
        appBar: VideoEditorAppBar(
          onCancel: () => Navigator.pop(context),
          primaryActionLabel: context.strings.done,
          onPrimaryAction: () {
            _keepChanges = true;
            Navigator.pop(context);
          },
        ),
        body: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Hero(
                          tag: 'video-editor-preview',
                          child: widget.preview,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: VideoEditorPlayerControl(
                            controller: widget.controller,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                widget.actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VideoEditorPreview extends StatelessWidget {
  const VideoEditorPreview({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) {
          final sourceSize = controller.sourceDisplaySize;
          final crop = controller.normalizedCropRect;
          final cropWidth = sourceSize.width * crop.width;
          final cropHeight = sourceSize.height * crop.height;
          return Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: RotatedBox(
                quarterTurns: controller.rotation ~/ 90,
                child: SizedBox(
                  width: cropWidth,
                  height: cropHeight,
                  child: ClipRect(
                    child: Transform.translate(
                      offset: Offset(
                        -crop.left * sourceSize.width,
                        -crop.top * sourceSize.height,
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: sourceSize.width,
                        maxWidth: sourceSize.width,
                        minHeight: sourceSize.height,
                        maxHeight: sourceSize.height,
                        child: SizedBox.fromSize(
                          size: sourceSize,
                          child: VideoPlayer(controller.video),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class VideoCropEditor extends StatefulWidget {
  const VideoCropEditor({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  State<VideoCropEditor> createState() => _VideoCropEditorState();
}

enum _CropDrag {
  move,
  left,
  top,
  right,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _VideoCropEditorState extends State<VideoCropEditor> {
  _CropDrag? _drag;
  Rect? _startRect;
  Offset? _startPosition;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (_, _) {
              final source = widget.controller.sourceDisplaySize;
              final rotated =
                  widget.controller.rotation == 90 ||
                      widget.controller.rotation == 270
                  ? Size(source.height, source.width)
                  : source;
              final mediaRect = _containedRect(constraints.biggest, rotated);
              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: mediaRect,
                    child: RotatedBox(
                      quarterTurns: widget.controller.rotation ~/ 90,
                      child: VideoPlayer(widget.controller.video),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: mediaRect,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) =>
                          _startDrag(details.localPosition, mediaRect.size),
                      onPanUpdate: (details) =>
                          _updateDrag(details.localPosition, mediaRect.size),
                      onPanEnd: (_) => _endDrag(),
                      onPanCancel: _endDrag,
                      child: CustomPaint(
                        painter: _CropOverlayPainter(
                          widget.controller.visualNormalizedCropRect,
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _startDrag(Offset position, Size size) {
    final rect = widget.controller.visualNormalizedCropRect;
    _drag = _hitTest(position, size, rect);
    _startRect = rect;
    _startPosition = Offset(
      position.dx / size.width,
      position.dy / size.height,
    );
  }

  void _updateDrag(Offset position, Size size) {
    final drag = _drag;
    final startRect = _startRect;
    final startPosition = _startPosition;
    if (drag == null || startRect == null || startPosition == null) return;
    final current = Offset(position.dx / size.width, position.dy / size.height);
    final delta = current - startPosition;
    final minimumWidth = math.max(44 / size.width, 0.05);
    final minimumHeight = math.max(44 / size.height, 0.05);
    Rect next;

    if (drag == _CropDrag.move) {
      final dx = delta.dx.clamp(-startRect.left, 1 - startRect.right);
      final dy = delta.dy.clamp(-startRect.top, 1 - startRect.bottom);
      next = startRect.shift(Offset(dx, dy));
    } else {
      var left = startRect.left;
      var top = startRect.top;
      var right = startRect.right;
      var bottom = startRect.bottom;
      if (_movesLeft(drag)) {
        left = (startRect.left + delta.dx).clamp(0.0, right - minimumWidth);
      }
      if (_movesRight(drag)) {
        right = (startRect.right + delta.dx).clamp(left + minimumWidth, 1.0);
      }
      if (_movesTop(drag)) {
        top = (startRect.top + delta.dy).clamp(0.0, bottom - minimumHeight);
      }
      if (_movesBottom(drag)) {
        bottom = (startRect.bottom + delta.dy).clamp(top + minimumHeight, 1.0);
      }
      next = Rect.fromLTRB(left, top, right, bottom);
      final ratio = widget.controller.preferredCropAspectRatio;
      if (ratio != null) {
        next = _constrainRatio(
          next,
          drag,
          ratio,
          size,
          minimumWidth,
          minimumHeight,
        );
      }
    }
    widget.controller.updateVisualCrop(next);
  }

  void _endDrag() {
    _drag = null;
    _startRect = null;
    _startPosition = null;
  }

  _CropDrag? _hitTest(Offset position, Size size, Rect normalized) {
    final rect = Rect.fromLTRB(
      normalized.left * size.width,
      normalized.top * size.height,
      normalized.right * size.width,
      normalized.bottom * size.height,
    );
    const threshold = 28.0;
    final left = (position.dx - rect.left).abs() <= threshold;
    final right = (position.dx - rect.right).abs() <= threshold;
    final top = (position.dy - rect.top).abs() <= threshold;
    final bottom = (position.dy - rect.bottom).abs() <= threshold;
    if (left && top) return _CropDrag.topLeft;
    if (right && top) return _CropDrag.topRight;
    if (left && bottom) return _CropDrag.bottomLeft;
    if (right && bottom) return _CropDrag.bottomRight;
    if (widget.controller.preferredCropAspectRatio == null) {
      if (left && position.dy >= rect.top && position.dy <= rect.bottom) {
        return _CropDrag.left;
      }
      if (right && position.dy >= rect.top && position.dy <= rect.bottom) {
        return _CropDrag.right;
      }
      if (top && position.dx >= rect.left && position.dx <= rect.right) {
        return _CropDrag.top;
      }
      if (bottom && position.dx >= rect.left && position.dx <= rect.right) {
        return _CropDrag.bottom;
      }
    }
    return rect.contains(position) ? _CropDrag.move : null;
  }

  Rect _constrainRatio(
    Rect rect,
    _CropDrag drag,
    double displayRatio,
    Size size,
    double minimumWidth,
    double minimumHeight,
  ) {
    final normalizedRatio = displayRatio * size.height / size.width;
    return constrainNormalizedCropRect(
      rect: rect,
      movesLeft: _movesLeft(drag),
      movesTop: _movesTop(drag),
      normalizedRatio: normalizedRatio,
      minimumWidth: minimumWidth,
      minimumHeight: minimumHeight,
    );
  }

  bool _movesLeft(_CropDrag drag) => const {
    _CropDrag.left,
    _CropDrag.topLeft,
    _CropDrag.bottomLeft,
  }.contains(drag);

  bool _movesRight(_CropDrag drag) => const {
    _CropDrag.right,
    _CropDrag.topRight,
    _CropDrag.bottomRight,
  }.contains(drag);

  bool _movesTop(_CropDrag drag) => const {
    _CropDrag.top,
    _CropDrag.topLeft,
    _CropDrag.topRight,
  }.contains(drag);

  bool _movesBottom(_CropDrag drag) => const {
    _CropDrag.bottom,
    _CropDrag.bottomLeft,
    _CropDrag.bottomRight,
  }.contains(drag);
}

@visibleForTesting
Rect constrainNormalizedCropRect({
  required Rect rect,
  required bool movesLeft,
  required bool movesTop,
  required double normalizedRatio,
  required double minimumWidth,
  required double minimumHeight,
}) {
  if (!normalizedRatio.isFinite || normalizedRatio <= 0) {
    throw ArgumentError.value(normalizedRatio, 'normalizedRatio');
  }
  final anchorX = movesLeft ? rect.right : rect.left;
  final anchorY = movesTop ? rect.bottom : rect.top;
  final maximumWidth = movesLeft ? anchorX : 1 - anchorX;
  final maximumHeight = movesTop ? anchorY : 1 - anchorY;
  final maximumRatioWidth = math.min(
    maximumWidth,
    maximumHeight * normalizedRatio,
  );
  final minimumRatioWidth = math.min(
    maximumRatioWidth,
    math.max(minimumWidth, minimumHeight * normalizedRatio),
  );
  final widthFromHeight = rect.height * normalizedRatio;
  final preserveWidthDelta = (rect.width / normalizedRatio - rect.height).abs();
  final preserveHeightDelta = (widthFromHeight - rect.width).abs();
  final desiredWidth = preserveWidthDelta <= preserveHeightDelta
      ? rect.width
      : widthFromHeight;
  final width = desiredWidth.clamp(minimumRatioWidth, maximumRatioWidth);
  final height = width / normalizedRatio;
  return Rect.fromLTWH(
    movesLeft ? anchorX - width : anchorX,
    movesTop ? anchorY - height : anchorY,
    width,
    height,
  );
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.normalizedRect, this.accentColor);

  final Rect normalizedRect;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final crop = Rect.fromLTRB(
      normalizedRect.left * size.width,
      normalizedRect.top * size.height,
      normalizedRect.right * size.width,
      normalizedRect.bottom * size.height,
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(crop);
    canvas.drawPath(shade, Paint()..color = Colors.black54);
    canvas.drawRect(
      crop,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final grid = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (var index = 1; index < 3; index++) {
      final x = crop.left + crop.width * index / 3;
      final y = crop.top + crop.height * index / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }
    final handle = Paint()..color = Colors.white;
    for (final point in [
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      canvas.drawCircle(point, 5, handle);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.normalizedRect != normalizedRect ||
      oldDelegate.accentColor != accentColor;
}

Rect _containedRect(Size available, Size content) {
  final fitted = applyBoxFit(BoxFit.contain, content, available).destination;
  return Alignment.center.inscribe(fitted, Offset.zero & available);
}
