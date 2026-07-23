import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_app_bar.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_bottom_action.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_main_actions.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_player_control.dart";
import 'package:video_editor/video_editor.dart';

class VideoRotatePage extends StatelessWidget {
  const VideoRotatePage({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  Widget build(BuildContext context) {
    final rotation = controller.rotation;
    final colorScheme = getEnteColorScheme(context);
    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: VideoEditorAppBar(
        onCancel: () {
          while (controller.rotation != rotation) {
            controller.rotate90Degrees(RotateDirection.left);
          }
          Navigator.pop(context);
        },
        primaryActionLabel: AppLocalizations.of(context).done,
        onPrimaryAction: () {
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
                        child: CropGridViewer.preview(controller: controller),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: VideoEditorPlayerControl(controller: controller),
                      ),
                    ),
                  ],
                ),
              ),
              VideoEditorMainActions(
                children: [
                  VideoEditorBottomAction(
                    label: AppLocalizations.of(context).left,
                    onPressed: () =>
                        controller.rotate90Degrees(RotateDirection.left),
                    icon: Icons.rotate_left,
                  ),
                  const SizedBox(width: 24),
                  VideoEditorBottomAction(
                    label: AppLocalizations.of(context).right,
                    onPressed: () =>
                        controller.rotate90Degrees(RotateDirection.right),
                    icon: Icons.rotate_right,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
