import 'package:flutter/material.dart';
import 'package:photos/ui/common/video_speed_options.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_controller.dart';
import 'package:photos/ui/tools/editor/video_editor/video_editor_widgets.dart';

class VideoSpeedPage extends StatelessWidget {
  const VideoSpeedPage({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  Widget build(BuildContext context) {
    return VideoEditorSubPage(
      controller: controller,
      preview: VideoEditorPreview(controller: controller),
      actions: Padding(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => VideoSpeedOptions(
            currentSpeed: controller.speed,
            onSpeedSelected: controller.updateSpeed,
          ),
        ),
      ),
    );
  }
}
