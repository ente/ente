import "package:flutter/widgets.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";

class RewindWordmark extends StatelessWidget {
  const RewindWordmark({required this.color, this.width = 50, super.key});

  static const aspectRatio = 50 / 15;

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: "ente",
      child: SvgPicture.file(
        RewindAssets.file(RewindAssets.wordmark),
        width: width,
        height: width / aspectRatio,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }
}
