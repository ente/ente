import "dart:math";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_text_bar.dart";
import "package:pro_image_editor/features/main_editor/services/layer_copy_manager.dart";
import "package:pro_image_editor/pro_image_editor.dart";

const _layerPadding = 24.0;
const _frameGap = 6.0;
const _handleRadius = 5.0;
const _handleTapSize = 32.0;
const _actionSize = 44.0;
const _textEditorWidthInset = 34.0;

LayerInteractionConfigs imageEditorLayerInteractionConfigs(
  BuildContext context,
  ValueGetter<ProImageEditorState?> editor,
) {
  final colors = context.componentColors;
  final strings = context.strings;
  return LayerInteractionConfigs(
    selectable: LayerInteractionSelectable.enabled,
    initialSelected: true,
    hideToolbarOnInteraction: false,
    enableKeyboardMultiSelection: false,
    enableLongPressMultiSelection: false,
    enableLayerDragSelection: false,
    style: const LayerInteractionStyle(
      overlayPadding: EdgeInsets.all(_layerPadding),
    ),
    widgets: LayerInteractionWidgets(
      overlayChildBuilder: (rebuildStream, info, layer, interactions) =>
          ReactiveWidget(
            stream: rebuildStream,
            builder: (_) => _LayerSelection(
              info: info,
              colors: colors,
              onScaleRotateDown: interactions.scaleRotateDown,
              onScaleRotateUp: interactions.scaleRotateUp,
              actions: [
                if (layer.isTextLayer ||
                    (layer is PaintLayer && !layer.item.isCensorArea))
                  _LayerAction(
                    label: strings.edit,
                    icon: HugeIcons.strokeRoundedPencilEdit02,
                    color: colors.iconColor,
                    onTap: () {
                      final state = editor();
                      if (state != null &&
                          !state.isSubEditorOpen &&
                          layer.isTextLayer) {
                        _editTextLayer(state, layer as TextLayer);
                      } else if (layer.isPaintLayer) {
                        interactions.edit();
                      }
                    },
                  ),
                _LayerAction(
                  label: strings.imageEditorDuplicate,
                  icon: HugeIcons.strokeRoundedCopy01,
                  color: colors.iconColor,
                  onTap: interactions.duplicated,
                ),
                _LayerAction(
                  label: strings.delete,
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: colors.warning,
                  onTap: () {
                    interactions.remove();
                    editor()?.layerInteractionManager.clearSelectedLayers();
                  },
                ),
              ],
            ),
          ),
    ),
  );
}

class ImageEditorLayerDoubleTap {
  ImageEditorLayerDoubleTap(this.editor, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final ValueGetter<ProImageEditorState?> editor;
  final DateTime Function() now;
  final Map<int, Offset> _pointers = {};
  String? _downLayerId;
  Offset? _downOffset;
  double? _downScale;
  double? _downRotation;
  String? _upLayerId;
  bool _moved = false;
  bool _multiTouch = false;
  String? _lastLayerId;
  DateTime? _lastTap;

  void onLayerDown(Layer layer) {
    _downLayerId = layer.id;
    _downOffset = layer.offset;
    _downScale = layer.scale;
    _downRotation = layer.rotation;
    _moved = false;
  }

  void onLayerUp(Layer layer) => _upLayerId = layer.id;

  void onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length > 1) {
      _multiTouch = true;
      _lastLayerId = null;
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    final start = _pointers[event.pointer];
    if (start != null && (event.position - start).distance > kTouchSlop) {
      _moved = true;
      _lastLayerId = null;
    }
  }

  void onPointerUp(PointerUpEvent event) {
    final layerId = _upLayerId;
    final state = editor();
    final layer = state?.activeLayers
        .whereType<TextLayer>()
        .where((layer) => layer.id == layerId)
        .firstOrNull;
    final start = _pointers.remove(event.pointer);
    final isTap =
        start != null &&
        (event.position - start).distance <= kTouchSlop &&
        !_moved &&
        !_multiTouch &&
        _pointers.isEmpty &&
        layer != null &&
        layer.id == _downLayerId &&
        layer.offset == _downOffset &&
        layer.scale == _downScale &&
        layer.rotation == _downRotation &&
        state != null &&
        !state.isSubEditorOpen;
    _upLayerId = null;
    if (_pointers.isEmpty) {
      _downLayerId = null;
      _multiTouch = false;
      _moved = false;
    }
    if (!isTap) {
      _lastLayerId = null;
      return;
    }
    final tapTime = now();
    if (_lastLayerId == layerId &&
        _lastTap != null &&
        tapTime.difference(_lastTap!) < kDoubleTapTimeout) {
      _lastLayerId = null;
      _editTextLayer(state, layer);
    } else {
      _lastLayerId = layerId;
      _lastTap = tapTime;
    }
  }

