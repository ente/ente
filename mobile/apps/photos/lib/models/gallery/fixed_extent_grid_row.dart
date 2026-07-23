import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// Based on code from https://github.com/deckerst/aves
// Copyright (c) 2020-2023 Thibault Deckers and contributors
// Licensed under BSD-3-Clause License

class FixedExtentGridRow extends MultiChildRenderObjectWidget {
  final double width, height, spacing;
  final TextDirection textDirection;

  const FixedExtentGridRow({
    super.key,
    required this.width,
    required this.height,
    required this.spacing,
    required this.textDirection,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFixedExtentGridRow(
      width: width,
      height: height,
      spacing: spacing,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFixedExtentGridRow renderObject,
  ) {
    renderObject.width = width;
    renderObject.height = height;
    renderObject.spacing = spacing;
    renderObject.textDirection = textDirection;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('width', width));
    properties.add(DoubleProperty('height', height));
    properties.add(DoubleProperty('spacing', spacing));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection));
  }
}

class _GridRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFixedExtentGridRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridRowParentData> {
  RenderFixedExtentGridRow({
    List<RenderBox>? children,
    required double width,
    required double height,
    required double spacing,
    required TextDirection textDirection,
  }) : _width = width,
       _height = height,
       _spacing = spacing,
       _textDirection = textDirection {
    addAll(children);
  }

  double get width => _width;
  double _width;

  set width(double value) {
    if (_width == value) return;
    _width = value;
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
    if (child.parentData is! _GridRowParentData) {
      child.parentData = _GridRowParentData();
    }
  }

  double get intrinsicWidth => width * childCount + spacing * (childCount - 1);

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
    var child = firstChild;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    size = Size(constraints.maxWidth, height);
    final childConstraints = BoxConstraints.tight(Size(width, height));
    final flipMainAxis = textDirection == TextDirection.rtl;
    var offset = Offset(flipMainAxis ? size.width - width : 0, 0);
    final dx = (flipMainAxis ? -1 : 1) * (width + spacing);
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: false);
      final childParentData = child.parentData! as _GridRowParentData;
      childParentData.offset = offset;
      offset += Offset(dx, 0);
      child = childParentData.nextSibling;
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('width', width));
    properties.add(DoubleProperty('height', height));
    properties.add(DoubleProperty('spacing', spacing));
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection));
  }
}
