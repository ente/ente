import "dart:math" as math;
import "dart:ui" show ImageFilter, lerpDouble;

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart" show NumberFormat;
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/people/memory_lane_now_caption.dart";

class MemoryLaneCaption extends StatefulWidget {
  const MemoryLaneCaption({
    required this.caption,
    required this.name,
    required this.value,
    this.duration = const Duration(milliseconds: 600),
    super.key,
  });

  static const namePlaceholder = "\uFFF9";
  static const timePlaceholder = "\uFFFC";

  final String caption;
  final String name;
  final int? value;
  final Duration duration;

  static TextStyle get numberStyle =>
      darkTheme.textTheme.h2Bold.copyWith(fontSize: 28.16);

  @override
  State<MemoryLaneCaption> createState() => _MemoryLaneCaptionState();
}

class _MemoryLaneCaptionState extends State<MemoryLaneCaption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late MemoryLaneCaption _previous;
  Object? _layoutKey;
  Object? _dependencies;
  _CaptionLayout? _oldLayout;
  _CaptionLayout? _newLayout;
  Map<String, Rect> _positions = {};
  Map<String, Rect> _origins = {};
  double? _height;
  double? _originHeight;

  @override
  void initState() {
    super.initState();
    _previous = widget;
    _controller = AnimationController(vsync: this, value: 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = (
      context.strings.localeName,
      Directionality.of(context),
      MediaQuery.textScalerOf(context),
      MediaQuery.disableAnimationsOf(context),
    );
    if (_dependencies != dependencies) {
      _previous = widget;
      _controller.value = 1;
      _origins = {};
      _originHeight = null;
      _dependencies = dependencies;
    }
  }

  @override
  void didUpdateWidget(MemoryLaneCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caption == widget.caption &&
        oldWidget.name == widget.name &&
        oldWidget.value == widget.value) {
      return;
    }
    _previous = oldWidget;
    _origins = Map.of(_positions);
    _originHeight = _height;
    _controller.duration = widget.duration;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _oldLayout?.dispose();
    _newLayout?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final layoutKey = (width, _dependencies, _previous, widget);
        if (_layoutKey != layoutKey) {
          _oldLayout?.dispose();
          _newLayout?.dispose();
          _oldLayout = _CaptionLayout(_previous, context, width);
          _newLayout = _CaptionLayout(widget, context, width);
          _layoutKey = layoutKey;
        }
        final old = _oldLayout!;
        final next = _newLayout!;
        return Semantics(
          label: next.label,
          excludeSemantics: true,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final progress = Curves.easeOutCubic.transform(_controller.value);
              final height = lerpDouble(
                _originHeight ?? old.height,
                next.height,
                progress,
              )!;
              _height = height;
              if (!old.canSplit || !next.canSplit) {
                _positions = {};
                return SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (progress < 1)
                        _wholeCaption(old, 1 - progress, height),
                      _wholeCaption(next, progress, height),
                    ],
                  ),
                );
              }
              final children = <Widget>[];
              final positions = <String, Rect>{};
              for (final part in next.parts) {
                final before = old.parts
                    .where((item) => item.key == part.key)
                    .firstOrNull;
                final target = next.rect(part);
                final origin = before == null
                    ? target
                    : _origins[part.key] ?? old.rect(before);
                final rect = Rect.lerp(origin, target, progress)!;
                positions[part.key] = rect;
                if (part.isTime &&
                    before != null &&
                    _previous.value != null &&
                    widget.value != null) {
                  children.add(
                    _position(
                      part.key,
                      rect,
                      _number(next, part, widget.value!),
                    ),
                  );
                } else if (before != null &&
                    before.text == part.text &&
                    before.isTime == part.isTime &&
                    (!part.isTime || _previous.value == widget.value)) {
                  children.add(_position(part.key, rect, next.fragment(part)));
                } else {
                  if (before != null && progress < 1) {
                    children.add(
                      _position(
                        "old-${part.key}",
                        rect,
                        _blend(
                          before.isTime && _previous.value != null
                              ? _number(old, before, _previous.value!)
                              : old.fragment(before),
                          1 - progress,
                          part.isTime ? 1 - progress * 0.3 : 1,
                          part.isTime ? progress * 4 : progress * 1.5,
                        ),
                      ),
                    );
                  }
                  children.add(
                    _position(
                      part.key,
                      rect,
                      _blend(
                        part.isTime && widget.value != null
                            ? _number(next, part, widget.value!)
                            : next.fragment(part),
                        progress,
                        part.isTime ? 0.72 + progress * 0.28 : 1,
                        (1 - progress) * (part.isTime ? 4 : 1.5),
                      ),
                    ),
                  );
                }
              }
              for (final part in old.parts) {
                if (next.parts.any((item) => item.key == part.key) ||
                    progress == 1) {
                  continue;
                }
                children.add(
                  _position(
                    "old-${part.key}",
                    old.rect(part),
                    _blend(old.fragment(part), 1 - progress, 1, progress),
                  ),
                );
              }
              _positions = positions;
              return SizedBox(
                width: width,
                height: height,
                child: Stack(clipBehavior: Clip.none, children: children),
              );
            },
          ),
        );
      },
    );
  }

  Widget _wholeCaption(_CaptionLayout layout, double opacity, double height) {
    return Positioned(
      left: layout.left,
      top: height - layout.height,
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          size: layout.painter.size,
          painter: _CaptionPainter(layout.painter),
        ),
      ),
    );
  }

  Widget _position(String key, Rect rect, Widget child) => Positioned.fromRect(
    key: ValueKey("memory-lane-caption-$key"),
    rect: rect,
    child: child,
  );

  Widget _number(_CaptionLayout layout, _CaptionPart part, int value) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: layout.baseline - part.box!.top - layout.numberBaseline,
          height: layout.numberHeight,
          child: OverflowBox(
            minWidth: 0,
            maxWidth: double.infinity,
            child: _MemoryLaneAnimatedDigit(value: value),
          ),
        ),
      ],
    );
  }

  Widget _blend(Widget child, double opacity, double scale, double blur) {
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          enabled: blur > 0,
          child: child,
        ),
      ),
    );
  }
}

