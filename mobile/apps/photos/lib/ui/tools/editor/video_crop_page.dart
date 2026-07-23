import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/tools/editor/video_editor/crop_value.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_app_bar.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_bottom_action.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_main_actions.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_player_control.dart";
import 'package:video_editor/video_editor.dart';

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

    // Check if we need to account for rotation
    final rotation = widget.controller.rotation;
    final isRotated = rotation % 180 != 0;

    // Find which crop value matches the current ratio
    for (final value in CropValue.values) {
      if (value == CropValue.original || value == CropValue.free) continue;

      final valueRatio = value.getFraction()?.toDouble();
      if (valueRatio == null) continue;

      // For rotated videos, check both the normal and swapped ratios
      if (isRotated && value != CropValue.ratio_1_1) {
        final swappedRatio = 1.0 / valueRatio;
        if ((currentRatio - swappedRatio).abs() < 0.01) {
          _selectedCropValue = value;
          return;
        }
      } else if ((currentRatio - valueRatio).abs() < 0.01) {
        _selectedCropValue = value;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: VideoEditorAppBar(
        onCancel: () => Navigator.pop(context),
        primaryActionLabel: AppLocalizations.of(context).done,
        onPrimaryAction: () {
          widget.controller.applyCacheCrop();
          Navigator.pop(context);
        },
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: "video-editor-preview",
                        child: CropGridViewer.edit(
                          controller: widget.controller,
                          rotateCropArea: true,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: VideoEditorPlayerControl(
                          controller: widget.controller,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCropButton(BuildContext context, CropValue value) {
    final aspectRatio = value.getFraction()?.toDouble();

    // Check if this button is selected
    final isSelected = _selectedCropValue == value;

    return VideoEditorBottomAction(
      label: value.displayName,
      isSelected: isSelected,
      onPressed: () {
        if (value == CropValue.original) {
          widget.controller.updateCrop(Offset.zero, const Offset(1.0, 1.0));
          widget.controller.cropAspectRatio(null);
          _selectedCropValue = null;
          setState(() {});
        } else if (value == CropValue.free) {
          widget.controller.preferredCropAspectRatio = null;
          _selectedCropValue = value;
          setState(() {});
        } else if (aspectRatio != null) {
          _selectedCropValue = value;

          // Store the visual aspect ratio, accounting for rotation
          final rotation = widget.controller.rotation;
          final isRotated = rotation % 180 != 0;
          final ratioToStore = (isRotated && value != CropValue.ratio_1_1)
              ? 1.0 / aspectRatio
              : aspectRatio;

          widget.controller.preferredCropAspectRatio = ratioToStore;
          setState(() {});
        }
      },
      svgPath: "assets/video-editor/video-crop-${value.name}-action.svg",
    );
  }
}
