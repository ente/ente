import "dart:async";
import "dart:math";
import "dart:ui" show ImageFilter, lerpDouble;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";

typedef RewindPhotoPlacement = ({Offset center, Size size, double angle});

RewindPhotoPlacement? rewindPhotoPlacement(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final transform = box.getTransformTo(null);
  final m = transform.storage;
  final size = box.size;
  return (
    center: MatrixUtils.transformPoint(transform, size.center(Offset.zero)),
    size: Size(
      size.width * sqrt(m[0] * m[0] + m[1] * m[1]),
      size.height * sqrt(m[4] * m[4] + m[5] * m[5]),
    ),
    angle: atan2(m[1], m[0]),
  );
}

Future<void> showRewindPhotoZoom(
  BuildContext context, {
  required EnteFile file,
  required RewindPhotoPlacement? Function() placement,
  required VoidCallback onLifted,
  required VoidCallback onReturned,
  required Widget placeholder,
  Alignment focus = Alignment.center,
}) async {
  final cached = ThumbnailInMemoryLruCache.get(file, thumbnailLargeSize);
  final ImageProvider? thumbnail = cached == null ? null : MemoryImage(cached);
  final aspect = await _aspectOf(thumbnail);
  final from = context.mounted ? placement() : null;
  if (!context.mounted || from == null) return;
  onLifted();
  unawaited(HapticFeedback.lightImpact());
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => _RewindPhotoZoom(
        file: file,
        thumbnail: thumbnail,
        aspect:
            aspect ??
            (file.width > 0 && file.height > 0
                ? file.width / file.height
                : from.size.width / from.size.height),
        from: from,
        returnTo: placement,
        onReturned: onReturned,
        placeholder: placeholder,
        focus: focus,
      ),
    ),
  );
}

Future<double?> _aspectOf(ImageProvider? provider) {
  if (provider == null) return Future.value();
  final completer = Completer<double?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(info.image.width / info.image.height);
      }
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!completer.isCompleted) completer.complete();
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(
    const Duration(milliseconds: 400),
    onTimeout: () {
      stream.removeListener(listener);
      return null;
    },
  );
}

class _RewindPhotoZoom extends StatefulWidget {
  const _RewindPhotoZoom({
    required this.file,
    required this.thumbnail,
    required this.aspect,
    required this.from,
    required this.returnTo,
    required this.onReturned,
    required this.placeholder,
    required this.focus,
  });

  final EnteFile file;
  final ImageProvider? thumbnail;
  final double aspect;
  final RewindPhotoPlacement from;
  final RewindPhotoPlacement? Function() returnTo;
  final VoidCallback onReturned;
  final Widget placeholder;
  final Alignment focus;

  @override
  State<_RewindPhotoZoom> createState() => _RewindPhotoZoomState();
}

class _RewindPhotoZoomState extends State<_RewindPhotoZoom>
    with TickerProviderStateMixin {
  static const _margin = 18.0;
  static const _paper = 7.0;
  static const _dismissDistance = 110.0;
  static const _dismissVelocity = 800.0;
  static const _grow = Cubic(0.2, 0.9, 0.28, 1.08);
  static const _move = Curves.easeOutCubic;

  late final _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    reverseDuration: const Duration(milliseconds: 420),
  );
  late final _drag = AnimationController.unbounded(vsync: this);
  late RewindPhotoPlacement _from = widget.from;
  var _landed = false;
  var _closing = false;
  var _zoomed = false;

  @override
  void initState() {
    super.initState();
    _flight.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_closing && !_landed) {
        setState(() => _landed = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_flight.isDismissed) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _landed = true;
      _flight.value = 1;
    } else {
      unawaited(_flight.forward());
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    _drag.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    setState(() {
      _from = widget.returnTo() ?? widget.from;
      _landed = false;
    });
    if (!MediaQuery.disableAnimationsOf(context)) await _flight.reverse();
    widget.onReturned();
    if (mounted) Navigator.of(context).pop();
  }

  void _dragged(DragUpdateDetails details) {
    if (_closing) return;
    _drag.value += details.primaryDelta ?? 0;
  }

  void _released(DragEndDetails details) {
    if (_closing) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_drag.value.abs() > _dismissDistance ||
        velocity.abs() > _dismissVelocity) {
      unawaited(_close());
    } else {
      unawaited(
        _drag.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
        ),
      );
    }
  }

  Size _landingSize(Size screen, EdgeInsets padding) {
    final room = Size(
      screen.width - 2 * (_margin + _paper),
      screen.height - padding.vertical - 4 * _margin - 2 * _paper,
    );
    return applyBoxFit(
      BoxFit.contain,
      Size(widget.aspect, 1),
      room,
    ).destination;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final landing = _landingSize(screen, padding);
    final landingCenter = Offset(
      screen.width / 2,
      padding.top + (screen.height - padding.vertical) / 2,
    );
    final canDrag = _landed && !_zoomed;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          onVerticalDragUpdate: canDrag ? _dragged : null,
          onVerticalDragEnd: canDrag ? _released : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_flight, _drag]),
            builder: (context, _) {
              final raw = _flight.value;
              final grow = _grow.transform(raw);
              final move = _move.transform(raw);
              final lift = (_drag.value.abs() / 320).clamp(0.0, 1.0);
              final shrink = lerpDouble(1, 1 - 0.18 * lift, raw)!;
              final size = Size.lerp(_from.size, landing, grow)! * shrink;
              final center = Offset.lerp(
                _from.center,
                landingCenter + Offset(0, _drag.value),
                move,
              )!;
              final wobble = -3 * sin(pi * raw) * pi / 180;
              final angle = lerpDouble(_from.angle, 0, move)! + wobble;
              final paper = _paper * raw;
              final shade = raw * (1 - 0.6 * lift);
              return Stack(
                fit: StackFit.expand,
                children: [
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 14 * shade,
                      sigmaY: 14 * shade,
                    ),
                    child: ColoredBox(
                      color: Color.fromRGBO(12, 10, 8, 0.74 * shade),
                    ),
                  ),
                  Positioned(
                    left: center.dx - size.width / 2 - paper,
                    top: center.dy - size.height / 2 - paper,
                    width: size.width + 2 * paper,
                    height: size.height + 2 * paper,
                    child: Transform.rotate(
                      angle: angle,
                      child: _print(paper, raw),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _print(double paper, double raw) {
    final radius = lerpDouble(2, 14, raw)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RewindColors.photoPaper,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.4 * raw),
            blurRadius: 30 * raw,
            offset: Offset(0, 16 * raw),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(paper),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(max(0, radius - paper)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _thumbnail(raw),
              if (_landed && widget.file.fileType != FileType.video)
                ZoomableImage(
                  widget.file,
                  tagPrefix: "rewind_zoom_",
                  backgroundDecoration: const BoxDecoration(),
                  isFromMemories: true,
                  enableVerticalSwipeActions: false,
                  shouldDisableScroll: (locked) {
                    if (mounted && locked != _zoomed) {
                      setState(() => _zoomed = locked);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(double raw) {
    final thumbnail = widget.thumbnail;
    if (thumbnail == null) return widget.placeholder;
    return Image(
      image: thumbnail,
      fit: BoxFit.cover,
      alignment: Alignment.lerp(widget.focus, Alignment.center, raw)!,
      gaplessPlayback: true,
    );
  }
}