class _CaptionLayout {
  _CaptionLayout(
    MemoryLaneCaption caption,
    BuildContext context,
    double width,
  ) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final time = caption.value == null
        ? context.strings.memoryLaneNow
        : NumberFormat.decimalPattern(
            context.strings.localeName,
          ).format(caption.value);
    final template = caption.name.isEmpty && caption.value == null
        ? MemoryLaneCaption.timePlaceholder
        : caption.caption.trim();
    label = template
        .replaceAll(MemoryLaneCaption.namePlaceholder, caption.name)
        .replaceAll(MemoryLaneCaption.timePlaceholder, time)
        .trim();
    final timeStyle = caption.value == null
        ? MemoryLaneNowCaption.textStyle
        : MemoryLaneCaption.numberStyle;
    TextPainter measure(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: Localizations.localeOf(context),
    )..layout();
    final rest = measure(
      template
          .replaceAll(MemoryLaneCaption.namePlaceholder, "")
          .replaceAll(MemoryLaneCaption.timePlaceholder, ""),
      darkTheme.textTheme.bodyMuted,
    );
    final timeMeasure = measure(time, timeStyle);
    final nameBudget = math.max(
      width * 0.35,
      width - rest.width - timeMeasure.width,
    );
    rest.dispose();
    timeMeasure.dispose();
    var name = caption.name;
    final nameMeasure = measure(name, darkTheme.textTheme.bodyMuted);
    if (nameMeasure.width > nameBudget) {
      final graphemes = name.characters.toList();
      var low = 0;
      var high = graphemes.length;
      while (low < high) {
        final count = (low + high + 1) ~/ 2;
        nameMeasure.text = TextSpan(
          text: "${graphemes.take(count).join()}…",
          style: darkTheme.textTheme.bodyMuted,
        );
        nameMeasure.layout();
        if (nameMeasure.width <= nameBudget) {
          low = count;
        } else {
          high = count - 1;
        }
      }
      name = "${graphemes.take(low).join()}…";
    }
    nameMeasure.dispose();
    final spans = <TextSpan>[];
    var cursor = 0;
    var offset = 0;
    var literal = 0;
    var times = 0;
    var names = 0;
    void add(
      String key,
      String text, {
      bool isTime = false,
      bool isolate = false,
    }) {
      if (text.isEmpty) return;
      final start = offset + (isolate ? 1 : 0);
      spans.add(
        TextSpan(
          text: isolate ? "\u2068$text\u2069" : text,
          style: isTime ? timeStyle : null,
        ),
      );
      parts.add(_CaptionPart(key, text, start, start + text.length, isTime));
      offset += text.length + (isolate ? 2 : 0);
    }

