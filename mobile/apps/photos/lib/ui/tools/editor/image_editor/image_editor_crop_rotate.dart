import 'dart:math';

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:flutter_svg/svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/tools/editor/image_editor/circular_icon_button.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_adjust_slider.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_configs_mixin.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_tune_bar.dart";
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/features/crop_rotate_editor/providers/tilt_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

enum CropAspectRatioType {
  original(
    label: "Original",
    ratio: null,
    svg: "assets/image-editor/image-editor-crop-original.svg",
  ),
  free(
    label: "Free",
    ratio: null,
    svg: "assets/video-editor/video-crop-free-action.svg",
  ),
  square(
    label: "1:1",
    ratio: 1.0,
    svg: "assets/video-editor/video-crop-ratio_1_1-action.svg",
  ),
  widescreen(
    label: "16:9",
    ratio: 16.0 / 9.0,
    svg: "assets/video-editor/video-crop-ratio_16_9-action.svg",
  ),
  portrait(
    label: "9:16",
    ratio: 9.0 / 16.0,
    svg: "assets/video-editor/video-crop-ratio_9_16-action.svg",
  ),
  photo(
    label: "4:3",
    ratio: 4.0 / 3.0,
    svg: "assets/video-editor/video-crop-ratio_4_3-action.svg",
  ),
  photo_3_4(
    label: "3:4",
    ratio: 3.0 / 4.0,
    svg: "assets/video-editor/video-crop-ratio_3_4-action.svg",
  );

  const CropAspectRatioType({
    required this.label,
    required this.ratio,
    required this.svg,
  });

  final String label;
  final String svg;
  final double? ratio;
}

enum _CropControl { none, crop, straighten }

class ImageEditorCropRotateBar extends StatefulWidget with SimpleConfigsAccess {
  const ImageEditorCropRotateBar({
    super.key,
    required this.configs,
    required this.callbacks,
    required this.editor,
  });
  final CropRotateEditorState editor;

  @override
  final ProImageEditorConfigs configs;

  @override
  final ProImageEditorCallbacks callbacks;

  @override
  State<ImageEditorCropRotateBar> createState() =>
      _ImageEditorCropRotateBarState();
}

