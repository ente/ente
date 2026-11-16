import "dart:math";

import "package:flutter/material.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef _BadgeCopy = ({String title, String pronunciation, String definition});

_BadgeCopy _copyOf(rust.RewindBadge badge) => switch (badge) {
  rust.RewindBadge.sunChaser => (
    title: "SUN CHASER",
    pronunciation: "/ˈsən ˌchā-sər/",
    definition:
        "A person who regularly photographs sunrises, sunsets, and golden-hour light.",
  ),
  rust.RewindBadge.consistencyChamp => (
    title: "CONSISTENCY\nCHAMP",
    pronunciation: "/kən-ˈsis-tən-sē champ/",
    definition: "A person who takes photos consistently throughout the year.",
  ),
  rust.RewindBadge.unpaidPhotographer => (
    title: "UNPAID\nPHOTOGRAPHER",
    pronunciation: "/ən-ˈpād fə-ˈtä-grə-fər/",
    definition:
        "A person who frequently creates and shares photo albums with others.",
  ),
  rust.RewindBadge.mainCharacter => (
    title: "MAIN\nCHARACTER",
    pronunciation: "/ˈmān ˈker-ik-tər/",
    definition:
        "A person who appears in a significant proportion of their own photos.",
  ),
  rust.RewindBadge.earlyBird => (
    title: "EARLY BIRD",
    pronunciation: "/ˈər-lē ˈbərd/",
    definition:
        "A person who frequently takes photos during the early morning hours.",
  ),
  rust.RewindBadge.nightOwl => (
    title: "NIGHT OWL",
    pronunciation: "/ˈnīt ˌau̇l/",
    definition: "A person who frequently takes photos after dark.",
  ),
  rust.RewindBadge.weekendStar => (
    title: "WEEKEND STAR",
    pronunciation: "/ˈwēk-end ˈstär/",
    definition: "A person who takes most of their photos on weekends.",
  ),
  rust.RewindBadge.pawparazzi => (
    title: "PAWPARAZZI",
    pronunciation: "/ˌpȯ-pə-ˈrät-sē/",
    definition:
        "A person whose photo collection contains a high proportion of pet photographs.",
  ),
  rust.RewindBadge.foodie => (
    title: "FOODIE",
    pronunciation: "/ˈfü-dē/",
    definition:
        "A person who frequently photographs food, meals, and dining experiences.",
  ),
  rust.RewindBadge.plantParent => (
    title: "PLANT PARENT",
    pronunciation: "/ˈplant ˌper-ənt/",
    definition:
        "A person who regularly photographs plants, flowers, and other botanical subjects.",
  ),
  rust.RewindBadge.buildingBuff => (
    title: "BUILDING BUFF",
    pronunciation: "/ˈbil-diŋ ˈbəf/",
    definition:
        "A person who frequently photographs buildings, architecture, and structural details.",
  ),
  rust.RewindBadge.screenshotCollector => (
    title: "SCREENSHOT\nCOLLECTOR",
    pronunciation: "/ˈskrēn-ˌshät kə-ˈlek-tər/",
    definition:
        "A person who regularly saves screenshots of information, conversations, images, and other digital content.",
  ),
  rust.RewindBadge.hobbyHopper => (
    title: "HOBBY HOPPER",
    pronunciation: "/ˈhä-bē ˈhä-pər/",
    definition:
        "A person whose photographs reflect a variety of hobbies and interests over time.",
  ),
  rust.RewindBadge.indoorKid => (
    title: "INDOOR KID",
    pronunciation: "/ˈin-dȯr ˈkid/",
    definition: "A person who takes most of their photographs indoors.",
  ),
  rust.RewindBadge.outOfOffice => (
    title: "OUT OF OFFICE",
    pronunciation: "/ˈau̇t əv ˈȯ-fəs/",
    definition:
        "A person who frequently photographs travel, outings, and visits to different places.",
  ),
  rust.RewindBadge.fullThrottle => (
    title: "FULL THROTTLE",
    pronunciation: "/ˈfu̇l ˈthrä-tᵊl/",
    definition:
        "A person who regularly captures sports, exercise, and other physical activities.",
  ),
  rust.RewindBadge.eventHopper => (
    title: "EVENT HOPPER",
    pronunciation: "/i-ˈvent ˈhä-pər/",
    definition:
        "A person who frequently photographs parties, concerts, festivals, celebrations, and other events.",
  ),
  rust.RewindBadge.alwaysRolling => (
    title: "ALWAYS\nROLLING",
    pronunciation: "/ˈȯl-wāz ˈrō-liŋ/",
    definition:
        "A person who frequently records videos rather than taking still photographs.",
  ),
  rust.RewindBadge.fitCheck => (
    title: "FIT CHECK",
    pronunciation: "/ˈfit ˌchek/",
    definition:
        "A person who regularly photographs clothing, outfits, footwear, and accessories.",
  ),
  rust.RewindBadge.artLover => (
    title: "ART LOVER",
    pronunciation: "/ˈärt ˈlə-vər/",
    definition:
        "A person who frequently photographs paintings, sculptures, murals, and other forms of art.",
  ),
  rust.RewindBadge.limitedEdition => (
    title: "LIMITED\nEDITION",
    pronunciation: "/ˈli-mə-təd i-ˈdi-shən/",
    definition:
        "A person who takes relatively few photos, spread across a substantial part of the year.",
  ),
  rust.RewindBadge.happySnapper => (
    title: "HAPPY SNAPPER",
    pronunciation: "/ˈha-pē ˈsna-pər/",
    definition:
        "A person who takes many photos across a wide variety of subjects, without a single dominant interest.",
  ),
  rust.RewindBadge.openingCredits => (
    title: "OPENING\nCREDITS",
    pronunciation: "/ˈō-pə-niŋ ˈkre-dits/",
    definition:
        "A person whose available photo history covers only a short period of time.",
  ),
  rust.RewindBadge.guestStar => (
    title: "GUEST STAR",
    pronunciation: "/ˈgest ˌstär/",
    definition:
        "A person who takes photos in occasional bursts, with extended periods of little or no activity.",
  ),
  rust.RewindBadge.mixedBag => (
    title: "MIXED BAG",
    pronunciation: "/ˈmikst ˈbag/",
    definition:
        "A person whose photo collection does not show a clearly dominant pattern or contains insufficient information to identify one.",
  ),
};

