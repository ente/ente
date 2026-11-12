import "dart:math";

import "package:flutter/material.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef _BadgeCopy = ({
  String title,
  double size,
  String Function(int n)? stat,
  String quip,
});

_BadgeCopy _copyOf(rust.RewindBadge badge) => switch (badge) {
  rust.RewindBadge.sunChaser => (
    title: "SUN CHASER",
    size: 59.508,
    stat: (n) => "Golden hour in ${rewindCounted(n, "photo", "photos")}.",
    quip: "The sun knows your schedule.",
  ),
  rust.RewindBadge.consistencyChamp => (
    title: "CONSISTENCY\nCHAMP",
    size: 53.508,
    stat: (n) => "Photos in all ${rewindCount(n)} months.",
    quip: "Your camera never took a holiday.",
  ),
  rust.RewindBadge.unpaidPhotographer => (
    title: "UNPAID\nPHOTOGRAPHER",
    size: 45.508,
    stat: (n) => "${rewindCounted(n, "album", "albums")} shared.",
    quip: "Someone should be paying you.",
  ),
  rust.RewindBadge.mainCharacter => (
    title: "MAIN\nCHARACTER",
    size: 59.508,
    stat: (n) => "You’re in $n% of your own photos.",
    quip: "As you should be.",
  ),
  rust.RewindBadge.earlyBird => (
    title: "EARLY BIRD",
    size: 59.508,
    stat: null,
    quip: "Most photos before 8am. The coffee came second.",
  ),
  rust.RewindBadge.nightOwl => (
    title: "NIGHT OWL",
    size: 59.508,
    stat: null,
    quip: "Most photos after 10pm. Sleep can wait.",
  ),
  rust.RewindBadge.weekendStar => (
    title: "WEEKEND STAR",
    size: 49.508,
    stat: (n) => "$n% shot on weekends.",
    quip: "Mondays never stood a chance.",
  ),
  rust.RewindBadge.pawparazzi => (
    title: "PAWPARAZZI",
    size: 55.508,
    stat: (n) => "Your pet was in ${rewindCounted(n, "photo", "photos")}.",
    quip: "Their agent is thrilled.",
  ),
  rust.RewindBadge.foodie => (
    title: "FOODIE",
    size: 59.508,
    stat: (n) => "${rewindCounted(n, "food photo", "food photos")}.",
    quip: "The camera eats first.",
  ),
  rust.RewindBadge.plantParent => (
    title: "PLANT PARENT",
    size: 52.508,
    stat: (n) => "${rewindCounted(n, "plant photo", "plant photos")}.",
    quip: "Every leaf got its close-up.",
  ),
  rust.RewindBadge.buildingBuff => (
    title: "BUILDING BUFF",
    size: 49.508,
    stat: (n) => "${rewindCounted(n, "building", "buildings")} photographed.",
    quip: "You look up a lot.",
  ),
  rust.RewindBadge.screenshotCollector => (
    title: "SCREENSHOT\nCOLLECTOR",
    size: 58.508,
    stat: (n) => "${rewindCounted(n, "screenshot", "screenshots")}.",
    quip: "Receipts, memes and proof, all saved.",
  ),
  rust.RewindBadge.hobbyHopper => (
    title: "HOBBY HOPPER",
    size: 48.508,
    stat: null,
    quip: "A new obsession every few months. Your gallery kept up.",
  ),
  rust.RewindBadge.indoorKid => (
    title: "INDOOR KID",
    size: 59.508,
    stat: (n) => "$n% shot indoors.",
    quip: "The couch thanks you.",
  ),
  rust.RewindBadge.outOfOffice => (
    title: "OUT OF OFFICE",
    size: 51.508,
    stat: (n) => "${rewindCounted(n, "trip", "trips")} this year.",
    quip: "The out-of-office stayed on.",
  ),
  rust.RewindBadge.fullThrottle => (
    title: "FULL THROTTLE",
    size: 51.508,
    stat: (n) => "${rewindCounted(n, "action shot", "action shots")}.",
    quip: "Rest days were optional.",
  ),
  rust.RewindBadge.eventHopper => (
    title: "EVENT HOPPER",
    size: 51.508,
    stat: (n) =>
        "${rewindCounted(n, "party, gig or festival", "parties, gigs and festivals")}.",
    quip: "Your camera always RSVPs yes.",
  ),
  rust.RewindBadge.alwaysRolling => (
    title: "ALWAYS\nROLLING",
    size: 59.508,
    stat: (n) => "${rewindCounted(n, "video", "videos")}.",
    quip: "Why take a photo when it can move?",
  ),
  rust.RewindBadge.fitCheck => (
    title: "FIT CHECK",
    size: 59.508,
    stat: (n) => "${rewindCounted(n, "outfit photo", "outfit photos")}.",
    quip: "The mirror’s been busy.",
  ),
  rust.RewindBadge.artLover => (
    title: "ART LOVER",
    size: 59.508,
    stat: (n) => "${rewindCounted(n, "artwork", "artworks")} photographed.",
    quip: "Your gallery has a gallery.",
  ),
  rust.RewindBadge.limitedEdition => (
    title: "LIMITED\nEDITION",
    size: 59.508,
    stat: null,
    quip: "Fewer photos, picked with care. Every one counts.",
  ),
  rust.RewindBadge.happySnapper => (
    title: "HAPPY SNAPPER",
    size: 46.508,
    stat: null,
    quip: "A bit of everything, and lots of it. No favourites here.",
  ),
  rust.RewindBadge.openingCredits => (
    title: "OPENING\nCREDITS",
    size: 59.508,
    stat: null,
    quip: "Just getting started. The best scenes are still coming.",
  ),
  rust.RewindBadge.guestStar => (
    title: "GUEST STAR",
    size: 59.508,
    stat: null,
    quip: "Quiet for weeks, then a burst. Always worth the wait.",
  ),
  rust.RewindBadge.mixedBag => (
    title: "MIXED BAG",
    size: 59.508,
    stat: null,
    quip: "No single label fits. Some years refuse to be summed up.",
  ),
};