  void onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _upLayerId = null;
    _lastLayerId = null;
    if (_pointers.isEmpty) _multiTouch = false;
  }
}

Future<TextLayer?> imageEditorCreateTextLayer(
  ValueGetter<ProImageEditorState?> editor,
) async {
  final state = editor();
  if (state == null || state.isSubEditorOpen) return null;
  final id = UniqueKey().toString();
  final layer = await state.openPage<TextLayer>(
    ImageEditorTextPage(
      key: state.textEditor,
      heroTag: id,
      configs: state.configs,
      theme: state.configs.theme ?? Theme.of(state.context),
      callbacks: state.callbacks,
      imageSize: state.sizesManager.decodedImageSize,
    ),
    duration: const Duration(milliseconds: 150),
  );
  if (layer == null) return null;
  layer.id = id;
  _selectLayerAfterClose(state, id);
  return layer;
}

void _selectLayerAfterClose(ProImageEditorState state, String id) {
  void selectWhenReady(Duration _) {
    if (!state.mounted) return;
    if (state.isSubEditorOpen) {
      WidgetsBinding.instance.addPostFrameCallback(selectWhenReady);
      return;
    }
    if (!state.activeLayers.any((active) => active.id == id)) return;
    state.unselectAllLayers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.mounted) return;
      state.selectLayerById(id);
    });
  }

  WidgetsBinding.instance.addPostFrameCallback(selectWhenReady);
}

Future<void> _editTextLayer(ProImageEditorState editor, TextLayer layer) async {
  if (editor.isSubEditorOpen) return;
  final layerWidth = layer.keyInternalSize.currentContext?.size?.width;
  final wrapWidth =
      layer.maxTextWidth ??
      (layerWidth == null ? null : layerWidth / layer.scale);
  final availableWidth =
      editor.sizesManager.bodySize.width - _textEditorWidthInset;
  final displayScale = min(
    layer.scale,
    wrapWidth == null || wrapWidth <= 0
        ? layer.scale
        : availableWidth / wrapWidth,
  );
  final updated = await editor.openPage<TextLayer>(
    ImageEditorTextPage(
      key: editor.textEditor,
      layer: (LayerCopyManager().copyLayer(layer) as TextLayer)
        ..fontScale = layer.fontScale * displayScale,
      heroTag: layer.rotation == 0 ? layer.id : null,
      configs: editor.configs.copyWith(
        textEditor: editor.configs.textEditor.copyWith(
          enableImageBoundaryTextWrap: layer.maxTextWidth != null,
        ),
      ),
      theme: editor.configs.theme ?? Theme.of(editor.context),
      callbacks: editor.callbacks,
      imageSize: layer.maxTextWidth == null
          ? editor.sizesManager.decodedImageSize
          : Size(
              layer.maxTextWidth! * displayScale + _textEditorWidthInset,
              editor.sizesManager.decodedImageSize.height,
            ),
    ),
    duration: const Duration(milliseconds: 250),
  );
  if (!editor.mounted || updated == null) return;
  if (updated.text.isEmpty) {
    editor.removeLayer(layer);
    return;
  }
  final color = updated.color;
  final background = updated.background;
  // The text flies back to wherever this layer is laid out. A layer with a
  // new key is measured at its new size, but it is also painted for one frame
  // before the flight hides it, so it stays clear for that frame.
  updated
    ..id = layer.id
    ..flipX = layer.flipX
    ..flipY = layer.flipY
    ..offset = layer.offset
    ..scale = layer.scale
    ..rotation = layer.rotation
    ..boxConstraints = layer.boxConstraints
    ..fontScale = updated.fontScale / displayScale
    ..maxTextWidth = layer.maxTextWidth
    ..groupId = layer.groupId
    ..interaction = layer.interaction
    ..meta = layer.meta
    ..color = Colors.transparent
    ..background = Colors.transparent;
  editor.replaceLayer(
    index: editor.activeLayers.indexWhere((other) => other.id == layer.id),
    layer: updated,
  );
  _selectLayerAfterClose(editor, layer.id);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    updated
      ..color = color
      ..background = background;
    if (editor.mounted) editor.setState(() {});
  });
}

