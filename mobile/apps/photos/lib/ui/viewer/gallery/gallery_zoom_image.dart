import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";

class GalleryZoomImage extends SingleChildRenderObjectWidget {
  const GalleryZoomImage({
    required this.animation,
    required this.lower,
    required this.from,
    required this.to,
    required this.image,
    required super.child,
    super.key,
  });

  final Animation<double> animation;
  final int lower;
  final Rect from;
  final Rect to;
  final ui.Image? image;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderGalleryZoomImage(animation, lower, from, to, image);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGalleryZoomImage renderObject,
  ) {
    renderObject
      ..lower = lower
      ..from = from
      ..to = to
      ..image = image
      ..markNeedsPaint();
  }
}

class RenderGalleryZoomImage extends RenderProxyBox {
  RenderGalleryZoomImage(
    this.animation,
    this.lower,
    this.from,
    this.to,
    this.image,
  );

  final Animation<double> animation;
  int lower;
  Rect from;
  Rect to;
  ui.Image? image;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    animation.addListener(_onProgress);
  }

  @override
  void detach() {
    animation.removeListener(_onProgress);
    super.detach();
  }

  void _onProgress() {
    if ((from.width / from.height - to.width / to.height).abs() >
        precisionErrorTolerance) {
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var thumbnail = image;
    if (thumbnail == null) {
      void visit(RenderObject object) {
        if (object is RenderImage && object.image != null) {
          thumbnail ??= object.image;
        } else if (thumbnail == null) {
          object.visitChildren(visit);
        }
      }

      child?.visitChildren(visit);
      if (child is RenderImage) visit(child!);
    }
    if (thumbnail == null) {
      super.paint(context, offset);
      return;
    }
    final rect = Rect.lerp(
      from,
      to,
      (animation.value - lower).clamp(0.0, 1.0),
    )!;
    final imageSize = Size(
      thumbnail!.width.toDouble(),
      thumbnail!.height.toDouble(),
    );
    final fit = applyBoxFit(BoxFit.cover, imageSize, rect.size);
    final source = Alignment.center.inscribe(
      fit.source,
      Offset.zero & imageSize,
    );
    context.canvas.drawImageRect(
      thumbnail!,
      source,
      offset & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }
}
