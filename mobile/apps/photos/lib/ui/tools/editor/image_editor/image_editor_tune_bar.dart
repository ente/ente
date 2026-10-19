import 'dart:math';

import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:flutter_svg/svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_adjust_slider.dart";
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
                        id: item.id,
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

                  return ImageEditorAdjustSlider(
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
  final String id;
  final IconData icon;
  final String label;
  final bool isSelected;
  final double value;
  final double min;
  final double max;
  final VoidCallback onTap;

  const TuneItem({
    super.key,
    required this.id,
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
    final hugeIcon = _hugeIconForID(id);
    final svgPath = _svgPathForID(id);
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

  List<List<dynamic>>? _hugeIconForID(String id) {
    return switch (id) {
      "brightness" => HugeIcons.strokeRoundedSun01,
      "contrast" => HugeIcons.strokeRoundedSlidersHorizontal,
      "exposure" => HugeIcons.strokeRoundedCameraLens,
      "saturation" => HugeIcons.strokeRoundedDroplet,
      "temperature" => HugeIcons.strokeRoundedTemperature,
      "hue" => HugeIcons.strokeRoundedColors,
      _ => null,
    };
  }

  String? _svgPathForID(String id) {
    return switch (id) {
      "fade" => "assets/image-editor/image-editor-fade.svg",
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
  final int Function(double)? displayValueBuilder;
  final String valueSuffix;

  const CircularProgressWithValue({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.icon,
    this.hugeIcon,
    this.svgPath,
    this.displayValueBuilder,
    this.valueSuffix = "",
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
      HapticFeedback.selectionClick();
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
      return (value.abs() / max.abs()).clamp(0.0, 1.0);
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
    final displayValue =
        widget.displayValueBuilder?.call(widget.value) ??
        _normalizeValueForDisplay(widget.value, widget.min, widget.max);
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
                    "$prefix$displayText${widget.valueSuffix}",
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
