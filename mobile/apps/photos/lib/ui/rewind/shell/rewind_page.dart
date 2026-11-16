import "package:flutter/widgets.dart";
import "package:photos/models/file/file.dart";
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

  Duration? get reelHold => const Duration(milliseconds: 2400);

  List<EnteFile>? get reelThumbnails => null;

  bool get hasOwnVideoButton => false;

  void resetAnswer() {}

  int get warmAhead => 2;

  Future<bool> warmUp() async => true;

  void release() {}

  Widget build(BuildContext context, double position, {required bool isActive});
}
