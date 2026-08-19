import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart" show getEnteTextTheme;

class VideoSpeedButton extends StatelessWidget {
  const VideoSpeedButton({
    super.key,
    required this.showControls,
    required this.playbackSpeed,
    required this.onTap,
  });

  final bool showControls;
  final double playbackSpeed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !showControls,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInQuad,
          opacity: showControls ? 1 : 0,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 4),
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  border: Border.all(color: strokeFaintDark),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedTimer02,
                      size: 16,
                      color: textBaseDark,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      playbackSpeed == 1.0 ? "1x" : "${playbackSpeed}x",
                      style: getEnteTextTheme(
                        context,
                      ).mini.copyWith(color: textBaseDark),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
