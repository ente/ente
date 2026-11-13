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

typedef _BadgeCopy = ({
  String title,
  double size,
  String pronunciation,
  String definition,
});

_BadgeCopy _copyOf(rust.RewindBadge badge) => switch (badge) {
  rust.RewindBadge.sunChaser => (
    title: "SUN CHASER",
    size: 59.508,
    pronunciation: "/ˈsən ˌchā-sər/",
    definition:
        "A person who regularly photographs sunrises, sunsets, and golden-hour light.",
  ),
  rust.RewindBadge.consistencyChamp => (
    title: "CONSISTENCY\nCHAMP",
    size: 53.508,
    pronunciation: "/kən-ˈsis-tən-sē champ/",
    definition: "A person who takes photos consistently throughout the year.",
  ),
  rust.RewindBadge.unpaidPhotographer => (
    title: "UNPAID\nPHOTOGRAPHER",
    size: 45.508,
    pronunciation: "/ən-ˈpād fə-ˈtä-grə-fər/",
    definition:
        "A person who frequently creates and shares photo albums with others.",
  ),
  rust.RewindBadge.mainCharacter => (
    title: "MAIN\nCHARACTER",
    size: 59.508,
    pronunciation: "/ˈmān ˈker-ik-tər/",
    definition:
        "A person who appears in a significant proportion of their own photos.",
  ),
  rust.RewindBadge.earlyBird => (
    title: "EARLY BIRD",
    size: 59.508,
    pronunciation: "/ˈər-lē ˈbərd/",
    definition:
        "A person who frequently takes photos during the early morning hours.",
  ),
  rust.RewindBadge.nightOwl => (
    title: "NIGHT OWL",
    size: 59.508,
    pronunciation: "/ˈnīt ˌau̇l/",
    definition: "A person who frequently takes photos after dark.",
  ),
  rust.RewindBadge.weekendStar => (
    title: "WEEKEND STAR",
    size: 49.508,
    pronunciation: "/ˈwēk-end ˈstär/",
    definition: "A person who takes most of their photos on weekends.",
  ),
  rust.RewindBadge.pawparazzi => (
    title: "PAWPARAZZI",
    size: 55.508,
    pronunciation: "/ˌpȯ-pə-ˈrät-sē/",
    definition:
        "A person whose photo collection contains a high proportion of pet photographs.",
  ),
  rust.RewindBadge.foodie => (
    title: "FOODIE",
    size: 59.508,
    pronunciation: "/ˈfü-dē/",
    definition:
        "A person who frequently photographs food, meals, and dining experiences.",
  ),
  rust.RewindBadge.plantParent => (
    title: "PLANT PARENT",
    size: 52.508,
    pronunciation: "/ˈplant ˌper-ənt/",
    definition:
        "A person who regularly photographs plants, flowers, and other botanical subjects.",
  ),
  rust.RewindBadge.buildingBuff => (
    title: "BUILDING BUFF",
    size: 49.508,
    pronunciation: "/ˈbil-diŋ ˈbəf/",
    definition:
        "A person who frequently photographs buildings, architecture, and structural details.",
  ),
  rust.RewindBadge.screenshotCollector => (
    title: "SCREENSHOT\nCOLLECTOR",
    size: 58.508,
    pronunciation: "/ˈskrēn-ˌshät kə-ˈlek-tər/",
    definition: "A person who regularly saves screenshots.",
  ),
  rust.RewindBadge.hobbyHopper => (
    title: "HOBBY HOPPER",
    size: 48.508,
    pronunciation: "/ˈhä-bē ˈhä-pər/",
    definition:
        "A person whose photographs reflect a variety of hobbies and interests over time.",
  ),
  rust.RewindBadge.indoorKid => (
    title: "INDOOR KID",
    size: 59.508,
    pronunciation: "/ˈin-dȯr ˈkid/",
    definition: "A person who takes most of their photographs indoors.",
  ),
  rust.RewindBadge.outOfOffice => (
    title: "OUT OF OFFICE",
    size: 51.508,
    pronunciation: "/ˈau̇t əv ˈȯ-fəs/",
    definition:
        "A person who frequently photographs travel, outings, and visits to different places.",
  ),
  rust.RewindBadge.fullThrottle => (
    title: "FULL THROTTLE",
    size: 51.508,
    pronunciation: "/ˈfu̇l ˈthrä-tᵊl/",
    definition:
        "A person who regularly captures sports, exercise, and other physical activities.",
  ),
  rust.RewindBadge.eventHopper => (
    title: "EVENT HOPPER",
    size: 51.508,
    pronunciation: "/i-ˈvent ˈhä-pər/",
    definition:
        "A person who frequently photographs parties, concerts, festivals, and other events.",
  ),
  rust.RewindBadge.alwaysRolling => (
    title: "ALWAYS\nROLLING",
    size: 59.508,
    pronunciation: "/ˈȯl-wāz ˈrō-liŋ/",
    definition:
        "A person who frequently records videos rather than taking still photographs.",
  ),
  rust.RewindBadge.fitCheck => (
    title: "FIT CHECK",
    size: 59.508,
    pronunciation: "/ˈfit ˌchek/",
    definition:
        "A person who regularly photographs clothing, outfits, footwear, and accessories.",
  ),
  rust.RewindBadge.artLover => (
    title: "ART LOVER",
    size: 59.508,
    pronunciation: "/ˈärt ˈlə-vər/",
    definition:
        "A person who frequently photographs paintings, sculptures, murals, and other forms of art.",
  ),
  rust.RewindBadge.limitedEdition => (
    title: "LIMITED\nEDITION",
    size: 59.508,
    pronunciation: "/ˈli-mə-təd i-ˈdi-shən/",
    definition:
        "A person who takes relatively few photos, spread across a substantial part of the year.",
  ),
  rust.RewindBadge.happySnapper => (
    title: "HAPPY SNAPPER",
    size: 46.508,
    pronunciation: "/ˈha-pē ˈsna-pər/",
    definition:
        "A person who takes many photos across a wide variety of subjects, without a single dominant interest.",
  ),
  rust.RewindBadge.openingCredits => (
    title: "OPENING\nCREDITS",
    size: 59.508,
    pronunciation: "/ˈō-pə-niŋ ˈkre-dits/",
    definition:
        "A person whose available photo history covers only a short period of time.",
  ),
  rust.RewindBadge.guestStar => (
    title: "GUEST STAR",
    size: 59.508,
    pronunciation: "/ˈgest ˌstär/",
    definition:
        "A person who takes photos in occasional bursts, with extended periods of little or no activity.",
  ),
  rust.RewindBadge.mixedBag => (
    title: "MIXED BAG",
    size: 59.508,
    pronunciation: "/ˈmikst ˈbag/",
    definition:
        "A person whose photo collection does not show a clearly dominant pattern or contains insufficient information to identify one.",
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
    final title = copy.title;
    final entry = "${copy.pronunciation} · noun";
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
                        label:
                            "${title.replaceAll("\n", " ")}. "
                            "${copy.definition}",
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
                              const SizedBox(height: 8),
                              RewindEntrance(
                                active: isActive,
                                preset: RewindPreset.line,
                                delayMs: 1650,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 2),
                                  child: SizedBox(
                                    width: 316,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry,
                                          style: RewindTextStyles.phonetic(15),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          copy.definition,
                                          style: RewindTextStyles.body(
                                            17,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
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
