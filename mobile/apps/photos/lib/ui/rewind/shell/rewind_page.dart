import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";

class RewindChrome {
  const RewindChrome({
    required this.foreground,
    this.wordmark,
    this.muteButton = true,
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

  bool get onLightPage => foreground.computeLuminance() < 0.5;
}

abstract class RewindPage {
  const RewindPage();

  String get key;

  int get stops => 1;

  bool get pinned => false;

  RewindChrome get chrome => RewindChrome.light;

  Widget build(BuildContext context, double position, {required bool isActive});
}
