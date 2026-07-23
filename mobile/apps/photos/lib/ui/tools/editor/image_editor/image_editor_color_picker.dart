import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

class ImageEditorColorPicker extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const ImageEditorColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  ColorSliderState createState() => ColorSliderState();
}

class ColorSliderState extends State<ImageEditorColorPicker> {
  Color get _selectedColor {
    final hue = widget.value * 360;
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFF8000),
                    Color(0xFFFFFF00),
                    Color(0xFF80FF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FF80),
                    Color(0xFF00FFFF),
                    Color(0xFF0080FF),
                    Color(0xFF0000FF),
                    Color(0xFF8000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0080),
                    Color(0xFFFF0000),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                border: Border.all(color: colors.fillLight, width: 6),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 36,
                  thumbShape: _CustomThumbShape(_selectedColor),
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                  trackShape: const _TransparentTrackShape(),
                ),
                child: Slider(
                  value: widget.value,
                  onChanged: widget.onChanged,
                  min: 0.0,
                  max: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomThumbShape extends SliderComponentShape {
  final Color color;

  const _CustomThumbShape(this.color);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(28, 28);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final Paint thumbPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 11, thumbPaint);

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, 13, borderPaint);
  }
}

class _TransparentTrackShape extends SliderTrackShape {
  const _TransparentTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight!;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {}
}
