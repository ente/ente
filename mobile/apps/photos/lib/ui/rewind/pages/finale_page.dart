import "package:flutter/widgets.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/pages/finale/envelope_finale.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";

class FinalePage extends RewindPage {
  const FinalePage(this.photos);

  static const pageKey = "finale";
  static const photoCount = EnvelopeFinale.photoCount;

  final List<EnteFile> photos;

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold => null;

  @override
  bool get hasOwnVideoButton => true;

  @override
  RewindChrome get chrome => const RewindChrome(foreground: RewindColors.cream);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return EnvelopeFinale(photos: photos, active: isActive);
  }
}
