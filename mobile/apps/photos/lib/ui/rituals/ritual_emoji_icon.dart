import "dart:collection";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/widgets.dart";

class RitualEmojiIcon extends StatefulWidget {
  const RitualEmojiIcon(
    this.emoji, {
    super.key,
    required this.style,
    this.textHeightBehavior,
    this.textScaler,
  });

  final String emoji;
  final TextStyle style;
  final TextHeightBehavior? textHeightBehavior;
  final TextScaler? textScaler;

  @override
  State<RitualEmojiIcon> createState() => _RitualEmojiIconState();
}

class _RitualEmojiIconState extends State<RitualEmojiIcon> {
  static const int _cacheLimit = 256;
  static final LinkedHashMap<_EmojiCacheKey, Offset> _offsetCache =
      LinkedHashMap<_EmojiCacheKey, Offset>();
  static final Map<_EmojiCacheKey, Future<Offset>> _inFlight =
      <_EmojiCacheKey, Future<Offset>>{};

  Offset _offset = Offset.zero;
  _EmojiCacheKey? _activeKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveOffset();
  }

  @override
  void didUpdateWidget(RitualEmojiIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emoji != widget.emoji ||
        oldWidget.style != widget.style ||
        oldWidget.textHeightBehavior != widget.textHeightBehavior ||
        oldWidget.textScaler != widget.textScaler) {
      _resolveOffset(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedTextScaler =
        widget.textScaler ?? MediaQuery.textScalerOf(context);
    final resolvedStyle = DefaultTextStyle.of(
      context,
    ).style.merge(widget.style);

    return Transform.translate(
      offset: _offset,
      child: Text(
        widget.emoji,
        style: resolvedStyle,
        textScaler: resolvedTextScaler,
        textHeightBehavior: widget.textHeightBehavior,
      ),
    );
  }

  void _resolveOffset({bool reset = false}) {
    if (widget.emoji.isEmpty) {
      if (_offset != Offset.zero) {
        setState(() {
          _offset = Offset.zero;
        });
      }
      return;
    }

    final resolvedTextScaler =
        widget.textScaler ?? MediaQuery.textScalerOf(context);
    final resolvedStyle = DefaultTextStyle.of(
      context,
    ).style.merge(widget.style);
    final textDirection = Directionality.of(context);
    final measurementPixelRatio = MediaQuery.devicePixelRatioOf(
      context,
    ).clamp(2.0, 3.5);

    final key = _EmojiCacheKey(
      emoji: widget.emoji,
      style: resolvedStyle,
      textHeightBehavior: widget.textHeightBehavior,
      textDirection: textDirection,
      scale: resolvedTextScaler.scale(1),
      pixelRatio: measurementPixelRatio,
    );

    if (_activeKey == key && !reset) return;
    _activeKey = key;

    final cached = _getCachedOffset(key);
    if (cached != null) {
      if (_offset != cached) {
        setState(() {
          _offset = cached;
        });
      }
      return;
    }

    if (reset && _offset != Offset.zero) {
      setState(() {
        _offset = Offset.zero;
      });
    }

    _inFlight[key] ??=
        _computeVisualCenterOffset(
              emoji: widget.emoji,
              style: resolvedStyle,
              textDirection: textDirection,
              textScaler: resolvedTextScaler,
              textHeightBehavior: widget.textHeightBehavior,
              pixelRatio: measurementPixelRatio,
            )
            .then((offset) {
              _storeCachedOffset(key, offset);
              return offset;
            })
            .catchError((_) {
              _storeCachedOffset(key, Offset.zero);
              return Offset.zero;
            })
            .whenComplete(() {
              _inFlight.remove(key);
            });

    _inFlight[key]!.then((offset) {
      if (!mounted) return;
      if (_activeKey != key) return;
      if (_offset == offset) return;
      setState(() {
        _offset = offset;
      });
    });
  }

  Offset? _getCachedOffset(_EmojiCacheKey key) {
    final value = _offsetCache.remove(key);
    if (value == null) return null;
    _offsetCache[key] = value;
    return value;
  }

  void _storeCachedOffset(_EmojiCacheKey key, Offset offset) {
    _offsetCache.remove(key);
    _offsetCache[key] = offset;
    if (_offsetCache.length <= _cacheLimit) return;
    _offsetCache.remove(_offsetCache.keys.first);
  }
}

class _EmojiCacheKey {
  const _EmojiCacheKey({
    required this.emoji,
    required this.style,
    required this.textHeightBehavior,
    required this.textDirection,
    required this.scale,
    required this.pixelRatio,
  });

  final String emoji;
  final TextStyle style;
  final TextHeightBehavior? textHeightBehavior;
  final TextDirection textDirection;
  final double scale;
  final double pixelRatio;

  @override
  bool operator ==(Object other) {
    return other is _EmojiCacheKey &&
        emoji == other.emoji &&
        style == other.style &&
        textHeightBehavior == other.textHeightBehavior &&
        textDirection == other.textDirection &&
        scale == other.scale &&
        pixelRatio == other.pixelRatio;
  }

  @override
  int get hashCode => Object.hash(
    emoji,
    style,
    textHeightBehavior,
    textDirection,
    scale,
    pixelRatio,
  );
}

Future<Offset> _computeVisualCenterOffset({
  required String emoji,
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
  required TextHeightBehavior? textHeightBehavior,
  required double pixelRatio,
}) async {
  if (emoji.isEmpty) return Offset.zero;

  final painter = TextPainter(
    text: TextSpan(text: emoji, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    textHeightBehavior: textHeightBehavior,
  )..layout();

  final fontSize = style.fontSize ?? 14.0;
  final padding = (fontSize * 1.2).clamp(8.0, 24.0);
  final logicalSize = Size(
    painter.width + (padding * 2),
    painter.height + (padding * 2),
  );

  final scaledWidth = (logicalSize.width * pixelRatio).ceil();
  final scaledHeight = (logicalSize.height * pixelRatio).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio, pixelRatio);
  painter.paint(canvas, Offset(padding, padding));
  final picture = recorder.endRecording();

  final image = await picture.toImage(scaledWidth, scaledHeight);
  ByteData? byteData;
  try {
    byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    image.dispose();
  }
  if (byteData == null) return Offset.zero;

  final bounds = _opaquePixelBounds(
    bytes: byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    ),
    width: scaledWidth,
    height: scaledHeight,
  );
  if (bounds == null) return Offset.zero;

  final inkRect = Rect.fromLTRB(
    (bounds.left / pixelRatio) - padding,
    (bounds.top / pixelRatio) - padding,
    (bounds.right / pixelRatio) - padding,
    (bounds.bottom / pixelRatio) - padding,
  );

  final painterRect = Offset.zero & painter.size;
  return painterRect.center - inkRect.center;
}

Rect? _opaquePixelBounds({
  required Uint8List bytes,
  required int width,
  required int height,
}) {
  if (bytes.lengthInBytes < width * height * 4) return null;

  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;

  for (var y = 0; y < height; y++) {
    final rowStart = y * width * 4;
    for (var x = 0; x < width; x++) {
      final alpha = bytes[rowStart + (x * 4) + 3];
      if (alpha == 0) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < 0 || maxY < 0) return null;

  return Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    (maxX + 1).toDouble(),
    (maxY + 1).toDouble(),
  );
}