    for (final match in RegExp("[\uFFF9\uFFFC]").allMatches(template)) {
      add("literal-${literal++}", template.substring(cursor, match.start));
      if (match.group(0) == MemoryLaneCaption.namePlaceholder) {
        add("name-${names++}", name, isolate: true);
      } else {
        add("time-${times++}", time, isTime: true, isolate: true);
      }
      cursor = match.end;
    }
    add("literal-$literal", template.substring(cursor));
    painter = TextPainter(
      text: TextSpan(style: darkTheme.textTheme.bodyMuted, children: spans),
      textDirection: direction,
      textScaler: scaler,
      locale: Localizations.localeOf(context),
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: width);
    if (painter.didExceedMaxLines) {
      painter
        ..maxLines = 2
        ..textAlign = TextAlign.center
        ..layout(maxWidth: width);
    }
    left = (width - painter.width) / 2;
    baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final number = measure(time, MemoryLaneCaption.numberStyle);
    numberBaseline = number.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    numberHeight = number.height;
    number.dispose();
    canSplit =
        !painter.didExceedMaxLines && painter.computeLineMetrics().length == 1;
    for (final part in parts) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: part.start, extentOffset: part.end),
      );
      if (boxes.length != 1) {
        canSplit = false;
      } else {
        part.box = boxes.single.toRect();
      }
    }
  }

  late final TextPainter painter;
  final List<_CaptionPart> parts = [];
  late final String label;
  late final double left;
  late final double baseline;
  late final double numberBaseline;
  late final double numberHeight;
  late bool canSplit;
  double get height => painter.height;
  Rect rect(_CaptionPart part) => Rect.fromLTWH(
    left + part.box!.left,
    part.box!.top,
    part.box!.width,
    part.box!.height,
  );
  Widget fragment(_CaptionPart part) =>
      CustomPaint(painter: _CaptionPainter(painter, clip: part.box));
  void dispose() => painter.dispose();
}

class _CaptionPart {
  _CaptionPart(this.key, this.text, this.start, this.end, this.isTime);
  final String key;
  final String text;
  final int start;
  final int end;
  final bool isTime;
  Rect? box;
}

class _CaptionPainter extends CustomPainter {
  const _CaptionPainter(this.text, {this.clip});
  final TextPainter text;
  final Rect? clip;

  @override
  void paint(Canvas canvas, Size size) {
    if (clip == null) {
      text.paint(canvas, Offset.zero);
      return;
    }
    // Crop the shaped paragraph to preserve glyph joining in translations.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clip!.width, clip!.height));
    text.paint(canvas, Offset(-clip!.left, -clip!.top));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CaptionPainter oldDelegate) =>
      oldDelegate.text != text || oldDelegate.clip != clip;
}

class _MemoryLaneAnimatedDigit extends StatefulWidget {
  const _MemoryLaneAnimatedDigit({required this.value}) : assert(value >= 0);

  final int value;

  @override
  State<_MemoryLaneAnimatedDigit> createState() =>
      _MemoryLaneAnimatedDigitState();
}

class _MemoryLaneAnimatedDigitState extends State<_MemoryLaneAnimatedDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(_MemoryLaneAnimatedDigit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _previousValue = oldWidget.value;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.value >= _previousValue ? 1 : -1;
    final formatter = NumberFormat.decimalPattern(context.strings.localeName);
    final current = formatter.format(widget.value);
    final previous = formatter.format(_previousValue);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: current,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = disableAnimations
              ? 1.0
              : Curves.easeOutCubic.transform(_controller.value);
          final length = progress == 1
              ? current.length
              : math.max(current.length, previous.length);
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            textDirection: TextDirection.ltr,
            children: [
              for (var place = length - 1; place >= 0; place--)
                Builder(
                  key: ValueKey(place),
                  builder: (context) {
                    final nextDigit = place < current.length
                        ? current[current.length - place - 1]
                        : null;
                    final oldDigit = place < previous.length
                        ? previous[previous.length - place - 1]
                        : null;
                    if (progress == 1 || oldDigit == nextDigit) {
                      return Text(
                        nextDigit ?? "",
                        style: MemoryLaneCaption.numberStyle,
                      );
                    }
                    return ClipRect(
                      child: Align(
                        widthFactor: nextDigit == null
                            ? 1 - progress
                            : oldDigit == null
                            ? progress
                            : 1,
                        child: ClipRect(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (oldDigit != null)
                                FractionalTranslation(
                                  translation: Offset(0, -direction * progress),
                                  child: Text(
                                    oldDigit,
                                    style: MemoryLaneCaption.numberStyle,
                                  ),
                                ),
                              if (nextDigit != null)
                                FractionalTranslation(
                                  translation: Offset(
                                    0,
                                    direction * (1 - progress),
                                  ),
                                  child: Text(
                                    nextDigit,
                                    style: MemoryLaneCaption.numberStyle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
