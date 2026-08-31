import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mobile_ocr/mobile_ocr.dart' show CharacterBox, TextBlock;
import 'package:photos/theme/colors.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/viewer/file/ocr/text_reading_order.dart';

// OCR character boxes tend to overhang slightly on the left edge, so keep the
// added selection slack slightly right-biased to visually center the highlight.
const double _kHighlightLeftPadding = 3.0;
const double _kHighlightRightPadding = 4.0;
const double _kHighlightVerticalPadding = 1.6;
const double _kHighlightCornerRadius = 4.0;
const double _kHighlightLineToleranceFactor = 0.7;

class TextOverlayController {
  _TextOverlayWidgetState? _state;

  void _attach(_TextOverlayWidgetState state) {
    _state = state;
  }

  void _detach(_TextOverlayWidgetState state) {
    if (_state == state) {
      _state = null;
    }
  }

  bool get hasActiveSelection => _state?._hasActiveSelection ?? false;

  Offset? _pendingAutoSelectPosition;

  void selectTextAtPosition(Offset globalPosition) {
    final state = _state;
    if (state != null && state._blockVisuals.isNotEmpty) {
      state._selectTextAtGlobalPosition(globalPosition);
    } else {
      _pendingAutoSelectPosition = globalPosition;
    }
  }

  void clearSelection() {
    _state?._clearSelection();
  }

  bool isPointOnSelectableText(Offset globalPosition) {
    return _state?._isGlobalPointOnSelectableText(globalPosition) ?? false;
  }

  bool isPointOnInteractiveSelectionUi(Offset globalPosition) {
    return _state?._isGlobalPointOnInteractiveSelectionUi(globalPosition) ??
        false;
  }

  void _consumePendingSelection() {
    final pos = _pendingAutoSelectPosition;
    if (pos == null) return;
    _pendingAutoSelectPosition = null;
    final state = _state;
    if (state != null) {
      state._selectTextAtGlobalPosition(pos);
    }
  }
}

class TextOverlayWidget extends StatefulWidget {
  final Size imageSize;
  final List<TextBlock> textBlocks;
  final VoidCallback? onTextCopied;
  final TextOverlayController controller;
  final bool isImageZoomed;
  final double uiScale;
  final Offset uiOffset;

  const TextOverlayWidget({
    super.key,
    required this.imageSize,
    required this.textBlocks,
    required this.controller,
    required this.isImageZoomed,
    required this.uiScale,
    required this.uiOffset,
    this.onTextCopied,
  });

  @override
  State<TextOverlayWidget> createState() => _TextOverlayWidgetState();
}

class _TextOverlayWidgetState extends State<TextOverlayWidget> {
  static const double _epsilon = 1e-6;
  static const double _characterHitPadding = 3.0;
  static const double _handleHitboxExtent = 72.0;
  static const double _toolbarMinVerticalSpacing = 24.0;
  static const double _toolbarViewportMargin = 12.0;
  static const double _toolbarButtonHorizontalPadding = 16.0;
  static const double _toolbarButtonVerticalPadding = 10.0;
  static const double _toolbarDividerWidth = 1.0;
  static const double _toolbarBorderWidth = 1.0;
  static const double _kMaterialTextLineHeight = 20.0;
  static const double _kDragStartSlop = 6.0;
  static final TextSelectionControls _selectionControls =
      MaterialTextSelectionControls();
  static final Size _handleVisualSize = _selectionControls.getHandleSize(
    _kMaterialTextLineHeight,
  );

  static double get _handleVisualHeight => _handleVisualSize.height;
  static double get _handleVisualWidth => _handleVisualSize.width;
  static double get _handleHorizontalPadding =>
      (_handleHitboxExtent - _handleVisualWidth) / 2;
  static double get _handleVerticalPadding =>
      (_handleHitboxExtent - _handleVisualHeight) / 2;
  static final RegExp _wordCharacterPattern = RegExp(
    r'[\p{L}\p{N}]',
    unicode: true,
  );

  final GlobalKey _overlayCoordinateKey = GlobalKey();

  Size? _displaySize;
  Offset? _displayOffset;
  BoxConstraints? _lastConstraints;
  bool _metricsUpdateScheduled = false;
  _DisplayMetrics? _queuedMetrics;

  final Map<int, _BlockVisual> _blockVisuals = <int, _BlockVisual>{};
  final List<int> _blockOrder = <int>[];
  bool get _hasActiveSelection => _activeSelections.isNotEmpty;
  bool get _isEntireTextSelected {
    var selectableBlockCount = 0;
    for (final index in _blockOrder) {
      final _BlockVisual? visual = _blockVisuals[index];
      if (visual == null || visual.characterCount == 0) {
        continue;
      }
      selectableBlockCount++;
      final TextSelection? selection = _activeSelections[index];
      if (selection == null ||
          selection.start != 0 ||
          selection.end != visual.characterCount) {
        return false;
      }
    }
    return selectableBlockCount > 0;
  }

  bool get _isPanFirstWhileZoomed => widget.isImageZoomed;

  Map<int, TextSelection> _activeSelections = <int, TextSelection>{};
  _SelectionAnchor? _baseAnchor;
  _SelectionAnchor? _extentAnchor;
  bool _isSelecting = false;
  int _activePointerCount = 0;
  int? _selectionPointerId;
  Offset? _selectionPointerDownScenePoint;
  bool _selectionDragArmed = false;
  bool _selectionDragInProgress = false;

