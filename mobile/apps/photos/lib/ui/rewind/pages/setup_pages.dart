import "package:flutter/painting.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/pages/setup_page.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stickers.dart";

const paletteSetupPage = SetupPage(
  key: "palette_setup",
  setup: RewindSetup.palette,
  color: Color(0xFF14BD2E),
  pattern: Color(0xFF14B62D),
  ink: RewindColors.white,
  chrome: RewindChrome.dark,
  headlines: [
    SetupHeadline(at: Offset(32, 126), size: 56, height: 0.84, width: 326),
  ],
  callout: SetupCallout(center: Offset(178, 422.5), delayMs: 600, onTop: true),
  art: SetupArt.ducky(
    RewindAssets.paletteDucky,
    Rect.fromLTWH(-1, 451, 383, 329),
    ticks: [(RewindTick.back, Rect.fromLTWH(192, 474, 13, 17))],
    pivot: Offset(190, 757),
    delayMs: 780,
  ),
);

const placesSetupPage = SetupPage(
  key: "places_setup",
  setup: RewindSetup.places,
  color: Color(0xFF123E97),
  pattern: Color(0xFF0C3B9B),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 66)],
  callout: SetupCallout(center: Offset(201.5, 426), delayMs: 600),
  art: SetupArt.ducky(
    RewindAssets.globeDucky,
    Rect.fromLTWH(0, 471, 390.2, 310.4),
    ticks: [(RewindTick.forward, Rect.fromLTWH(194, 486, 11, 18))],
    pivot: Offset(195, 758),
    delayMs: 780,
  ),
);

const peopleSetupPage = SetupPage(
  key: "people_setup",
  setup: RewindSetup.people,
  color: Color(0xFF9D4AE4),
  pattern: Color(0xFF993EE9),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 46)],
  callout: SetupCallout(center: Offset(198, 463.9), turn: -3.1, delayMs: 600),
  art: SetupArt.ducky(
    RewindAssets.hugDucky,
    Rect.fromLTWH(-46, 379, 484.3, 484.3),
    pivot: Offset(195, 840),
    delayMs: 780,
  ),
);

const busiestDaySetupPage = SetupPage(
  key: "busiest_day_setup",
  setup: RewindSetup.busiestDay,
  color: Color(0xFFF72F33),
  pattern: Color(0xFFF02525),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 100), size: 59)],
  callout: SetupCallout(center: Offset(201.2, 350), onTop: true),
  art: SetupArt.image(
    RewindAssets.photoHeapDucky,
    Rect.fromLTWH(-75, 281, 540, 540),
    ticks: [(RewindTick.forward, Rect.fromLTWH(194, 373, 11, 18))],
    preset: RewindPreset.crowd,
    delayMs: 250,
  ),
);

const newFacesSetupPage = SetupPage(
  key: "new_faces_setup",
  setup: RewindSetup.newFaces,
  color: Color(0xFF3366D3),
  pattern: Color(0xFF3B6ED7),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 49.578)],
  callout: SetupCallout(center: Offset(195, 334.2), turn: -4.5),
  art: SetupArt.ducky(
    RewindAssets.famDucky,
    Rect.fromLTWH(-124, 350, 579, 547.8),
    pivot: Offset(195, 844),
  ),
);

const favouritesSetupPage = SetupPage(
  key: "favourites_setup",
  setup: RewindSetup.favourites,
  color: Color(0xFFFB4196),
  pattern: Color(0xFFFF4D9F),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 48)],
  callout: SetupCallout(center: Offset(199, 391), size: 29.01),
  art: SetupArt.ducky(
    RewindAssets.photosDucky,
    Rect.fromLTWH(-140, 392, 605.3, 426.5),
    pivot: Offset(195, 795),
  ),
);

const ritualSetupPage = SetupPage(
  key: "ritual_setup",
  setup: RewindSetup.ritual,
  color: Color(0xFFFFCA39),
  pattern: Color(0xFFFFD24E),
  ink: RewindColors.ink,
  chrome: RewindChrome.dark,
  headlines: [
    SetupHeadline(at: Offset(24, 140), size: 50),
    SetupHeadline(at: Offset(29.4, 233), size: 50, turn: 0.44, delayMs: 120),
  ],
  callout: SetupCallout(center: Offset(217.7, 393), delayMs: 650, onTop: true),
  art: SetupArt.ducky(
    RewindAssets.almostTimeDucky,
    Rect.fromLTWH(11, 386.5, 315.7, 400.3),
    ticks: [(RewindTick.forward, Rect.fromLTWH(232, 431, 11, 18))],
    pivot: Offset(158, 762),
    delayMs: 830,
  ),
);

const ritualStreakSetupPage = SetupPage(
  key: "ritual_streak_setup",
  setup: RewindSetup.ritualStreak,
  color: Color(0xFFE86436),
  pattern: Color(0xFFF0713F),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 66)],
  callout: SetupCallout(center: Offset(196.6, 391.9), delayMs: 600),
  art: SetupArt.ducky(
    RewindAssets.artistDucky,
    Rect.fromLTWH(-17.2, 422.3, 427.6, 375.7),
    ticks: [(RewindTick.forwardFlipped, Rect.fromLTWH(190, 429, 10.5, 18))],
    pivot: Offset(175, 765),
    delayMs: 780,
  ),
);

const mosaicSetupPage = SetupPage(
  key: "mosaic_setup",
  setup: RewindSetup.mosaic,
  color: Color(0xFFF9692C),
  pattern: Color(0xFFF9763B),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 66)],
  callout: SetupCallout(center: Offset(188.6, 380.6), delayMs: 600),
  art: SetupArt.ducky(
    RewindAssets.puzzleDucky,
    Rect.fromLTWH(-20, 432, 484, 484),
    ticks: [(RewindTick.slant, Rect.fromLTWH(239, 436.3, 13.9, 19.3))],
    pivot: Offset(195, 844),
    delayMs: 780,
  ),
);

const likesSetupPage = SetupPage(
  key: "likes_setup",
  setup: RewindSetup.likes,
  color: Color(0xFF2F65D7),
  pattern: Color(0xFF3670EB),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 48)],
  callout: SetupCallout(center: Offset(188.2, 383.5)),
  art: SetupArt.ducky(
    RewindAssets.likesDucky,
    Rect.fromLTWH(21.5, 410, 344, 376),
    pivot: Offset(194, 762),
  ),
);

const badgeSetupPage = SetupPage(
  key: "badge_setup",
  setup: RewindSetup.badge,
  color: Color(0xFF0DBE28),
  pattern: Color(0xFF11B72A),
  ink: RewindColors.cream,
  headlines: [SetupHeadline(at: Offset(24, 140), size: 45)],
  callout: SetupCallout(center: Offset(196.5, 351), size: 29.01),
  art: SetupArt.ducky(
    RewindAssets.badgeDucky,
    Rect.fromLTWH(-18, 375.5, 375, 415),
    stateMachine: "State Machine",
    ticks: [(RewindTick.bold, Rect.fromLTWH(206, 384, 16, 25))],
    pivot: Offset(154, 746),
  ),
);

const setupPages = [
  paletteSetupPage,
  placesSetupPage,
  peopleSetupPage,
  busiestDaySetupPage,
  newFacesSetupPage,
  favouritesSetupPage,
  ritualSetupPage,
  likesSetupPage,
  mosaicSetupPage,
  badgeSetupPage,
];
