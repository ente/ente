import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";

class VideoDownloadProgressIndicator extends StatelessWidget {
  final double? progress;

  const VideoDownloadProgressIndicator({required this.progress, super.key});

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    if (progress == null || progress == 1) {
      return const EnteLoadingWidget(size: 32, color: fillBaseDark, padding: 0);
    }

    return SizedBox.square(
      dimension: 32,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            backgroundColor: Colors.transparent,
            value: progress,
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color.fromRGBO(45, 194, 98, 1.0),
            ),
            strokeWidth: 2,
            strokeCap: StrokeCap.round,
          ),
          Center(
            child: Text(
              "${(progress * 100).toStringAsFixed(0)}%",
              style: getEnteTextTheme(
                context,
              ).tiny.copyWith(color: textBaseDark),
            ),
          ),
        ],
      ),
    );
  }
}