  _HandleType? _activeHandle;
  Offset? _activeHandleTouchOffset;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildOverlay();
  }

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleMetricsRebuild(constraints);
        final Widget? copyButton = _buildCopyHandleButton(constraints);

        // Keep all visuals in one coordinate space. Text ignores pointers;
        // handles and the copy button remain interactive.
        final Widget visualLayer = KeyedSubtree(
          key: _overlayCoordinateKey,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const SizedBox.expand(),
                    ..._buildEditableBlockOverlays(),
                  ],
                ),
              ),
            ],
          ),
        );

        final Widget gestureLayer = _TextRegionHitTestBox(
          hitTest: _isPositionOnGestureLayer,
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: <Type, GestureRecognizerFactory>{
              _TextRegionLongPressRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _TextRegionLongPressRecognizer
                  >(
                    () => _TextRegionLongPressRecognizer(
                      hitTestBlock: _isPositionOnGestureLayer,
                    ),
                    (_TextRegionLongPressRecognizer instance) {
                      instance
                        ..hitTestBlock = _isPositionOnGestureLayer
                        ..onLongPressStart = (details) {
                          if (_activePointerCount > 1) return;
                          _onLongPressStart(details);
                        };
                    },
                  ),
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: const SizedBox.expand(),
            ),
          ),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            visualLayer,
            gestureLayer,
            ..._buildSelectionHandles(),
            ?copyButton,
          ],
        );
      },
    );
  }

  Offset? _sceneFromGlobal(Offset globalPoint) {
    final renderBox =
        _overlayCoordinateKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return null;
    }
    return renderBox.globalToLocal(globalPoint);
  }

  void _setActivePointerCount(int newCount) {
    final int clamped = max(0, newCount);
    if (clamped == _activePointerCount) {
      return;
    }

    _activePointerCount = clamped;

    if (_activePointerCount > 1) {
      _cancelPointerDrivenSelection();
    }
  }

  bool _isPrimaryPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return event.buttons == kPrimaryMouseButton;
    }
    return true;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _setActivePointerCount(_activePointerCount + 1);

    if (!_isPrimaryPointer(event) || _activePointerCount > 1) {
      return;
    }

    final Offset? scenePoint = _sceneFromGlobal(event.position);
    if (scenePoint == null) {
      return;
    }

    if (_isScenePointOnHandle(scenePoint)) {
      _clearPointerSelectionTracking();
      return;
    }

    if (_isPanFirstWhileZoomed) {
      _clearPointerSelectionTracking();
      return;
    }

    _clearPointerSelectionTracking();
    _selectionPointerId = event.pointer;
    _selectionPointerDownScenePoint = scenePoint;
    _selectionDragArmed = true;
    _selectionDragInProgress = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _selectionPointerId || _activePointerCount > 1) {
      return;
    }

    final Offset? scenePoint = _sceneFromGlobal(event.position);
    if (scenePoint == null) {
      return;
    }

    _selectionPointerDownScenePoint ??= scenePoint;

    if (_selectionDragArmed && !_selectionDragInProgress) {
      final Offset? initial = _selectionPointerDownScenePoint;
      final double delta = initial == null
          ? 0.0
          : (scenePoint - initial).distance;
      if (delta < _kDragStartSlop) {
        return;
      }

      bool started = false;
      if (initial != null) {
        started = _beginDragSelection(initial);
      }
      if (!started) {
        started = _beginDragSelection(scenePoint);
      }
      if (started) {
        _selectionDragArmed = false;
        _selectionDragInProgress = true;
        if (initial != null && (scenePoint - initial).distance > 0.0) {
          _continueDragSelection(scenePoint);
        }
      }
      return;
    }

    if (_isSelecting && !_selectionDragInProgress) {
      _selectionDragInProgress = true;
    }

    if (_selectionDragInProgress) {
      _continueDragSelection(scenePoint);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer == _selectionPointerId) {
      if (_selectionDragInProgress) {
        _finishDragSelection(cancelled: false);
      }
      _clearPointerSelectionTracking();
    }
    _setActivePointerCount(_activePointerCount - 1);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _selectionPointerId) {
      if (_selectionDragInProgress) {
        _finishDragSelection(cancelled: true);
      }
      _clearPointerSelectionTracking();
    }
    _setActivePointerCount(_activePointerCount - 1);
  }

  void _cancelPointerDrivenSelection() {
    if (_selectionDragInProgress) {
      _finishDragSelection(cancelled: true);
    }
    _clearPointerSelectionTracking();
  }

  void _clearPointerSelectionTracking() {
    _selectionPointerId = null;
    _selectionPointerDownScenePoint = null;
    _selectionDragArmed = false;
    _selectionDragInProgress = false;
  }

  bool _beginDragSelection(Offset scenePoint) {
    final int? blockIndex = _hitTestBlock(scenePoint);
    if (blockIndex == null) {
      if (_activeSelections.isNotEmpty) {
        _clearSelection();
      }
      return false;
    }

    final _SelectionAnchor anchor = _anchorForPoint(blockIndex, scenePoint);
    setState(() {
      _isSelecting = true;
      _baseAnchor = anchor;
      _extentAnchor = anchor;
      _recomputeSelections();
    });
    if (_activeSelections.isNotEmpty) {
      HapticFeedback.selectionClick();
    }
    return true;
  }

  void _continueDragSelection(Offset scenePoint) {
    if (!_isSelecting) {
      return;
    }

    final int? blockIndex =
        _hitTestBlock(scenePoint) ?? _nearestBlockIndex(scenePoint);
    if (blockIndex == null) {
      return;
    }

    final _SelectionAnchor anchor = _anchorForPoint(blockIndex, scenePoint);
    setState(() {
      _extentAnchor = anchor;
      _recomputeSelections();
    });
  }

  void _finishDragSelection({required bool cancelled}) {
    if (!mounted || !_isSelecting) {
      return;
    }

    setState(() => _isSelecting = false);

    if (_activeSelections.isNotEmpty) {
      if (!cancelled) {
        HapticFeedback.lightImpact();
      }
    } else {
      _baseAnchor = null;
      _extentAnchor = null;
    }
  }

  void _scheduleMetricsRebuild(BoxConstraints constraints) {
    if (_lastConstraints != null &&
        (_lastConstraints!.maxWidth - constraints.maxWidth).abs() < 0.5 &&
        (_lastConstraints!.maxHeight - constraints.maxHeight).abs() < 0.5) {
      return;
    }

    _lastConstraints = constraints;
    final metrics = _calculateMetrics(constraints);

    final bool needsUpdate =
        _displaySize == null ||
        !_roughlyEqualsSize(_displaySize!, metrics.size) ||
        _displayOffset == null ||
        !_roughlyEqualsOffset(_displayOffset!, metrics.offset);

    if (!needsUpdate) {
      return;
    }

    if (_metricsUpdateScheduled) {
      _queuedMetrics = metrics;
      return;
    }

    _metricsUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _metricsUpdateScheduled = false;
        _queuedMetrics = null;
        return;
      }
      final pending = _queuedMetrics ?? metrics;
      _queuedMetrics = null;
      _applyMetrics(pending);
      _metricsUpdateScheduled = false;
    });
  }

  _DisplayMetrics _calculateMetrics(BoxConstraints constraints) {
    final double imageAspect = widget.imageSize.width / widget.imageSize.height;
    final double containerAspect = constraints.maxWidth / constraints.maxHeight;

    double displayWidth;
    double displayHeight;

    if (imageAspect > containerAspect) {
      displayWidth = constraints.maxWidth;
      displayHeight = displayWidth / imageAspect;
    } else {
      displayHeight = constraints.maxHeight;
      displayWidth = displayHeight * imageAspect;
    }

    final double offsetX = (constraints.maxWidth - displayWidth) / 2;
    final double offsetY = (constraints.maxHeight - displayHeight) / 2;

    return _DisplayMetrics(
      Size(displayWidth, displayHeight),
      Offset(offsetX, offsetY),
    );
  }

  void _applyMetrics(_DisplayMetrics metrics) {
    setState(() {
      _displaySize = metrics.size;
      _displayOffset = metrics.offset;
      _computeBlockVisuals();
    });
    widget.controller._consumePendingSelection();
  }

  double get _effectiveUiScale =>
      widget.uiScale <= _epsilon ? 1.0 : widget.uiScale;

  Rect _viewportSceneRect(Size viewportSize) {
    final Offset center = viewportSize.center(Offset.zero);

    Offset inverseTransform(Offset viewportPoint) {
      return center +
          ((viewportPoint - center - widget.uiOffset) / _effectiveUiScale);
    }

    final Offset topLeft = inverseTransform(Offset.zero);
    final Offset bottomRight = inverseTransform(
      Offset(viewportSize.width, viewportSize.height),
    );

    return Rect.fromLTRB(
      min(topLeft.dx, bottomRight.dx),
      min(topLeft.dy, bottomRight.dy),
      max(topLeft.dx, bottomRight.dx),
      max(topLeft.dy, bottomRight.dy),
    );
  }

  TextStyle get _toolbarButtonTextStyle =>
      getEnteTextTheme(context).small.copyWith(color: textBaseDark);

  Size _measureToolbarScreenSize(
    MaterialLocalizations localizations,
    TextStyle buttonTextStyle,
  ) {
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final TextDirection textDirection = Directionality.of(context);

    Size measureLabel(String text) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: buttonTextStyle),
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      return painter.size;
    }

    final Size copyLabelSize = measureLabel(localizations.copyButtonLabel);
    final Size selectAllLabelSize = measureLabel(
      localizations.selectAllButtonLabel,
    );

    final double buttonHeight = max(
      max(copyLabelSize.height, selectAllLabelSize.height) +
          (_toolbarButtonVerticalPadding * 2) +
          (_toolbarBorderWidth * 2),
      36.0,
    );
    double buttonWidthFor(Size labelSize) =>
        max(labelSize.width + (_toolbarButtonHorizontalPadding * 2), 64.0);

    return Size(
      buttonWidthFor(copyLabelSize) +
          buttonWidthFor(selectAllLabelSize) +
          _toolbarDividerWidth +
          (_toolbarBorderWidth * 2) +
          8.0,
      buttonHeight,
    );
  }

  _ToolbarLayout? _toolbarLayout(BoxConstraints constraints) {
    if (_activeSelections.isEmpty || _activeHandle != null || _isSelecting) {
      return null;
    }

    final Rect? selectionBounds = _selectedRegionBounds();
    if (selectionBounds == null) {
      return null;
    }

    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final TextStyle buttonTextStyle = _toolbarButtonTextStyle;

    final Size screenSize = _measureToolbarScreenSize(
      localizations,
      buttonTextStyle,
    );
    final Size sceneSize = Size(
      screenSize.width / _effectiveUiScale,
      screenSize.height / _effectiveUiScale,
    );
    final Rect viewportSceneRect = _viewportSceneRect(constraints.biggest);
    final double sceneMargin = _toolbarViewportMargin / _effectiveUiScale;
    final double sceneSpacing =
        max(_toolbarMinVerticalSpacing, _handleVisualHeight + 12.0) /
        _effectiveUiScale;

    final double minLeft = viewportSceneRect.left + sceneMargin;
    final double maxLeft = max(
      minLeft,
      viewportSceneRect.right - sceneSize.width - sceneMargin,
    );
    final bool centerInViewport = _isEntireTextSelected;
    final double horizontalCenter = centerInViewport
        ? viewportSceneRect.center.dx
        : selectionBounds.center.dx;
    final double left = (horizontalCenter - (sceneSize.width / 2)).clamp(
      minLeft,
      maxLeft,
    );

    final double minTop = viewportSceneRect.top + sceneMargin;
    final double maxTop = max(
      minTop,
      viewportSceneRect.bottom - sceneSize.height - sceneMargin,
    );
    late final double top;
    if (centerInViewport) {
      top = (viewportSceneRect.center.dy - (sceneSize.height / 2)).clamp(
        minTop,
        maxTop,
      );
    } else {
      final double preferredTop =
          selectionBounds.top - sceneSpacing - sceneSize.height;
      final double fallbackTop = selectionBounds.bottom + sceneSpacing;
      final bool fitsAbove = preferredTop >= minTop;
      top = (fitsAbove ? preferredTop : fallbackTop).clamp(minTop, maxTop);
    }

    return _ToolbarLayout(
      sceneRect: Rect.fromLTWH(left, top, sceneSize.width, sceneSize.height),
      screenSize: screenSize,
    );
  }

  Rect _inflateSelectionRect(Rect rect) {
    return Rect.fromLTRB(
      rect.left - _kHighlightLeftPadding,
      rect.top - _kHighlightVerticalPadding,
      rect.right + _kHighlightRightPadding,
      rect.bottom + _kHighlightVerticalPadding,
    );
  }

  bool _isScenePointOnToolbar(Offset scenePoint) {
    final BoxConstraints? constraints = _lastConstraints;
    if (constraints == null) {
      return false;
    }
    final _ToolbarLayout? layout = _toolbarLayout(constraints);
    return layout != null && layout.sceneRect.contains(scenePoint);
  }

  bool _isScenePointOnInteractiveSelectionUi(Offset scenePoint) {
    return _isScenePointOnHandle(scenePoint) ||
        _isScenePointOnToolbar(scenePoint);
  }

  bool _isGlobalPointOnSelectableText(Offset globalPosition) {
    final Offset? scenePoint = _sceneFromGlobal(globalPosition);
    return scenePoint != null && _hitTestBlock(scenePoint) != null;
  }

  bool _isGlobalPointOnInteractiveSelectionUi(Offset globalPosition) {
    final Offset? scenePoint = _sceneFromGlobal(globalPosition);
    return scenePoint != null &&
        _isScenePointOnInteractiveSelectionUi(scenePoint);
  }

  bool _isPositionOnGestureLayer(Offset globalPosition) {
    final Offset? scenePoint = _sceneFromGlobal(globalPosition);
    if (scenePoint == null) {
      return false;
    }

    if (_isScenePointOnHandle(scenePoint) ||
        _isScenePointOnToolbar(scenePoint)) {
      return true;
    }

    if (_isPanFirstWhileZoomed) {
      return false;
    }

    return _hitTestBlock(scenePoint) != null;
  }

  Color _handleColor(BuildContext context) {
    final TextSelectionThemeData theme = TextSelectionTheme.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return theme.selectionHandleColor ?? scheme.primary;
  }

  Color _selectionHighlightColor(BuildContext context) {
    final TextSelectionThemeData theme = TextSelectionTheme.of(context);
    final Color? selectionColor = theme.selectionColor;
    if (selectionColor != null) {
      return selectionColor;
    }
    final Color base = _handleColor(context);
    final double targetOpacity = base.a == 1.0 ? 0.28 : base.a;
    final double clampedOpacity = targetOpacity.clamp(0.2, 0.35);
    return base.withValues(alpha: clampedOpacity);
  }

  List<Widget> _buildEditableBlockOverlays() {
    if (_displaySize == null || _displayOffset == null) {
      return const [];
    }

    final List<Widget> overlays = <Widget>[];
    final Color selectionColor = _selectionHighlightColor(context);
    for (final index in _blockOrder) {
      final visual = _blockVisuals[index];
      if (visual == null) {
        continue;
      }

      overlays.add(
        Positioned(
          left: visual.bounds.left,
          top: visual.bounds.top,
          width: visual.bounds.width,
          height: visual.bounds.height,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _EditableBlockPainter(
                visual: visual,
                selection: _activeSelections[index],
                selectionColor: selectionColor,
              ),
            ),
          ),
        ),
      );
    }

    return overlays;
  }

  Rect? _selectedRegionBounds() {
    if (_activeSelections.isEmpty) {
      return null;
    }

    Rect? bounds;
    for (final entry in _activeSelections.entries) {
      final _BlockVisual? visual = _blockVisuals[entry.key];
      if (visual == null || visual.characterCount == 0) {
        continue;
      }

      final selection = entry.value;
      final int start = selection.start.clamp(0, visual.characterCount);
      final int end = selection.end.clamp(start, visual.characterCount);
      if (start >= end) {
        continue;
      }

      for (int i = start; i < end && i < visual.characters.length; i++) {
        final Rect charRect = visual.characters[i].bounds;
        if (charRect.isEmpty) {
          continue;
        }
        final Rect expanded = _inflateSelectionRect(charRect);
        final Rect globalRect = expanded.shift(visual.bounds.topLeft);
        bounds = bounds == null
            ? globalRect
            : bounds.expandToInclude(globalRect);
      }
    }

    if (bounds == null) {
      final _SelectionAnchor? baseAnchor = _baseAnchor;
      if (baseAnchor != null) {
        final Rect? startRect = _caretRectForAnchor(baseAnchor, isStart: true);
        if (startRect != null) {
          bounds = startRect;
        }
      }
      final _SelectionAnchor? extentAnchor = _extentAnchor;
      if (extentAnchor != null) {
        final Rect? endRect = _caretRectForAnchor(extentAnchor, isStart: false);
        if (endRect != null) {
          bounds = bounds == null ? endRect : bounds.expandToInclude(endRect);
        }
      }
    }

    return bounds;
  }

  List<Widget> _buildSelectionHandles() {
    if (_activeSelections.isEmpty ||
        _baseAnchor == null ||
        _extentAnchor == null) {
      return const [];
    }

    final List<Widget> handles = <Widget>[];

    final _SelectionAnchor baseAnchor = _baseAnchor!;
    final Offset? startPoint = _handleAnchorPoint(baseAnchor, isStart: true);
    if (startPoint != null) {
      handles.add(_buildHandleWidget(anchorPoint: startPoint, isStart: true));
    }

    final _SelectionAnchor extentAnchor = _extentAnchor!;
    final Offset? endPoint = _handleAnchorPoint(extentAnchor, isStart: false);
    if (endPoint != null) {
      handles.add(_buildHandleWidget(anchorPoint: endPoint, isStart: false));
    }

    return handles;
  }

  Widget? _buildCopyHandleButton(BoxConstraints constraints) {
    final _ToolbarLayout? layout = _toolbarLayout(constraints);
    if (layout == null) {
      return null;
    }

    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );

    final TextStyle buttonTextStyle = _toolbarButtonTextStyle;

    final Widget toolbar = Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              alignment: Alignment.center,
              foregroundColor: Colors.white,
              minimumSize: const Size(64, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
              ),
            ),
            onPressed: _copySelectedText,
            child: Text(localizations.copyButtonLabel, style: buttonTextStyle),
          ),
          Container(width: 1, color: Colors.white.withValues(alpha: 0.2)),
          TextButton(
            style: TextButton.styleFrom(
              alignment: Alignment.center,
              foregroundColor: Colors.white,
              minimumSize: const Size(64, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
              ),
            ),
            onPressed: _selectAllText,
            child: Text(
              localizations.selectAllButtonLabel,
              style: buttonTextStyle,
            ),
          ),
        ],
      ),
    );

    return Positioned(
      left: layout.sceneRect.left,
      top: layout.sceneRect.top,
      width: layout.sceneRect.width,
      height: layout.sceneRect.height,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: layout.screenSize.width,
        maxWidth: layout.screenSize.width,
        minHeight: layout.screenSize.height,
        maxHeight: layout.screenSize.height,
        child: Transform.scale(
          alignment: Alignment.topLeft,
          scale: 1.0 / _effectiveUiScale,
          child: SizedBox(
            width: layout.screenSize.width,
            height: layout.screenSize.height,
            child: toolbar,
          ),
        ),
      ),
    );
  }

  Widget _buildHandleWidget({
    required Offset anchorPoint,
    required bool isStart,
  }) {
    final TextSelectionHandleType handleType = isStart
        ? TextSelectionHandleType.left
        : TextSelectionHandleType.right;
    final Rect hitbox = _handleHitboxRectForAnchor(anchorPoint, handleType);

    return Positioned(
      left: hitbox.left,
      top: hitbox.top,
      width: hitbox.width,
      height: hitbox.height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) => _onHandlePanStart(
          details,
          isStart ? _HandleType.base : _HandleType.extent,
        ),
        onPanUpdate: _onHandlePanUpdate,
        onPanEnd: (_) => _onHandlePanEnd(),
        onPanCancel: _onHandlePanCancel,
        child: Transform.scale(
          alignment: _handleScaleAlignment(handleType),
          scale: 1.0 / _effectiveUiScale,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _handleHorizontalPadding,
              vertical: _handleVerticalPadding,
            ),
            child: _selectionControls.buildHandle(
              context,
              handleType,
              _kMaterialTextLineHeight,
            ),
          ),
        ),
      ),
    );
  }

  Alignment _handleScaleAlignment(TextSelectionHandleType type) {
    final Offset handleAnchor = _selectionControls.getHandleAnchor(
      type,
      _kMaterialTextLineHeight,
    );
    final Offset anchorWithinHitbox =
        handleAnchor + Offset(_handleHorizontalPadding, _handleVerticalPadding);
    return Alignment(
      (anchorWithinHitbox.dx / _handleHitboxExtent) * 2 - 1,
      (anchorWithinHitbox.dy / _handleHitboxExtent) * 2 - 1,
    );
  }

  Rect _handleHitboxRectForAnchor(
    Offset anchorPoint,
    TextSelectionHandleType type,
  ) {
    final Offset handleAnchor = _selectionControls.getHandleAnchor(
      type,
      _kMaterialTextLineHeight,
    );
    final Offset hitboxTopLeft =
        anchorPoint -
        handleAnchor -
        Offset(_handleHorizontalPadding, _handleVerticalPadding);
    return Rect.fromLTWH(
      hitboxTopLeft.dx,
      hitboxTopLeft.dy,
      _handleHitboxExtent,
      _handleHitboxExtent,
    );
  }

  Offset? _handleAnchorPoint(_SelectionAnchor anchor, {required bool isStart}) {
    final Rect? caretRect = _caretRectForAnchor(anchor, isStart: isStart);
    if (caretRect == null) {
      return null;
    }
    return isStart ? caretRect.bottomLeft : caretRect.bottomRight;
  }

  bool _isScenePointOnHandle(Offset scenePoint) {
    if (_activeSelections.isEmpty ||
        _baseAnchor == null ||
        _extentAnchor == null) {
      return false;
    }

    final Offset? startPoint = _handleAnchorPoint(_baseAnchor!, isStart: true);
    if (startPoint != null) {
      final Rect startRect = _handleHitboxRectForAnchor(
        startPoint,
        TextSelectionHandleType.left,
      );
      if (startRect.contains(scenePoint)) {
        return true;
      }
    }

    final Offset? endPoint = _handleAnchorPoint(_extentAnchor!, isStart: false);
    if (endPoint != null) {
      final Rect endRect = _handleHitboxRectForAnchor(
        endPoint,
        TextSelectionHandleType.right,
      );
      if (endRect.contains(scenePoint)) {
        return true;
      }
    }

    return false;
  }

  Rect? _caretRectForAnchor(_SelectionAnchor anchor, {required bool isStart}) {
    final _BlockVisual? visual = _blockVisuals[anchor.blockIndex];
    if (visual == null || visual.characterCount == 0) {
      return null;
    }

    final int count = visual.characterCount;
    int referenceIndex;
    if (isStart) {
      referenceIndex = _clampIndex(anchor.position.offset, 0, count - 1);
    } else {
      referenceIndex = _clampIndex(anchor.position.offset - 1, 0, count - 1);
    }

    final Rect? baseRect = _visibleRectNearIndex(
      visual,
      referenceIndex,
      preferForward: isStart,
    );
    if (baseRect == null) {
      return null;
    }

    final Rect inflated = _inflateSelectionRect(baseRect);

    return inflated.shift(visual.bounds.topLeft);
  }

  Rect? _visibleRectNearIndex(
    _BlockVisual visual,
    int index, {
    required bool preferForward,
  }) {
    if (visual.characterCount == 0) {
      return null;
    }

    final List<_CharacterVisual> characters = visual.characters;
    final int clamped = _clampIndex(index, 0, characters.length - 1);

    final Rect candidate = characters[clamped].bounds;
    if (_isRenderableRect(candidate)) {
      return candidate;
    }

    if (preferForward) {
      for (int i = clamped + 1; i < characters.length; i++) {
        final Rect next = characters[i].bounds;
        if (_isRenderableRect(next)) {
          return next;
        }
      }
      for (int i = clamped - 1; i >= 0; i--) {
        final Rect prev = characters[i].bounds;
        if (_isRenderableRect(prev)) {
          return prev;
        }
      }
    } else {
      for (int i = clamped - 1; i >= 0; i--) {
        final Rect prev = characters[i].bounds;
        if (_isRenderableRect(prev)) {
          return prev;
        }
      }
      for (int i = clamped + 1; i < characters.length; i++) {
        final Rect next = characters[i].bounds;
        if (_isRenderableRect(next)) {
          return next;
        }
      }
    }

    return null;
  }

  void _onHandlePanStart(DragStartDetails details, _HandleType type) {
    final bool isStart = type == _HandleType.base;
    final _SelectionAnchor? activeAnchor = isStart
        ? _baseAnchor
        : _extentAnchor;
    final Offset? anchorPoint = activeAnchor == null
        ? null
        : _handleAnchorPoint(activeAnchor, isStart: isStart);
    final Offset? fingerScene = _sceneFromGlobal(details.globalPosition);
    _activeHandleTouchOffset = anchorPoint != null && fingerScene != null
        ? anchorPoint - fingerScene
        : null;

    setState(() {
      _activeHandle = type;
      _isSelecting = true;
      final Offset? targetPoint = fingerScene == null
          ? anchorPoint
          : fingerScene + (_activeHandleTouchOffset ?? Offset.zero);
      if (targetPoint != null) {
        final int? blockIndex =
            _hitTestBlock(targetPoint) ?? _nearestBlockIndex(targetPoint);
        if (blockIndex != null) {
          final _SelectionAnchor anchor = _anchorForPoint(
            blockIndex,
            targetPoint,
          );
          if (isStart) {
            _baseAnchor = anchor;
          } else {
            _extentAnchor = anchor;
          }
          _recomputeSelections();
        }
      }
    });
    if (_activeSelections.isNotEmpty) {
      HapticFeedback.selectionClick();
    }
  }

  void _onHandlePanUpdate(DragUpdateDetails details) {
    if (_activeHandle == null) {
      return;
    }

    final Offset? fingerScene = _sceneFromGlobal(details.globalPosition);
    if (fingerScene == null) {
      return;
    }

    final Offset targetPoint =
        fingerScene + (_activeHandleTouchOffset ?? Offset.zero);
    final int? blockIndex =
        _hitTestBlock(targetPoint) ?? _nearestBlockIndex(targetPoint);
    if (blockIndex == null) {
      return;
    }

    final _SelectionAnchor anchor = _anchorForPoint(blockIndex, targetPoint);
    setState(() {
      if (_activeHandle == _HandleType.base) {
        _baseAnchor = anchor;
      } else {
        _extentAnchor = anchor;
      }
      _recomputeSelections();
    });
  }

  void _onHandlePanEnd() {
    if (_activeHandle == null) {
      return;
    }

    setState(() {
      _isSelecting = false;
      _activeHandle = null;
      _activeHandleTouchOffset = null;
    });

    if (_activeSelections.isNotEmpty) {
      HapticFeedback.lightImpact();
    } else {
      _baseAnchor = null;
      _extentAnchor = null;
    }
  }

  void _onHandlePanCancel() {
    if (_activeHandle == null) {
      return;
    }

    setState(() {
      _isSelecting = false;
      _activeHandle = null;
      _activeHandleTouchOffset = null;
    });

    if (_activeSelections.isEmpty) {
      _baseAnchor = null;
      _extentAnchor = null;
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final scenePoint = _sceneFromGlobal(details.globalPosition);
    if (scenePoint == null) {
      return;
    }

    final blockIndex = _hitTestBlock(scenePoint);
    if (blockIndex == null) {
      return;
    }

    final bool wordSelected = _performWordSelection(
      blockIndex,
      scenePoint,
      finalizeSelection: true,
    );

    if (wordSelected) {
      _clearPointerSelectionTracking();
      return;
    }

    final anchor = _anchorForPoint(blockIndex, scenePoint);
    setState(() {
      _isSelecting = true;
      _baseAnchor = anchor;
      _extentAnchor = anchor;
      _recomputeSelections();
    });

    _selectionDragArmed = false;
    _selectionDragInProgress = true;
    _selectionPointerDownScenePoint ??= scenePoint;
    HapticFeedback.mediumImpact();
  }

  bool _performWordSelection(
    int blockIndex,
    Offset scenePoint, {
    bool finalizeSelection = true,
  }) {
    final _BlockVisual? visual = _blockVisuals[blockIndex];
    if (visual == null || visual.characterCount == 0) {
      return false;
    }

    final _SelectionAnchor anchor = _anchorForPoint(blockIndex, scenePoint);
    int characterIndex = anchor.position.offset;
    if (characterIndex >= visual.characterCount) {
      characterIndex = visual.characterCount - 1;
    }
    if (characterIndex < 0) {
      characterIndex = 0;
    }

    final TextRange? range = _wordBoundaryAt(visual, characterIndex);
    if (range == null || range.isCollapsed) {
      return false;
    }

    setState(() {
      _baseAnchor = _SelectionAnchor(
        blockIndex,
        TextPosition(offset: range.start),
      );
      _extentAnchor = _SelectionAnchor(
        blockIndex,
        TextPosition(offset: range.end),
      );
      _isSelecting = !finalizeSelection;
      _recomputeSelections();
    });
    if (_activeSelections.isNotEmpty) {
      if (finalizeSelection) {
        HapticFeedback.selectionClick();
      }
      return true;
    }
    return false;
  }

  TextRange? _wordBoundaryAt(_BlockVisual visual, int index) {
    final int charCount = visual.characterCount;
    if (charCount == 0) {
      return null;
    }

    final int clampedIndex = _clampIndex(index, 0, charCount - 1);
    final _GlyphCategory category = _glyphCategory(
      visual.characters[clampedIndex].text,
    );
    if (category == _GlyphCategory.whitespace) {
      return null;
    }

    int start = clampedIndex;
    while (start > 0 &&
        _glyphCategory(visual.characters[start - 1].text) == category) {
      start -= 1;
    }

    int end = clampedIndex + 1;
    while (end < charCount &&
        _glyphCategory(visual.characters[end].text) == category) {
      end += 1;
    }

    start = _clampIndex(start, 0, charCount);
    end = _clampIndex(end, 0, charCount);

    if (start == end) {
      if (end < charCount) {
        end = _clampIndex(end + 1, 0, charCount);
      } else if (start > 0) {
        start = _clampIndex(start - 1, 0, charCount);
      }
    }

    if (start >= end) {
      return null;
    }

    return TextRange(start: start, end: end);
  }

  _GlyphCategory _glyphCategory(String character) {
    if (character.trim().isEmpty) {
      return _GlyphCategory.whitespace;
    }
    if (_wordCharacterPattern.hasMatch(character)) {
      return _GlyphCategory.word;
    }
    return _GlyphCategory.symbol;
  }

  _SelectionAnchor _anchorForPoint(int blockIndex, Offset globalPoint) {
    final visual = _blockVisuals[blockIndex];
    if (visual == null || visual.characterCount == 0) {
      return _SelectionAnchor(blockIndex, const TextPosition(offset: 0));
    }

    final bounds = visual.bounds;
    if (globalPoint.dx <= bounds.left - 1) {
      return _SelectionAnchor(blockIndex, const TextPosition(offset: 0));
    }
    if (globalPoint.dx >= bounds.right + 1) {
      return _SelectionAnchor(
        blockIndex,
        TextPosition(offset: visual.characterCount),
      );
    }

    final localPoint = globalPoint - bounds.topLeft;

    for (int i = 0; i < visual.characters.length; i++) {
      final character = visual.characters[i];
      final rect = character.bounds;
      if (!rect.isEmpty) {
        final paddedRect = rect.inflate(_characterHitPadding);
        if (paddedRect.contains(localPoint)) {
          return _SelectionAnchor(blockIndex, TextPosition(offset: i));
        }
      }
      if (character.polygon.length >= 3 &&
          _pointInPolygon(character.polygon, localPoint)) {
        return _SelectionAnchor(blockIndex, TextPosition(offset: i));
      }
    }

    int? bestIndex;
    double bestDistance = double.infinity;
    for (int i = 0; i < visual.characters.length; i++) {
      final rect = visual.characters[i].bounds;
      if (rect.isEmpty) {
        continue;
      }
      final paddedRect = rect.inflate(_characterHitPadding);
      final dx = _distanceToRange(
        localPoint.dx,
        paddedRect.left,
        paddedRect.right,
      );
      final dy = _distanceToRange(
        localPoint.dy,
        paddedRect.top,
        paddedRect.bottom,
      );
      final distance = sqrt(dx * dx + dy * dy);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    final fallbackIndex = bestIndex ?? 0;
    return _SelectionAnchor(blockIndex, TextPosition(offset: fallbackIndex));
  }

  int? _hitTestBlock(Offset point) {
    for (final entry in _blockVisuals.entries) {
      final polygon = entry.value.scaledPolygon;
      if (polygon.isEmpty) {
        continue;
      }
      if (_pointInPolygon(polygon, point)) {
        return entry.key;
      }
    }
    return null;
  }

  int? _nearestBlockIndex(Offset point) {
    if (_blockVisuals.isEmpty) {
      return null;
    }

    int? nearestIndex;
    double smallestDistance = double.infinity;

    for (final entry in _blockVisuals.entries) {
      final rect = entry.value.bounds;
      final dx = _distanceToRange(point.dx, rect.left, rect.right);
      final dy = _distanceToRange(point.dy, rect.top, rect.bottom);
      final distance = sqrt(dx * dx + dy * dy);
      if (distance < smallestDistance) {
        smallestDistance = distance;
        nearestIndex = entry.key;
      }
    }

    return nearestIndex;
  }

  void _recomputeSelections() {
    _clampAnchorsToVisuals();
    _normalizeAnchors();
    _activeSelections = _computeSelections(_baseAnchor, _extentAnchor);
  }

  void _normalizeAnchors() {
    if (_baseAnchor == null || _extentAnchor == null) {
      return;
    }

    final int baseOrder = _blockOrder.indexOf(_baseAnchor!.blockIndex);
    final int extentOrder = _blockOrder.indexOf(_extentAnchor!.blockIndex);
    if (baseOrder == -1 || extentOrder == -1) {
      return;
    }

    final bool shouldSwap =
        baseOrder > extentOrder ||
        (baseOrder == extentOrder &&
            _extentAnchor!.position.offset < _baseAnchor!.position.offset);

    if (shouldSwap) {
      final temp = _baseAnchor;
      _baseAnchor = _extentAnchor;
      _extentAnchor = temp;
    }
  }

  double _distanceToRange(double value, double min, double max) {
    if (value < min) return min - value;
    if (value > max) return value - max;
    return 0.0;
  }

  void _computeBlockVisuals() {
    _blockVisuals.clear();
    _blockOrder.clear();

    if (_displaySize == null || _displayOffset == null) {
      return;
    }

    for (final entry in widget.textBlocks.asMap().entries) {
      final index = entry.key;
      final block = entry.value;

      final scaledPoints = _getScaledPoints(block);
      if (scaledPoints.length < 3) {
        continue;
      }

      final bounds = _rectFromPoints(scaledPoints);
      if (bounds.width <= 0 || bounds.height <= 0) {
        continue;
      }

      final origin = bounds.topLeft;
      final localPolygon = scaledPoints
          .map((point) => point - origin)
          .toList(growable: false);
      final geometry = _OrientedGeometry.fromPolygon(localPolygon);
      final characters = _buildCharacterVisuals(
        block,
        scaledPoints,
        bounds,
        geometry,
      );
      if (characters.isEmpty) {
        continue;
      }

      _blockVisuals[index] = _BlockVisual(
        index: index,
        block: block,
        scaledPolygon: scaledPoints,
        bounds: bounds,
        characters: characters,
        geometry: geometry,
      );
      _blockOrder.add(index);
    }

    _blockOrder
      ..clear()
      ..addAll(
        orderTextBlocksForReading(
          _blockVisuals.values.map(
            (visual) => TextReadingOrderBlock(
              index: visual.index,
              bounds: visual.bounds,
              text: visual.block.text,
            ),
          ),
        ),
      );
    _recomputeSelections();
  }

  List<_CharacterVisual> _buildCharacterVisuals(
    TextBlock block,
    List<Offset> scaledBlockPolygon,
    Rect blockBounds,
    _OrientedGeometry geometry,
  ) {
    final origin = blockBounds.topLeft;

    if (block.characters.isNotEmpty) {
      final visuals = <_CharacterVisual>[];
      for (final character in block.characters) {
        final scaled = _getScaledCharacterPoints(character);
        if (scaled.length < 3) {
          continue;
        }
        final localPolygon = scaled
            .map((point) => point - origin)
            .toList(growable: false);
        if (localPolygon.isEmpty) {
          continue;
        }
        final rect = _rectFromPoints(localPolygon);
        final _OrientedBounds? orientedBounds = geometry.isValid
            ? _orientedBoundsForPolygon(geometry, localPolygon)
            : null;
        visuals.add(
          _CharacterVisual(
            text: character.text,
            confidence: character.confidence,
            polygon: localPolygon,
            bounds: rect,
            orientedBounds: orientedBounds,
          ),
        );
      }
      if (visuals.isNotEmpty) {
        return visuals;
      }
    }

    return _buildFallbackCharacters(
      block,
      scaledBlockPolygon,
      blockBounds,
      geometry,
    );
  }

  List<_CharacterVisual> _buildFallbackCharacters(
    TextBlock block,
    List<Offset> scaledBlockPolygon,
    Rect blockBounds,
    _OrientedGeometry geometry,
  ) {
    final origin = blockBounds.topLeft;

    if (scaledBlockPolygon.length < 4) {
      if (scaledBlockPolygon.length >= 3) {
        final localPolygon = scaledBlockPolygon
            .map((point) => point - origin)
            .toList(growable: false);
        final rect = _rectFromPoints(localPolygon);
        final _OrientedBounds? orientedBounds = geometry.isValid
            ? _orientedBoundsForPolygon(geometry, localPolygon)
            : null;
        return [
          _CharacterVisual(
            text: block.text,
            confidence: block.confidence,
            polygon: localPolygon,
            bounds: rect,
            orientedBounds: orientedBounds,
          ),
        ];
      }
      return const [];
    }

    final topLeft = scaledBlockPolygon[0];
    final topRight = scaledBlockPolygon[1];
    final bottomRight = scaledBlockPolygon[2];
    final bottomLeft = scaledBlockPolygon[3];

    if (block.text.isEmpty) {
      final localPolygon = scaledBlockPolygon
          .map((point) => point - origin)
          .toList(growable: false);
      final rect = _rectFromPoints(localPolygon);
      final _OrientedBounds? orientedBounds = geometry.isValid
          ? _orientedBoundsForPolygon(geometry, localPolygon)
          : null;
      return [
        _CharacterVisual(
          text: '',
          confidence: block.confidence,
          polygon: localPolygon,
          bounds: rect,
          orientedBounds: orientedBounds,
        ),
      ];
    }

    final characters = <_CharacterVisual>[];
    final text = block.text;
    final length = text.length;
    for (int i = 0; i < length; i++) {
      final startRatio = i / length;
      final endRatio = (i + 1) / length;

      final topStart = _interpolateOffset(topLeft, topRight, startRatio);
      final topEnd = _interpolateOffset(topLeft, topRight, endRatio);
      final bottomStart = _interpolateOffset(
        bottomLeft,
        bottomRight,
        startRatio,
      );
      final bottomEnd = _interpolateOffset(bottomLeft, bottomRight, endRatio);

      final polygon = <Offset>[topStart, topEnd, bottomEnd, bottomStart];
      final localPolygon = polygon
          .map((point) => point - origin)
          .toList(growable: false);
      final rect = _rectFromPoints(localPolygon);
      final _OrientedBounds? orientedBounds = geometry.isValid
          ? _orientedBoundsForPolygon(geometry, localPolygon)
          : null;
      characters.add(
        _CharacterVisual(
          text: text[i],
          confidence: block.confidence,
          polygon: localPolygon,
          bounds: rect,
          orientedBounds: orientedBounds,
        ),
      );
    }

    return characters;
  }

  _OrientedBounds? _orientedBoundsForPolygon(
    _OrientedGeometry geometry,
    List<Offset> polygon,
  ) {
    if (!geometry.isValid || polygon.isEmpty) {
      return null;
    }

    double minU = double.infinity;
    double maxU = -double.infinity;
    double minV = double.infinity;
    double maxV = -double.infinity;

    for (final point in polygon) {
      final Offset aligned = geometry.toAligned(point);
      if (!aligned.dx.isFinite || !aligned.dy.isFinite) {
        continue;
      }
      if (aligned.dx < minU) minU = aligned.dx;
      if (aligned.dx > maxU) maxU = aligned.dx;
      if (aligned.dy < minV) minV = aligned.dy;
      if (aligned.dy > maxV) maxV = aligned.dy;
    }

    if (!minU.isFinite || !maxU.isFinite || !minV.isFinite || !maxV.isFinite) {
      return null;
    }

    if (maxU - minU < _kGeometryEpsilon) {
      final double mid = (maxU + minU) / 2;
      minU = mid - _kGeometryEpsilon;
      maxU = mid + _kGeometryEpsilon;
    }

    if (maxV - minV < _kGeometryEpsilon) {
      final double mid = (maxV + minV) / 2;
      minV = mid - _kGeometryEpsilon;
      maxV = mid + _kGeometryEpsilon;
    }

    return _OrientedBounds(minU: minU, maxU: maxU, minV: minV, maxV: maxV);
  }

  List<Offset> _getScaledCharacterPoints(CharacterBox character) {
    if (_displaySize == null || _displayOffset == null) {
      return const [];
    }

    final double scaleX = _displaySize!.width / widget.imageSize.width;
    final double scaleY = _displaySize!.height / widget.imageSize.height;

    return character.points
        .map(
          (point) => Offset(
            _displayOffset!.dx + (point.dx * scaleX),
            _displayOffset!.dy + (point.dy * scaleY),
          ),
        )
        .toList(growable: false);
  }

  Offset _interpolateOffset(Offset start, Offset end, double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    return Offset(
      start.dx + (end.dx - start.dx) * clamped,
      start.dy + (end.dy - start.dy) * clamped,
    );
  }

  void _clampAnchorsToVisuals() {
    if (_baseAnchor != null &&
        !_blockVisuals.containsKey(_baseAnchor!.blockIndex)) {
      _baseAnchor = null;
    } else if (_baseAnchor != null) {
      final visual = _blockVisuals[_baseAnchor!.blockIndex];
      if (visual != null) {
        final offset = _baseAnchor!.position.offset.clamp(
          0,
          visual.characterCount,
        );
        _baseAnchor = _SelectionAnchor(
          _baseAnchor!.blockIndex,
          TextPosition(offset: offset),
        );
      }
    }

    if (_extentAnchor != null &&
        !_blockVisuals.containsKey(_extentAnchor!.blockIndex)) {
      _extentAnchor = null;
    } else if (_extentAnchor != null) {
      final visual = _blockVisuals[_extentAnchor!.blockIndex];
      if (visual != null) {
        final offset = _extentAnchor!.position.offset.clamp(
          0,
          visual.characterCount,
        );
        _extentAnchor = _SelectionAnchor(
          _extentAnchor!.blockIndex,
          TextPosition(offset: offset),
        );
      }
    }
  }

  Map<int, TextSelection> _computeSelections(
    _SelectionAnchor? base,
    _SelectionAnchor? extent,
  ) {
    final result = <int, TextSelection>{};

    if (base == null || extent == null) {
      return result;
    }

    final int baseOrderIndex = _blockOrder.indexOf(base.blockIndex);
    final int extentOrderIndex = _blockOrder.indexOf(extent.blockIndex);
    if (baseOrderIndex == -1 || extentOrderIndex == -1) {
      return result;
    }

    var startAnchor = base;
    var endAnchor = extent;
    var startIndex = baseOrderIndex;
    var endIndex = extentOrderIndex;

    if (startIndex > endIndex) {
      startAnchor = extent;
      endAnchor = base;
      startIndex = extentOrderIndex;
      endIndex = baseOrderIndex;
    } else if (startIndex == endIndex &&
        endAnchor.position.offset < startAnchor.position.offset) {
      final temp = startAnchor;
      startAnchor = endAnchor;
      endAnchor = temp;
    }

    if (startAnchor.blockIndex == endAnchor.blockIndex &&
        startAnchor.position.offset == endAnchor.position.offset) {
      return result;
    }

    for (int i = startIndex; i <= endIndex; i++) {
      final blockIndex = _blockOrder[i];
      final visual = _blockVisuals[blockIndex];
      if (visual == null || visual.characterCount == 0) {
        continue;
      }

      int startOffset = 0;
      int endOffset = visual.characterCount;

      if (blockIndex == startAnchor.blockIndex) {
        startOffset = startAnchor.position.offset.clamp(
          0,
          visual.characterCount,
        );
      }
      if (blockIndex == endAnchor.blockIndex) {
        endOffset = endAnchor.position.offset.clamp(0, visual.characterCount);
      }

      if (blockIndex == startAnchor.blockIndex &&
          blockIndex == endAnchor.blockIndex) {
        final int minOffset = min(startOffset, endOffset);
        final int maxOffset = max(startOffset, endOffset);
        startOffset = minOffset;
        endOffset = maxOffset;
      }

      if (startOffset == endOffset) {
        continue;
      }

      result[blockIndex] = TextSelection(
        baseOffset: startOffset,
        extentOffset: endOffset,
      );
    }

    return result;
  }

  void _copySelectedText() {
    final text = _collectSelectionText();
    if (text.isEmpty) {
      return;
    }

    Clipboard.setData(ClipboardData(text: text));
    widget.onTextCopied?.call();
    HapticFeedback.mediumImpact();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _clearSelection();
    });
  }

  bool _selectAllText() {
    if (_blockOrder.isEmpty) {
      return false;
    }

    final Map<int, TextSelection> selections = <int, TextSelection>{};
    int? firstIndex;
    int? lastIndex;

    for (final index in _blockOrder) {
      final _BlockVisual? visual = _blockVisuals[index];
      if (visual == null || visual.characterCount == 0) {
        continue;
      }

      selections[index] = TextSelection(
        baseOffset: 0,
        extentOffset: visual.characterCount,
      );
      firstIndex ??= index;
      lastIndex = index;
    }

    if (selections.isEmpty || firstIndex == null || lastIndex == null) {
      _clearSelection();
      return false;
    }

    final int first = firstIndex;
    final int last = lastIndex;
    final int lastExtent = _blockVisuals[last]?.characterCount ?? 0;

    setState(() {
      _activeSelections = selections;
      _baseAnchor = _SelectionAnchor(first, const TextPosition(offset: 0));
      _extentAnchor = _SelectionAnchor(last, TextPosition(offset: lastExtent));
      _isSelecting = false;
      _activeHandle = null;
      _activeHandleTouchOffset = null;
    });

    HapticFeedback.selectionClick();
    return true;
  }

  bool _selectTextAtGlobalPosition(Offset globalPosition) {
    final scenePoint = _sceneFromGlobal(globalPosition);
    if (scenePoint == null) {
      return false;
    }
    final blockIndex =
        _hitTestBlock(scenePoint) ?? _nearestBlockIndex(scenePoint);
    if (blockIndex == null) {
      return false;
    }
    final bool selected = _performWordSelection(blockIndex, scenePoint);
    return selected;
  }

  void _clearSelection() {
    _clearPointerSelectionTracking();
    setState(() {
      _activeSelections = <int, TextSelection>{};
      _baseAnchor = null;
      _extentAnchor = null;
      _isSelecting = false;
      _activeHandle = null;
      _activeHandleTouchOffset = null;
    });
  }

  String _collectSelectionText() {
    final selectedIndices = _blockOrder
        .where((index) => _activeSelections.containsKey(index))
        .toList();
    if (selectedIndices.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    for (int i = 0; i < selectedIndices.length; i++) {
      final index = selectedIndices[i];
      final selection = _activeSelections[index]!;
      final visual = _blockVisuals[index];
      if (visual == null || visual.characterCount == 0) {
        continue;
      }

      final start = selection.start.clamp(0, visual.characterCount);
      final end = selection.end.clamp(start, visual.characterCount);
      if (start < end) {
        final segment = visual.characters
            .sublist(start, end)
            .map((character) => character.text)
            .join();
        buffer.write(segment);
      }

      if (i < selectedIndices.length - 1) {
        final currentRect = visual.bounds;
        final nextVisual = _blockVisuals[selectedIndices[i + 1]];
        if (nextVisual != null) {
          final nextRect = nextVisual.bounds;
          final bool sameLine =
              (nextRect.top - currentRect.top).abs() <
              min(currentRect.height, nextRect.height) * 0.6;
          buffer.write(sameLine ? ' ' : '\n');
        } else {
          buffer.write('\n');
        }
      }
    }

    return buffer.toString();
  }

  List<Offset> _getScaledPoints(TextBlock block) {
    if (_displaySize == null || _displayOffset == null) {
      return const [];
    }

    final double scaleX = _displaySize!.width / widget.imageSize.width;
    final double scaleY = _displaySize!.height / widget.imageSize.height;

    return block.points
        .map(
          (point) => Offset(
            _displayOffset!.dx + (point.dx * scaleX),
            _displayOffset!.dy + (point.dy * scaleY),
          ),
        )
        .toList(growable: false);
  }

  Rect _rectFromPoints(List<Offset> points) {
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;

    for (final point in points) {
      minX = min(minX, point.dx);
      maxX = max(maxX, point.dx);
      minY = min(minY, point.dy);
      maxY = max(maxY, point.dy);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _isRenderableRect(Rect rect) {
    return !rect.isEmpty && rect.width > _epsilon && rect.height > _epsilon;
  }

  int _clampIndex(int value, int minValue, int maxValue) {
    if (value < minValue) {
      return minValue;
    }
    if (value > maxValue) {
      return maxValue;
    }
    return value;
  }

  bool _pointInPolygon(List<Offset> polygon, Offset point) {
    if (polygon.length < 3) {
      return false;
    }

    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;

      final intersects =
          ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx <
              (xj - xi) *
                      (point.dy - yi) /
                      ((yj - yi).abs() < _epsilon ? _epsilon : (yj - yi)) +
                  xi);
      if (intersects) {
        inside = !inside;
      }
    }

    return inside;
  }

  bool _roughlyEqualsSize(Size a, Size b) {
    return (a.width - b.width).abs() < 0.5 && (a.height - b.height).abs() < 0.5;
  }

  bool _roughlyEqualsOffset(Offset a, Offset b) {
    return (a.dx - b.dx).abs() < 0.5 && (a.dy - b.dy).abs() < 0.5;
  }
}

