import "package:flutter/widgets.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";

class RewindChrome {
  const RewindChrome({
    required this.foreground,
    this.wordmark,
    this.muteButton = true,
    this.nextArrow = false,
  });

  static const light = RewindChrome(
    foreground: RewindColors.cream,
    wordmark: RewindColors.white,
  );
  static const dark = RewindChrome(
    foreground: RewindColors.ink,
    wordmark: RewindColors.white,
  );

  final Color foreground;
  final Color? wordmark;
  final bool muteButton;
  final bool nextArrow;

  bool get onLightPage => foreground.computeLuminance() < 0.5;
}

abstract class RewindPage {
  const RewindPage();

  String get key;

  int get stops => 1;

  bool get pinned => false;

  RewindChrome get chrome => RewindChrome.light;

  Duration? get reelHold =>
      const Duration(milliseconds: 2400 + RewindMotion.reelReadingMs);

  List<EnteFile>? get reelThumbnails => null;

  Duration? get clipHold => null;

  RewindPage? get clipIntro => null;

  Object get clipKey => this;

  bool get hasOwnVideoButton => false;

  void resetAnswer() {}

  int get warmAhead => 2;

  Future<bool> warmUp() async => true;

  void release() {}

  Widget build(BuildContext context, double position, {required bool isActive});
}