class _LayerSelection extends StatelessWidget {
  const _LayerSelection({
    required this.info,
    required this.colors,
    required this.onScaleRotateDown,
    required this.onScaleRotateUp,
    required this.actions,
  });

  final OverlayChildLayoutInfo info;
  final ColorTokens colors;
  final ValueChanged<PointerDownEvent> onScaleRotateDown;
  final ValueChanged<PointerUpEvent> onScaleRotateUp;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Offset point(double x, double y) =>
        MatrixUtils.transformPoint(info.childPaintTransform, Offset(x, y));
    final topLeft = point(_layerPadding, _layerPadding);
    final topRight = point(info.childSize.width - _layerPadding, _layerPadding);
    final bottomLeft = point(
      _layerPadding,
      info.childSize.height - _layerPadding,
    );
    final center = (topRight + bottomLeft) / 2;
    final angle = (topRight - topLeft).direction;
    final frame = Size(
      (topRight - topLeft).distance + _frameGap * 2,
      (bottomLeft - topLeft).distance + _frameGap * 2,
    );
    final corners = [
      for (final (dx, dy) in const [(-1, -1), (1, -1), (-1, 1), (1, 1)])
        center +
            Offset.fromDirection(angle, dx * frame.width / 2) +
            Offset.fromDirection(angle + pi / 2, dy * frame.height / 2),
    ];
    final top = corners.map((corner) => corner.dy).reduce(min);
    final bottom = corners.map((corner) => corner.dy).reduce(max);
    final actionsWidth = actions.length * _actionSize;
    final visibleTop = MediaQuery.viewPaddingOf(context).top + kToolbarHeight;
    final visibleBottom =
        info.overlaySize.height -
        editorBottomBarHeight -
        MediaQuery.viewPaddingOf(context).bottom;
    final belowFits = bottom + Spacing.md + _actionSize <= visibleBottom;
    final actionTop =
        (belowFits ? bottom + Spacing.md : top - Spacing.md - _actionSize)
            .clamp(visibleTop, max(visibleTop, visibleBottom - _actionSize))
            .toDouble();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _LayerFramePainter(
                center: center,
                angle: angle,
                size: frame,
                color: colors.specialWhite,
                outline: colors.specialScrim,
              ),
            ),
          ),
        ),
        for (final corner in corners)
          Positioned(
            left: corner.dx - _handleTapSize / 2,
            top: corner.dy - _handleTapSize / 2,
            width: _handleTapSize,
            height: _handleTapSize,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: onScaleRotateDown,
              onPointerUp: onScaleRotateUp,
              child: const IgnorePointer(child: SizedBox.expand()),
            ),
          ),
        Positioned(
          left: (center.dx - actionsWidth / 2).clamp(
            Spacing.sm,
            max(Spacing.sm, info.overlaySize.width - actionsWidth - Spacing.sm),
          ),
          top: actionTop,
          child: Container(
            height: _actionSize,
            decoration: BoxDecoration(
              color: colors.fillLight,
              borderRadius: BorderRadius.circular(_actionSize / 2),
              boxShadow: Shadows.soft,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ),
      ],
    );
  }
}

class _LayerFramePainter extends CustomPainter {
  const _LayerFramePainter({
    required this.center,
    required this.angle,
    required this.size,
    required this.color,
    required this.outline,
  });

  final Offset center;
  final double angle;
  final Size size;
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width,
        height: size.height,
      ),
      const Radius.circular(Radii.sm),
    );
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = outline;
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(angle)
      ..drawRRect(frame, outlinePaint)
      ..drawRRect(frame, framePaint);
    for (final corner in [
      frame.outerRect.topLeft,
      frame.outerRect.topRight,
      frame.outerRect.bottomLeft,
      frame.outerRect.bottomRight,
    ]) {
      canvas
        ..drawCircle(corner, _handleRadius + 0.75, Paint()..color = outline)
        ..drawCircle(corner, _handleRadius, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayerFramePainter oldDelegate) =>
      center != oldDelegate.center ||
      angle != oldDelegate.angle ||
      size != oldDelegate.size ||
      color != oldDelegate.color ||
      outline != oldDelegate.outline;
}

class _LayerAction extends StatelessWidget {
  const _LayerAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox.square(
            dimension: _actionSize,
            child: Center(
              child: HugeIcon(icon: icon, size: IconSizes.medium, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