class _SelectionAnchor {
  const _SelectionAnchor(this.blockIndex, this.position);

  final int blockIndex;
  final TextPosition position;
}

enum _HandleType { base, extent }

enum _GlyphCategory { whitespace, word, symbol }

const double _kGeometryEpsilon = 1e-6;

class _OrientedBounds {
  const _OrientedBounds({
    required this.minU,
    required this.maxU,
    required this.minV,
    required this.maxV,
  });

  final double minU;
  final double maxU;
  final double minV;
  final double maxV;

  Rect toRect() => Rect.fromLTRB(minU, minV, maxU, maxV);

  Rect inflate(double left, double right, double vertical) => Rect.fromLTRB(
    minU - left,
    minV - vertical,
    maxU + right,
    maxV + vertical,
  );
}

class _OrientedGeometry {
  _OrientedGeometry._({
    required this.axisX,
    required this.axisY,
    required this.translation,
    required this.forwardMatrix,
    required this.isValid,
  });

  final Offset axisX;
  final Offset axisY;
  final Offset translation;
  final Float64List forwardMatrix;
  final bool isValid;

  factory _OrientedGeometry.identity() {
    final identityMatrix = Float64List(16);
    identityMatrix[0] = 1.0;
    identityMatrix[5] = 1.0;
    identityMatrix[10] = 1.0;
    identityMatrix[15] = 1.0;
    return _OrientedGeometry._(
      axisX: const Offset(1, 0),
      axisY: const Offset(0, 1),
      translation: Offset.zero,
      forwardMatrix: identityMatrix,
      isValid: false,
    );
  }