class _ImageEditorCropRotateBarState extends State<ImageEditorCropRotateBar>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  CropAspectRatioType selectedAspectRatio = CropAspectRatioType.original;
  _CropControl selectedControl = _CropControl.crop;
  double? _lastStraightenAngle;
  double? _cachedBarHeight;
  double? _cachedActionWidth;
  TextScaler? _cachedTextScaler;
  Locale? _cachedLocale;

  double _barHeight(BuildContext context, double actionWidth) {
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.localeOf(context);
    if (_cachedBarHeight != null &&
        _cachedActionWidth == actionWidth &&
        _cachedTextScaler == textScaler &&
        _cachedLocale == locale) {
      return _cachedBarHeight!;
    }

    var labelHeight = 0.0;
    for (final label in [
      context.strings.crop,
      context.strings.straighten,
      context.strings.rotate,
      context.strings.flip,
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: TextStyles.body),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout(maxWidth: actionWidth);
      labelHeight = max(labelHeight, painter.height);
      painter.dispose();
    }

    _cachedActionWidth = actionWidth;
    _cachedTextScaler = textScaler;
    _cachedLocale = locale;
    return _cachedBarHeight = max(
      editorBottomBarHeight,
      60 + 8 + labelHeight + 40 + 24,
    );
  }

  void _handleStraightenTap(double angle) {
    if (selectedControl != _CropControl.straighten) {
      setState(() => selectedControl = _CropControl.straighten);
      return;
    }

    if (angle != 0) {
      _lastStraightenAngle = angle;
      widget.editor.tilt(TiltMode.rotate, 0);
    } else if (_lastStraightenAngle != null) {
      widget.editor.tilt(TiltMode.rotate, _lastStraightenAngle! * pi / 180);
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
    final colors = context.componentColors;
    final tiltConfigs = widget.configs.cropRotateEditor.tiltConfigs;
    final straightenAngle = TiltProvider.of(context).tiltRotate * 180 / pi;
    final actionWidth = min(90.0, constraints.maxWidth / 4);
    return BottomAppBar(
      color: colors.backgroundBase,
      padding: EdgeInsets.zero,
      height: _barHeight(context, actionWidth),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FadeInUp(
          duration: fadeInDuration,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularIconButton(
                    width: actionWidth,
                    hugeIcon: HugeIcons.strokeRoundedCrop,
                    label: context.strings.crop,
                    isSelected: selectedControl == _CropControl.crop,
                    onTap: () => setState(() {
                      selectedControl = selectedControl == _CropControl.crop
                          ? _CropControl.none
                          : _CropControl.crop;
                    }),
                  ),
                  GestureDetector(
                    onTap: () => _handleStraightenTap(straightenAngle),
                    child: SizedBox(
                      width: actionWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressWithValue(
                            value: straightenAngle,
                            min: tiltConfigs.tiltRotateMin,
                            max: tiltConfigs.tiltRotateMax,
                            icon: Icons.straighten,
                            hugeIcon: HugeIcons.strokeRoundedRuler,
                            progressColor: colors.primary,
                            isSelected:
                                selectedControl == _CropControl.straighten,
                            displayValueBuilder: (value) => value.round(),
                            valueSuffix: "°",
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.strings.straighten,
                            style: TextStyles.body.copyWith(
                              color: colors.textBase,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  CircularIconButton(
                    width: actionWidth,
                    hugeIcon: HugeIcons.strokeRoundedRotate02,
                    label: context.strings.rotate,
                    onTap: () {
                      widget.editor.rotate();
                    },
                  ),
                  CircularIconButton(
                    width: actionWidth,
                    hugeIcon: HugeIcons.strokeRoundedFlipLeft,
                    label: context.strings.flip,
                    onTap: () {
                      widget.editor.flip();
                    },
                  ),
                ],
              ),
              if (selectedControl == _CropControl.straighten)
                RepaintBoundary(
                  child: ImageEditorAdjustSlider(
                    min: tiltConfigs.tiltRotateMin,
                    max: tiltConfigs.tiltRotateMax,
                    value: straightenAngle.clamp(
                      tiltConfigs.tiltRotateMin,
                      tiltConfigs.tiltRotateMax,
                    ),
                    onChanged: (value) => widget.editor.tilt(
                      TiltMode.rotate,
                      value * pi / 180,
                      updateStateHistory: false,
                    ),
                    onChangeEnd: (value) =>
                        widget.editor.tilt(TiltMode.rotate, value * pi / 180),
                  ),
                )
              else if (selectedControl == _CropControl.crop)
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: CropAspectRatioType.values.length,
                    itemBuilder: (context, index) {
                      final aspectRatio = CropAspectRatioType.values[index];
                      final isSelected = selectedAspectRatio == aspectRatio;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
                        child: CropAspectChip(
                          label: aspectRatio.label,
                          svg: aspectRatio.svg,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              selectedAspectRatio = aspectRatio;
                            });
                            widget.editor.updateAspectRatio(
                              aspectRatio.ratio ?? -1,
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              if (selectedControl == _CropControl.none)
                const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class CropAspectChip extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String? svg;
  final bool isSelected;
  final VoidCallback? onTap;

  const CropAspectChip({
    super.key,
    this.label,
    this.icon,
    this.svg,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final selectedBackground = colors.fillBase.withValues(alpha: 0.9);
    final selectedForeground = colors.textReverse;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? selectedBackground : colors.fillLight,
          borderRadius: BorderRadius.circular(25),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (svg != null) ...[
              SvgPicture.asset(
                svg!,
                height: 32,
                colorFilter: ColorFilter.mode(
                  isSelected ? selectedForeground : colors.iconColor,
                  BlendMode.srcIn,
                ),
              ),
            ],
            const SizedBox(width: 4),
            if (label != null)
              Text(
                label!,
                style: TextStyles.body.copyWith(
                  color: isSelected ? selectedForeground : colors.iconColor,
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
