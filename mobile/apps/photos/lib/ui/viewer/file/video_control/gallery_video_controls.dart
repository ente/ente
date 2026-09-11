import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/video_control/mute_button.dart";

const kVideoProgressBottomInset = 64.0;
const kVideoProgressHeight = 16.0;
const kVideoProgressRowBottomInset = 56.0;
const kVideoProgressRowHeight = 32.0;
const kVideoCaptionGap = 6.0;
const kVideoCaptionLineHeight = 16.0;
const kVideoScrimTopPadding = 12.0;
const kVideoLongPressPlaybackSpeed = 2.0;

OverlayEntry showVideoLongPressSpeedIndicator(BuildContext context) {
  final entry = OverlayEntry(
    builder: (context) {
      final screenSize = MediaQuery.sizeOf(context);
      final isLandscape = screenSize.width > screenSize.height;
      return Positioned(
        top:
            MediaQuery.paddingOf(context).top +
            (isLandscape ? 12 : kToolbarHeight + 16),
        left: 0,
        right: 0,
        child: const IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            child: Center(child: VideoLongPressSpeedIndicator()),
          ),
        ),
      );
    },
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return entry;
}

class VideoLongPressSpeedIndicator extends StatelessWidget {
  const VideoLongPressSpeedIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          "2x",
          style: textTheme.smallBold.copyWith(color: textBaseDark),
        ),
      ),
    );
  }
}

ValueListenable<double> galleryBottomControlsAdditionalInsetListenable(
  BuildContext context,
) {
  return InheritedDetailPageState.maybeOf(
        context,
      )?.bottomControlsAdditionalInsetNotifier ??
      const AlwaysStoppedAnimation(0);
}

// This widget returns Positioned, so its parent must be a Stack.
class GalleryBottomControlsPositioned extends StatelessWidget {
  final double bottom;
  final Widget child;

  const GalleryBottomControlsPositioned({
    required this.bottom,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: galleryBottomControlsAdditionalInsetListenable(context),
      builder: (context, additionalBottomInset, child) => Positioned(
        left: 0,
        right: 0,
        bottom: bottom + additionalBottomInset,
        child: child!,
      ),
      child: child,
    );
  }
}

class EqualHeightSliderTrackShape extends RoundedRectSliderTrackShape {
  const EqualHeightSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: 0,
    );
  }
}

class VideoBottomScrim extends StatelessWidget {
  final bool hasCaption;

  const VideoBottomScrim({required this.hasCaption, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: galleryBottomControlsAdditionalInsetListenable(context),
      builder: (context, additionalBottomInset, _) => IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: double.infinity,
            height:
                MediaQuery.paddingOf(context).bottom +
                kVideoProgressBottomInset +
                kVideoProgressHeight +
                additionalBottomInset +
                (hasCaption ? kVideoCaptionGap + kVideoCaptionLineHeight : 0) +
                kVideoScrimTopPadding,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const [0, 0.8, 1],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoProgressRow extends StatelessWidget {
  final Widget seekBar;
  final String elapsedTime;
  final String totalTime;

  const VideoProgressRow({
    required this.seekBar,
    required this.elapsedTime,
    required this.totalTime,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    final timeStyle = getEnteTextTheme(context).mini.copyWith(
      color: textBaseDark.withValues(alpha: 0.85),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: EdgeInsets.only(
        left: safePadding.left + 16,
        right: safePadding.right + 16,
      ),
      child: SizedBox(
        height: kVideoProgressRowHeight,
        child: Row(
          children: [
            Expanded(child: seekBar),
            const SizedBox(width: 16),
            Text('$elapsedTime / $totalTime', style: timeStyle),
            const SizedBox(width: 7),
            const VideoMuteButton(),
          ],
        ),
      ),
    );
  }
}