  factory _OrientedGeometry.fromPolygon(List<Offset> polygon) {
    if (polygon.length < 2) {
      return _OrientedGeometry.identity();
    }

    Offset axisX = const Offset(1, 0);
    Offset basePoint = polygon.first;
    double longestEdgeLengthSquared = 0;

    for (int i = 0; i < polygon.length; i++) {
      final Offset current = polygon[i];
      final Offset next = polygon[(i + 1) % polygon.length];
      final Offset edge = next - current;
      final double lengthSquared = edge.dx * edge.dx + edge.dy * edge.dy;
      if (lengthSquared > longestEdgeLengthSquared) {
        final double length = sqrt(lengthSquared);
        if (length > _kGeometryEpsilon) {
          axisX = edge / length;
          basePoint = current;
          longestEdgeLengthSquared = lengthSquared;
        }
      }
    }

    if (longestEdgeLengthSquared <= _kGeometryEpsilon) {
      return _OrientedGeometry.identity();
    }

    Offset axisY = Offset(-axisX.dy, axisX.dx);
    final Offset centroid =
        polygon.reduce((a, b) => a + b) / polygon.length.toDouble();
    final Offset toCentroid = centroid - basePoint;
    if (toCentroid.dx * axisY.dx + toCentroid.dy * axisY.dy < 0) {
      axisY = Offset(-axisY.dx, -axisY.dy);
    }

    double minU = double.infinity;
    double minV = double.infinity;
    for (final point in polygon) {
      final double u = point.dx * axisX.dx + point.dy * axisX.dy;
      final double v = point.dx * axisY.dx + point.dy * axisY.dy;
      if (u < minU) minU = u;
      if (v < minV) minV = v;
    }

    if (!minU.isFinite || !minV.isFinite) {
      return _OrientedGeometry.identity();
    }

    final Offset translation = axisX * minU + axisY * minV;
    final Float64List matrix = Float64List(16);
    matrix[0] = axisX.dx;
    matrix[1] = axisX.dy;
    matrix[4] = axisY.dx;
    matrix[5] = axisY.dy;
    matrix[12] = translation.dx;
    matrix[13] = translation.dy;
    matrix[10] = 1.0;
    matrix[15] = 1.0;

    return _OrientedGeometry._(
      axisX: axisX,
      axisY: axisY,
      translation: translation,
      forwardMatrix: matrix,
      isValid: true,
    );
  }

