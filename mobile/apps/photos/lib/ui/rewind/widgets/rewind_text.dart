import "package:flutter/material.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";

class RewindOutlinedText extends StatelessWidget {
  const RewindOutlinedText(
    this.text, {
    required this.style,
    this.outline = 3,
    this.shadow = Offset.zero,
    this.ink = RewindColors.ink,
    this.textAlign = TextAlign.left,
    super.key,
  });

  final String text;
  final TextStyle style;
  final double outline;
  final Offset shadow;
  final Color ink;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final stroke = style.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline * 2
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    );
    Text layer(TextStyle style) =>
        Text(text, style: style, textAlign: textAlign, softWrap: false);
    return Stack(
      children: [
        if (shadow != Offset.zero) ...[
          Positioned.fill(
            child: Transform.translate(
              offset: shadow,
              child: layer(style.copyWith(color: ink)),
            ),
          ),
          Positioned.fill(
            child: Transform.translate(offset: shadow, child: layer(stroke)),
          ),
        ],
        if (outline > 0) Positioned.fill(child: layer(stroke)),
        layer(style),
      ],
    );
  }
}

class RewindCallout extends StatelessWidget {
  const RewindCallout(this.text, {this.size = 38.72, super.key});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return RewindOutlinedText(
      text,
      style: RewindTextStyles.display(
        size,
        color: RewindColors.white,
        height: 0.84,
      ),
      outline: 3 * size / 38.72,
      shadow: Offset(0.037 * size, 0.044 * size),
    );
  }
}

class RewindFitWidth extends StatelessWidget {
  const RewindFitWidth({
    required this.width,
    required this.child,
    this.alignment = Alignment.centerLeft,
    super.key,
  });

  final double width;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: child,
      ),
    );
  }
}
