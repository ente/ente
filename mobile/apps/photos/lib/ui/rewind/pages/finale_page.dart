import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/pages/finale/finale_card.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";

class FinalePage extends RewindPage {
  const FinalePage();

  static const pageKey = "finale";

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
    final launched =
        (isActive || (position < 0 && position > -0.9)) &&
        !RewindPageScope.coveredOf(context);
    return FinaleCard(active: isActive, launched: launched);
  }
}
