import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_app_bar.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_player_control.dart";
import 'package:video_editor/video_editor.dart';

class VideoTrimPage extends StatefulWidget {
  const VideoTrimPage({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  State<VideoTrimPage> createState() => _VideoTrimPageState();
}

class _VideoTrimPageState extends State<VideoTrimPage> {
  final double height = 60;

  @override
  Widget build(BuildContext context) {
    final minTrim = widget.controller.minTrim;
    final maxTrim = widget.controller.maxTrim;
    final colorScheme = getEnteColorScheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: VideoEditorAppBar(
        onCancel: () {
          widget.controller.updateTrim(minTrim, maxTrim);
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
                        child: CropGridViewer.preview(
                          controller: widget.controller,
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
              _buildTrimSlider(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrimSlider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TrimSlider(
        controller: widget.controller,
        height: height,
        horizontalMargin: height / 4,
      ),
    );
  }

  String formatter(Duration duration) => [
    duration.inMinutes.remainder(60).toString().padLeft(2, '0'),
    duration.inSeconds.remainder(60).toString().padLeft(2, '0'),
  ].join(":");
}
