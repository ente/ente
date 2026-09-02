import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";

class JustifiedGridRow extends MultiChildRenderObjectWidget {
  final List<double> itemWidths;
  final double height;
  final double spacing;
  final TextDirection textDirection;

  const JustifiedGridRow({
    super.key,
    required this.itemWidths,
    required this.height,
    required this.spacing,
    required this.textDirection,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderJustifiedGridRow(
      itemWidths: itemWidths,
      height: height,
      spacing: spacing,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderJustifiedGridRow renderObject,
  ) {
    renderObject
      ..itemWidths = itemWidths
      ..height = height
      ..spacing = spacing
      ..textDirection = textDirection;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<double>("itemWidths", itemWidths));
    properties.add(DoubleProperty("height", height));
    properties.add(DoubleProperty("spacing", spacing));
    properties.add(EnumProperty<TextDirection>("textDirection", textDirection));
  }
}

class _JustifiedGridRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderJustifiedGridRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _JustifiedGridRowParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _JustifiedGridRowParentData
        > {
  RenderJustifiedGridRow({
    List<RenderBox>? children,
    required List<double> itemWidths,
    required double height,
    required double spacing,
    required TextDirection textDirection,
  }) : _itemWidths = itemWidths,
       _height = height,
       _spacing = spacing,
       _textDirection = textDirection {
    addAll(children);
  }

  List<double> get itemWidths => _itemWidths;
  List<double> _itemWidths;

  set itemWidths(List<double> value) {
    if (listEquals(_itemWidths, value)) return;
    _itemWidths = value;
    markNeedsLayout();
  }

  double get height => _height;
  double _height;

  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  double get spacing => _spacing;
  double _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _JustifiedGridRowParentData) {
      child.parentData = _JustifiedGridRowParentData();
    }
  }

  double get intrinsicWidth =>
      itemWidths.fold<double>(0, (sum, width) => sum + width) +
      spacing * (childCount > 0 ? childCount - 1 : 0);

  @override
  double computeMinIntrinsicWidth(double height) => intrinsicWidth;

  @override
  double computeMaxIntrinsicWidth(double height) => intrinsicWidth;

  @override
  double computeMinIntrinsicHeight(double width) => height;

  @override
  double computeMaxIntrinsicHeight(double width) => height;

  @override
  void performLayout() {
    assert(
      childCount == itemWidths.length,
      "Each justified child must have one precomputed width",
    );
    final rowWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : intrinsicWidth;
    size = constraints.constrain(Size(rowWidth, height));

    var child = firstChild;
    final flipMainAxis = textDirection == TextDirection.rtl;
    var offsetX = flipMainAxis ? size.width : 0.0;
    var index = 0;
    while (child != null) {
      final childWidth = index < itemWidths.length ? itemWidths[index] : 0.0;
      child.layout(
        BoxConstraints.tight(Size(childWidth, size.height)),
        parentUsesSize: false,
      );
      final childParentData = child.parentData! as _JustifiedGridRowParentData;
      if (flipMainAxis) offsetX -= childWidth;
      childParentData.offset = Offset(offsetX, 0);
      offsetX += flipMainAxis ? -(spacing) : childWidth + spacing;
      child = childParentData.nextSibling;
      index++;
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToHighestActualBaseline(baseline);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}
