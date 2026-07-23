import "package:flutter/material.dart";
import "package:photos/ente_theme_data.dart";
import "package:video_editor/video_editor.dart";

class VideoEditorPlayerControl extends StatelessWidget {
  const VideoEditorPlayerControl({super.key, required this.controller});

  final VideoEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: "video_editor_player_control",
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, controller.video]),
        builder: (_, _) {
          final duration = controller.trimmedDuration;
          Duration pos = controller.videoPosition - controller.startTrim;
          if (pos.isNegative) {
            pos = Duration.zero;
          } else if (pos > duration) {
            pos = duration;
          }
          final isPlaying = controller.isPlaying;

          return GestureDetector(
            onTap: () {
              if (controller.isPlaying) {
                controller.video.pause();
              } else {
                controller.video.play();
              }
            },
            child: Container(
              margin: const EdgeInsets.only(top: 24, bottom: 28),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              constraints: const BoxConstraints(minHeight: 36),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.editorBackgroundColor,
                borderRadius: BorderRadius.circular(56),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(!isPlaying ? Icons.play_arrow : Icons.pause, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    "${formatter(pos)} / ${formatter(duration)}",
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String formatter(Duration duration) => [
    duration.inMinutes.remainder(60).toString().padLeft(2, '0'),
    duration.inSeconds.remainder(60).toString().padLeft(2, '0'),
  ].join(":");
}
