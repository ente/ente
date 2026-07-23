import "package:ente_components/ente_components.dart";
import "package:flutter/widgets.dart";

typedef GalleryAppBarGeometryBuilder =
    HeaderAppBarGeometry Function(BuildContext context);

class GalleryAppBarConfig {
  const GalleryAppBarConfig({
    required this.sliverBuilder,
    required this.geometryBuilder,
  });

  final WidgetBuilder sliverBuilder;
  final GalleryAppBarGeometryBuilder geometryBuilder;

  HeaderAppBarGeometry resolveGeometry(BuildContext context) {
    final geometry = geometryBuilder(context);
    assert(geometry.maxExtent >= geometry.minExtent);
    return geometry;
  }

  Widget buildSliver(BuildContext context) => sliverBuilder(context);
}
