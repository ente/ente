import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:photos/ui/viewer/file/file_icons_widget.dart";

class ImageHeroSource extends InheritedWidget {
  const ImageHeroSource({
    super.key,
    required this.tag,
    required this.image,
    required super.child,
  });

  final Object tag;
  final ui.Image? image;

  Size? get size => image == null
      ? null
      : Size(image!.width.toDouble(), image!.height.toDouble());

  static ImageHeroSource? maybeOf(BuildContext context, Object? tag) {
    final source = context
        .dependOnInheritedWidgetOfExactType<ImageHeroSource>();
    return source?.tag == tag ? source : null;
  }

  @override
  bool updateShouldNotify(ImageHeroSource oldWidget) =>
      tag != oldWidget.tag || image != oldWidget.image;
}

ui.Image? imageFromHero(BuildContext context) {
  ui.Image? image;
  void visit(RenderObject renderObject) {
    if (renderObject is RenderImage && renderObject.image != null) {
      image ??= renderObject.image;
    } else if (image == null) {
      renderObject.visitChildren(visit);
    }
  }

  final renderObject = context.findRenderObject();
  if (renderObject != null) {
    visit(renderObject);
  }
  return image;
}

Widget imageHeroFlightShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) => HeroFlightImage(image: imageFromHero(fromHeroContext));

Widget imageHeroPlaceholderBuilder(
  BuildContext context,
  Size size,
  Widget child,
) => SizedBox.fromSize(
  size: size,
  child: Offstage(child: TickerMode(enabled: false, child: child)),
);

Tween<Rect?> imageHeroRectTween(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

class HeroFlightImage extends StatefulWidget {
  const HeroFlightImage({super.key, required this.image});

  final ui.Image? image;

  @override
  State<HeroFlightImage> createState() => _HeroFlightImageState();
}

class _HeroFlightImageState extends State<HeroFlightImage> {
  late final ui.Image? _image = widget.image?.clone();

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image != null
      ? RawImage(image: _image, fit: BoxFit.cover)
      : const ThumbnailPlaceHolder();
}
