import 'dart:math';

import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:flutter_svg/svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_configs_mixin.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditorTuneBar extends StatefulWidget with SimpleConfigsAccess {
  const ImageEditorTuneBar({
    super.key,
    required this.configs,
    required this.callbacks,
    required this.editor,
  });

  final TuneEditorState editor;

  @override
  final ProImageEditorConfigs configs;

  @override
  final ProImageEditorCallbacks callbacks;

  @override
  State<ImageEditorTuneBar> createState() => _ImageEditorTuneBarState();
}

class _ImageEditorTuneBarState extends State<ImageEditorTuneBar>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  TuneEditorState get tuneEditor => widget.editor;

  final Map<int, double> _lastValues = {};

  void _handleTuneItemTap(int index) {
    if (tuneEditor.selectedIndex == index) {
      final currentValue = tuneEditor.tuneAdjustmentMatrix[index].value;
      if (currentValue != 0) {
        _lastValues[index] = currentValue;
        tuneEditor.onChanged(0);
      } else if (_lastValues.containsKey(index)) {
        tuneEditor.onChanged(_lastValues[index]!);
      }
    } else {
      tuneEditor.setState(() {
        tuneEditor.selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildFunctions(constraints)],
        );
      },
    );
  }

  Widget _buildFunctions(BoxConstraints constraints) {
    return SizedBox(
      width: double.infinity,
      height: editorBottomBarHeight,
      child: FadeInUp(
        duration: fadeInDuration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              height: 90,
              child: SingleChildScrollView(
                controller: tuneEditor.bottomBarScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    tuneEditor.tuneAdjustmentMatrix.length,
                    (index) {
                      final item = tuneEditor.tuneAdjustmentList[index];
                      return TuneItem(
                        icon: item.icon,
                        label: item.label,
                        isSelected: tuneEditor.selectedIndex == index,
                        value: tuneEditor.tuneAdjustmentMatrix[index].value,
                        max: item.max,
                        min: item.min,
                        onTap: () => _handleTuneItemTap(index),
                      );
                    },
                  ),
                ),
              ),
            ),
            RepaintBoundary(
              child: StreamBuilder(
                stream: tuneEditor.uiStream.stream,
                builder: (context, snapshot) {
                  final activeOption =
                      tuneEditor.tuneAdjustmentList[tuneEditor.selectedIndex];
                  final activeMatrix =
                      tuneEditor.tuneAdjustmentMatrix[tuneEditor.selectedIndex];

                  return _TuneAdjustWidget(
                    min: activeOption.min,
                    max: activeOption.max,
                    value: activeMatrix.value,
                    onChanged: tuneEditor.onChanged,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TuneItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final double value;
  final double min;
  final double max;
  final VoidCallback onTap;

  const TuneItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.value,
    required this.min,
    required this.max,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hugeIcon = _hugeIconForLabel(label);
    final svgPath = _svgPathForLabel(label);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 90,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressWithValue(
              value: value,
              min: min,
              max: max,
              size: 60,
              icon: icon,
              hugeIcon: hugeIcon,
              svgPath: svgPath,
              isSelected: isSelected,
              progressColor: colors.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyles.body.copyWith(color: colors.textBase),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<List<dynamic>>? _hugeIconForLabel(String label) {
    return switch (label.toLowerCase()) {
      "brightness" => HugeIcons.strokeRoundedSun01,
      "contrast" => HugeIcons.strokeRoundedSlidersHorizontal,
      "exposure" => HugeIcons.strokeRoundedCameraLens,
      "saturation" => HugeIcons.strokeRoundedDroplet,
      "temperature" => HugeIcons.strokeRoundedTemperature,
      "sharpness" => HugeIcons.strokeRoundedFocusPoint,
      "hue" => HugeIcons.strokeRoundedColors,
      _ => null,
    };
  }

  String? _svgPathForLabel(String label) {
    return switch (label.toLowerCase()) {
      "luminance" ||
      "fade" => "assets/image-editor/image-editor-${label.toLowerCase()}.svg",
      _ => null,
    };
  }
}

class CircularProgressWithValue extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final IconData icon;
  final List<List<dynamic>>? hugeIcon;
  final bool isSelected;
  final double size;
  final Color progressColor;
  final String? svgPath;

  const CircularProgressWithValue({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.icon,
    this.hugeIcon,
    this.svgPath,
    required this.progressColor,
    this.isSelected = false,
    this.size = 60,
  });

  @override
  State<CircularProgressWithValue> createState() =>
      _CircularProgressWithValueState();
}

class _CircularProgressWithValueState extends State<CircularProgressWithValue>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;
  double _previousValue = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      animationBehavior: AnimationBehavior.preserve,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: widget.value).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();
  }

  @override
  void didUpdateWidget(CircularProgressWithValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.value < 0 && widget.value >= 0) ||
        (oldWidget.value > 0 && widget.value <= 0)) {
      HapticFeedback.vibrate();
    }
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value;
      _progressAnimation =
          Tween<double>(begin: _previousValue, end: widget.value).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeInOut,
            ),
          );
      _animationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  int _normalizeValueForDisplay(double value, double min, double max) {
    if (min == -0.5 && max == 0.5) {
      return (value * 200).round();
    } else if (min == 0 && max == 1) {
      return (value * 100).round();
    } else if (min == -0.25 && max == 0.25) {
      return (value * 400).round();
    } else {
      return (value * 100).round();
    }
  }

  double _normalizeValueForProgress(double value, double min, double max) {
    if (min == -0.5 && max == 0.5) {
      return (value.abs() / 0.5).clamp(0.0, 1.0);
    } else if (min == 0 && max == 1) {
      return (value / 1.0).clamp(0.0, 1.0);
    } else if (min == -0.25 && max == 0.25) {
      return (value.abs() / 0.25).clamp(0.0, 1.0);
    } else {
      return (value.abs() / 1.0).clamp(0.0, 1.0);
    }
  }

  bool _isClockwise(double value, double min, double max) {
    if (min >= 0) {
      return true;
    } else {
      return value >= 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final displayValue = _normalizeValueForDisplay(
      widget.value,
      widget.min,
      widget.max,
    );
    final displayText = displayValue.toString();
    final prefix = displayValue > 0 ? "+" : "";
    final progressColor = widget.progressColor;

    final showValue = displayValue != 0 || widget.isSelected;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: showValue || widget.isSelected
                  ? progressColor.withValues(alpha: 0.2)
                  : colors.fillLight,
              border: Border.all(
                color: widget.isSelected
                    ? progressColor.withValues(alpha: 0.4)
                    : colors.fillLight,
                width: 2,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              final animatedValue = displayValue == 0
                  ? 0.0
                  : _progressAnimation.value;

              final isClockwise = _isClockwise(
                animatedValue,
                widget.min,
                widget.max,
              );
              final progressValue = _normalizeValueForProgress(
                animatedValue,
                widget.min,
                widget.max,
              );

              return SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: CircularProgressPainter(
                    progress: progressValue,
                    isClockwise: isClockwise,
                    color: progressColor,
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.center,
            child: showValue
                ? Text(
                    "$prefix$displayText",
                    style: TextStyles.bodyBold.copyWith(color: colors.textBase),
                  )
                : widget.svgPath != null
                ? SvgPicture.asset(
                    widget.svgPath!,
                    width: 22,
                    height: 22,
                    fit: BoxFit.scaleDown,
                    colorFilter: ColorFilter.mode(
                      colors.iconColor,
                      BlendMode.srcIn,
                    ),
                  )
                : widget.hugeIcon != null
                ? HugeIcon(
                    icon: widget.hugeIcon!,
                    color: colors.iconColor,
                    size: 22,
                  )
                : Icon(widget.icon, color: colors.iconColor, size: 20),
          ),
        ],
      ),
    );
  }
}

