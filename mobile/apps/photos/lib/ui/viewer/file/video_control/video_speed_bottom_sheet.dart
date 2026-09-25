import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import 'package:photos/ui/common/video_speed_options.dart';

Future<void> showVideoSpeedBottomSheet(
  BuildContext context, {
  required double currentSpeed,
  required void Function(double) onSpeedSelected,
}) async {
  await showBottomSheetComponent<void>(
    context: context,
    builder: (context) => BottomSheetComponent(
      title: context.strings.playbackSpeed,
      content: VideoSpeedOptions(
        currentSpeed: currentSpeed,
        onSpeedSelected: (speed) {
          onSpeedSelected(speed);
          Navigator.of(context).pop();
        },
      ),
    ),
  );
}