  Offset toAligned(Offset point) {
    final Offset delta = point - translation;
    final double u = delta.dx * axisX.dx + delta.dy * axisX.dy;
    final double v = delta.dx * axisY.dx + delta.dy * axisY.dy;
    return Offset(u, v);
  }
}

class _CharacterVisual {
  const _CharacterVisual({
    required this.text,
    required this.confidence,
    required this.polygon,
    required this.bounds,
    required this.orientedBounds,
  });

  final String text;
  final double confidence;
  final List<Offset> polygon;
  final Rect bounds;
  final _OrientedBounds? orientedBounds;
}

class _BlockVisual {
  _BlockVisual({
    required this.index,
    required this.block,
    required this.scaledPolygon,
    required this.bounds,
    required this.characters,
    required this.geometry,
  });

  final int index;
  final TextBlock block;
  final List<Offset> scaledPolygon;
  final Rect bounds;
  final List<_CharacterVisual> characters;
  final _OrientedGeometry geometry;

  int get characterCount => characters.length;
}

class _DisplayMetrics {
  const _DisplayMetrics(this.size, this.offset);

  final Size size;
  final Offset offset;
}

class _ToolbarLayout {
  const _ToolbarLayout({required this.sceneRect, required this.screenSize});

  final Rect sceneRect;
  final Size screenSize;
}

