import 'package:flutter/material.dart';
import "package:photos/ui/tools/editor/video_editor/crop_value.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_bottom_action.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_controller.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_main_actions.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_widgets.dart";

class VideoCropPage extends StatefulWidget {
  const VideoCropPage({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  State<VideoCropPage> createState() => _VideoCropPageState();
}

class _VideoCropPageState extends State<VideoCropPage> {
  CropValue? _selectedCropValue;

  @override
  void initState() {
    super.initState();
    _initializeSelectedValue();
  }

  void _initializeSelectedValue() {
    final currentRatio = widget.controller.preferredCropAspectRatio;
    if (currentRatio == null) {
      _selectedCropValue = CropValue.free;
      return;
    }

    for (final value in CropValue.values) {
      if (value == CropValue.original || value == CropValue.free) continue;

      final valueRatio = value.getFraction()?.toDouble();
      if (valueRatio == null) continue;

      if ((currentRatio - valueRatio).abs() < 0.01) {
        _selectedCropValue = value;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return VideoEditorSubPage(
      controller: widget.controller,
      preview: VideoCropEditor(controller: widget.controller),
      actions: AnimatedBuilder(
        animation: widget.controller,
        builder: (_, _) => VideoEditorMainActions(
          children: [
            _buildCropButton(context, CropValue.free),
            const SizedBox(width: 24),
            _buildCropButton(context, CropValue.ratio_1_1),
            const SizedBox(width: 24),
            _buildCropButton(context, CropValue.ratio_9_16),
            const SizedBox(width: 24),
            _buildCropButton(context, CropValue.ratio_16_9),
            const SizedBox(width: 24),
            _buildCropButton(context, CropValue.ratio_3_4),
            const SizedBox(width: 24),
            _buildCropButton(context, CropValue.ratio_4_3),
          ],
        ),
      ),
    );
  }

  Widget _buildCropButton(BuildContext context, CropValue value) {
    final aspectRatio = value.getFraction()?.toDouble();

    final isSelected = _selectedCropValue == value;

    return VideoEditorBottomAction(
      label: value.displayName,
      isSelected: isSelected,
      onPressed: () {
        if (value == CropValue.original) {
          widget.controller.updateCrop(Offset.zero, const Offset(1.0, 1.0));
          widget.controller.preferredCropAspectRatio = null;
          _selectedCropValue = null;
          setState(() {});
        } else if (value == CropValue.free) {
          widget.controller.preferredCropAspectRatio = null;
          _selectedCropValue = value;
          setState(() {});
        } else if (aspectRatio != null) {
          _selectedCropValue = value;

          widget.controller.preferredCropAspectRatio = aspectRatio;
          setState(() {});
        }
      },
      svgPath: "assets/video-editor/video-crop-${value.name}-action.svg",
    );
  }
}
