import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:photos/ui/tools/editor/video_editor/video_editor_bottom_action.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_controller.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_main_actions.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_widgets.dart";

class VideoRotatePage extends StatelessWidget {
  const VideoRotatePage({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  Widget build(BuildContext context) {
    return VideoEditorSubPage(
      controller: controller,
      preview: VideoEditorPreview(controller: controller),
      actions: VideoEditorMainActions(
        children: [
          VideoEditorBottomAction(
            label: context.strings.left,
            onPressed: () =>
                controller.rotate90Degrees(VideoRotationDirection.left),
            icon: Icons.rotate_left,
          ),
          VideoEditorBottomAction(
            label: context.strings.right,
            onPressed: () =>
                controller.rotate90Degrees(VideoRotationDirection.right),
            icon: Icons.rotate_right,
          ),
        ],
      ),
    );
  }
}
