import "dart:ui";

import "package:photos/ui/rewind/reel/rewind_reel.dart";

class RewindVideoFormat {
  const RewindVideoFormat({required this.pixelRatio, required this.encoder});

  static const fullHd = RewindVideoFormat(
    pixelRatio: 3,
    encoder: [
      "-c:v:0",
      "libx264",
      "-preset",
      "superfast",
      "-crf",
      "23",
      "-maxrate",
      "10M",
      "-bufsize",
      "20M",
      "-g",
      "60",
    ],
  );

  final double pixelRatio;
  final List<String> encoder;

  Size get pixels => RewindReel.canvas * pixelRatio;
}