class BadgeRevealPage extends RewindPage {
  const BadgeRevealPage(this.badge);

  static const backdrop = RewindBackdrop(
    color: Color(0xFF000000),
    pattern: RewindRays(Color(0xFF070707)),
  );
  static const _badgeCenter = Offset(195, 326);
  static const _titleBox = 92.0;

  final rust.Badge badge;

  @override
  String get key => "badge";

  @override
  Duration? get reelHold => const Duration(milliseconds: 3400);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final copy = _copyOf(badge.id);
    final title = copy.title;
    final entry = "${copy.pronunciation} · noun";
    final trigger = badge.id.name.replaceAllMapped(
      RegExp("[A-Z]"),
      (match) => "_${match[0]!.toLowerCase()}",
    );
    final inset =
        MediaQuery.paddingOf(context).bottom /
        RewindStage.scaleFor(MediaQuery.sizeOf(context));
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
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
                  centerY: 640,
                  child: CustomSingleChildLayout(
                    delegate: _BadgeTextLayout(
                      bottom: 768 - max(0, inset - 12),
                    ),
                    child: SizedBox(
                      width: 334,
                      child: Semantics(
                        label:
                            "${title.replaceAll("\n", " ")}. "
                            "${copy.definition}",
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: _titleBox,
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: RewindEntrance(
                                    preset: RewindPreset.slap,
                                    active: isActive,
                                    delayMs: 1350,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.bottomLeft,
                                      child: RewindOutlinedText(
                                        title,
                                        style: RewindTextStyles.display(
                                          44,
                                          color: RewindColors.white,
                                          height: 46 / 44,
                                        ),
                                        outline: 2.264,
                                        shadow: const Offset(3.234, 3.881),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              RewindEntrance(
                                active: isActive,
                                preset: RewindPreset.line,
                                delayMs: 1650,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry,
                                      style: RewindTextStyles.phonetic(
                                        14,
                                        color: RewindColors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      copy.definition,
                                      style: RewindTextStyles.body(
                                        18,
                                        height: 24 / 18,
                                        color: RewindColors.white,
                                      ),
                                    ),
                                  ],
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
  static const _top = 536.0;

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