class _EditableBlockPainter extends CustomPainter {
  const _EditableBlockPainter({
    required this.visual,
    required this.selectionColor,
    this.selection,
  });

  final _BlockVisual visual;
  final Color selectionColor;
  final TextSelection? selection;

  @override
  void paint(Canvas canvas, Size size) {
    if (selection != null && !selection!.isCollapsed) {
      final start = selection!.start.clamp(0, visual.characterCount);
      final end = selection!.end.clamp(start, visual.characterCount);
      if (start < end) {
        final highlightPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = selectionColor;
        final selected = <_CharacterVisual>[];
        for (int index = start; index < end; index++) {
          if (index >= visual.characters.length) break;
          final character = visual.characters[index];
          if (character.bounds.isEmpty) {
            continue;
          }
          selected.add(character);
        }
        if (selected.isNotEmpty) {
          final Path? rotatedPath = _buildRotatedHighlightPath(selected);
          if (rotatedPath != null) {
            canvas.drawPath(rotatedPath, highlightPaint);
          } else {
            for (final rrect in _buildAxisAlignedHighlightRegions(selected)) {
              canvas.drawRRect(rrect, highlightPaint);
            }
          }
        }
      }
    }
  }

  Path? _buildRotatedHighlightPath(List<_CharacterVisual> characters) {
    final _OrientedGeometry geometry = visual.geometry;
    if (!geometry.isValid) {
      return null;
    }

    final List<Rect> inflatedRects = <Rect>[];
    for (final character in characters) {
      final _OrientedBounds? oriented = character.orientedBounds;
      if (oriented == null) {
        return null;
      }
      inflatedRects.add(
        oriented.inflate(
          _kHighlightLeftPadding,
          _kHighlightRightPadding,
          _kHighlightVerticalPadding,
        ),
      );
    }

    final List<Rect> merged = _mergeSequentialRects(inflatedRects);
    if (merged.isEmpty) {
      return null;
    }

    final Path path = Path();
    for (final rect in merged) {
      path.addRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(_kHighlightCornerRadius),
        ),
      );
    }

    return path.transform(geometry.forwardMatrix);
  }

  List<RRect> _buildAxisAlignedHighlightRegions(
    List<_CharacterVisual> characters,
  ) {
    if (characters.isEmpty) {
      return const [];
    }

    final List<Rect> rects = <Rect>[];
    for (final character in characters) {
      rects.add(_inflateRect(character.bounds));
    }

    final List<Rect> merged = _mergeSequentialRects(rects);
    if (merged.isEmpty) {
      return const [];
    }

    return merged
        .map(
          (rect) => RRect.fromRectAndRadius(
            rect,
            const Radius.circular(_kHighlightCornerRadius),
          ),
        )
        .toList(growable: false);
  }

  List<Rect> _mergeSequentialRects(List<Rect> rects) {
    if (rects.isEmpty) {
      return const [];
    }

    final List<Rect> merged = <Rect>[];
    Rect? current;

    for (final rect in rects) {
      if (rect.isEmpty) {
        continue;
      }
      if (current == null) {
        current = rect;
        continue;
      }

      if (_isSameLine(current, rect)) {
        current = _mergeRects(current, rect);
      } else {
        merged.add(current);
        current = rect;
      }
    }

    if (current != null) {
      merged.add(current);
    }

    return merged;
  }

  Rect _inflateRect(Rect rect) {
    return _inflateRectBy(
      rect,
      _kHighlightLeftPadding,
      _kHighlightRightPadding,
      _kHighlightVerticalPadding,
    );
  }

  Rect _inflateRectBy(Rect rect, double left, double right, double vertical) {
    return Rect.fromLTRB(
      rect.left - left,
      rect.top - vertical,
      rect.right + right,
      rect.bottom + vertical,
    );
  }

  Rect _mergeRects(Rect a, Rect b) {
    return Rect.fromLTRB(
      min(a.left, b.left),
      min(a.top, b.top),
      max(a.right, b.right),
      max(a.bottom, b.bottom),
    );
  }

  bool _isSameLine(Rect a, Rect b) {
    final double verticalDiff = (a.center.dy - b.center.dy).abs();
    final double maxHeight = max(a.height, b.height);
    final double effectiveHeight = max(maxHeight, 1.0);
    return verticalDiff <= effectiveHeight * _kHighlightLineToleranceFactor;
  }

  @override
  bool shouldRepaint(covariant _EditableBlockPainter oldDelegate) {
    return oldDelegate.visual != visual || oldDelegate.selection != selection;
  }
}

// Reject hits outside text so PageView and the image viewer receive the gesture.
class _TextRegionHitTestBox extends SingleChildRenderObjectWidget {
  final bool Function(Offset globalPosition) hitTest;

  const _TextRegionHitTestBox({required this.hitTest, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTextRegionHitTestBox(hitTest);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTextRegionHitTestBox renderObject,
  ) {
    renderObject.hitTestCallback = hitTest;
  }
}

class _RenderTextRegionHitTestBox extends RenderProxyBox {
  bool Function(Offset globalPosition) hitTestCallback;

  _RenderTextRegionHitTestBox(this.hitTestCallback);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final global = localToGlobal(position);
    if (!hitTestCallback(global)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

// Reject long presses outside text so motion-photo playback can win.
class _TextRegionLongPressRecognizer extends LongPressGestureRecognizer {
  bool Function(Offset globalPosition) hitTestBlock;

  _TextRegionLongPressRecognizer({required this.hitTestBlock});

  Offset? _initialGlobalPosition;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _initialGlobalPosition = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void didExceedDeadline() {
    final pos = _initialGlobalPosition;
    if (pos != null && hitTestBlock(pos)) {
      super.didExceedDeadline();
    } else {
      resolve(GestureDisposition.rejected);
    }
  }
}