class _TuneAdjustWidget extends StatelessWidget {
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;

  const _TuneAdjustWidget({
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: colors.fillLight,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(25)),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const _ColorPickerThumbShape(),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                activeTrackColor: colors.primary,
                inactiveTrackColor: colors.fillLight,
                trackShape: const _CenterBasedTrackShape(),
                trackHeight: 24,
              ),
              child: Slider(
                value: value,
                onChanged: onChanged,
                min: min,
                max: max,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 38),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.fillBase.withAlpha(30),
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.fillBase.withAlpha(30),
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.fillBase.withAlpha(30),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorPickerThumbShape extends SliderComponentShape {
  const _ColorPickerThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(20, 20);
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
    required Size sizeWithOverflow,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double textScaleFactor,
    required double value,
  }) {
    final canvas = context.canvas;

    final trackRect = sliderTheme.trackShape!.getPreferredRect(
      parentBox: parentBox,
      offset: Offset.zero,
      sliderTheme: sliderTheme,
      isEnabled: true,
      isDiscrete: isDiscrete,
    );

    final constrainedCenter = Offset(
      center.dx.clamp(trackRect.left + 15, trackRect.right - 15),
      center.dy,
    );

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(constrainedCenter, 15, paint);

    final innerPaint = Paint()
      ..color = const Color.fromRGBO(8, 194, 37, 1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(constrainedCenter, 12.5, innerPaint);
  }
}

class _CenterBasedTrackShape extends SliderTrackShape {
  const _CenterBasedTrackShape();

  static const double horizontalPadding = 6.0;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 8;
    final double trackLeft = offset.dx + horizontalPadding;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width - (horizontalPadding * 2);
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
    bool isEnabled = false,
    bool isDiscrete = false,
    double? additionalActiveTrackHeight,
  }) {
    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double centerX = trackRect.left + trackRect.width / 2;

    final double clampedThumbDx = thumbCenter.dx.clamp(
      trackRect.left,
      trackRect.right,
    );

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor!
      ..style = PaintingStyle.fill;

    final RRect inactiveRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(trackRect.height / 2),
    );

    canvas.drawRRect(inactiveRRect, inactivePaint);

    if (clampedThumbDx != centerX) {
      final Paint activePaint = Paint()
        ..color = sliderTheme.activeTrackColor!
        ..style = PaintingStyle.fill;

      final Rect activeRect = clampedThumbDx >= centerX
          ? Rect.fromLTWH(
              centerX,
              trackRect.top,
              clampedThumbDx - centerX,
              trackRect.height,
            )
          : Rect.fromLTWH(
              clampedThumbDx,
              trackRect.top,
              centerX - clampedThumbDx,
              trackRect.height,
            );

      final RRect activeRRect = RRect.fromRectAndRadius(
        activeRect,
        Radius.circular(trackRect.height / 2),
      );

      canvas.drawRRect(activeRRect, activePaint);
    }
  }
}

class CircularProgressPainter extends CustomPainter {
  final double progress;
  final bool isClockwise;
  final Color color;

  CircularProgressPainter({
    required this.progress,
    required this.isClockwise,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final backgroundPaint = Paint()
      ..color = Colors.transparent
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final foregroundPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    if (progress > 0) {
      const startAngle = -pi / 2;
      final sweepAngle = 2 * pi * progress * (isClockwise ? 1 : -1);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        foregroundPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