class BadgeRevealPage extends RewindPage {
  const BadgeRevealPage(this.badge);

  static const _badgeCenter = Offset(195, 376);

  final rust.Badge badge;

  @override
  String get key => "badge";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final copy = _copyOf(badge.id);
    final value = badge.value;
    final stat = copy.stat;
    final line = stat != null && value != null
        ? "${stat(value)} ${copy.quip}"
        : copy.quip;
    final title = copy.title;
    final trigger = badge.id.name.replaceAllMapped(
      RegExp("[A-Z]"),
      (match) => "_${match[0]!.toLowerCase()}",
    );
    final twoLines = title.contains("\n");
    final inset =
        MediaQuery.paddingOf(context).bottom /
        RewindStage.scaleFor(MediaQuery.sizeOf(context));
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFF12BB2C),
            pattern: RewindRays(Color(0xFF16B42E)),
          ),
          RewindStage(
            children: [
              Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: _badgeCenter,
                  width: 290,
                  height: 364,
                ),
                child: RewindLeave(
                  position: position,
                  centerY: _badgeCenter.dy,
                  child: Semantics(
                    label: "${title.replaceAll("\n", " ")} badge",
                    button: true,
                    hint: "Double tap to flip it again",
                    child: OverflowBox(
                      maxWidth: 522,
                      maxHeight: 580,
                      child: RewindBadge(badge: trigger, active: isActive),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: RewindLeave(
                  position: position,
                  centerY: 690,
                  child: CustomSingleChildLayout(
                    delegate: _BadgeTextLayout(
                      bottom: 768 - max(0, inset - 12),
                    ),
                    child: SizedBox(
                      width: 340,
                      child: Semantics(
                        label: "${title.replaceAll("\n", " ")}. $line",
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RewindEntrance(
                                preset: RewindPreset.slap,
                                active: isActive,
                                delayMs: 1350,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 340,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: RewindOutlinedText(
                                      title,
                                      style: RewindTextStyles.display(
                                        copy.size,
                                        color: RewindColors.white,
                                        height: twoLines ? 0.92 : 0.95,
                                      ),
                                      outline: 3,
                                      shadow: const Offset(3.234, 3.881),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 13),
                              RewindEntrance(
                                active: isActive,
                                preset: RewindPreset.line,
                                delayMs: 1650,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 2),
                                  child: SizedBox(
                                    width: 316,
                                    child: Text(
                                      line,
                                      style: RewindTextStyles.body(
                                        19,
                                        height: 1.32,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgeTextLayout extends SingleChildLayoutDelegate {
  const _BadgeTextLayout({required this.bottom});

  static const _left = 26.0;
  static const _top = 604.0;

  final double bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(_left, min(_top, bottom - childSize.height));

  @override
  bool shouldRelayout(_BadgeTextLayout oldDelegate) =>
      oldDelegate.bottom != bottom;
}
