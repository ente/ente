import "package:flutter/painting.dart";
import "package:photos/ui/rewind/pages/setup_page.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stickers.dart";

const paletteSetupPage = SetupPage(
  key: "palette_setup",
  color: Color(0xFF14BD2E),
  pattern: Color(0xFF14B62D),
  ink: RewindColors.white,
  chrome: RewindChrome.dark,
  headlines: [
    SetupHeadline(
      "YOUR YEAR\nHAD A COLOUR\nPALETTE.",
      at: Offset(32, 126),
      size: 47,
      height: 0.84,
      width: 326,
    ),
  ],
  callout: SetupCallout(
    "AND IT WAS\nVERY YOU.",
    center: Offset(178, 422.5),
    delayMs: 600,
    onTop: true,
  ),
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
  color: Color(0xFF3F78F0),
  pattern: Color(0xFF4A82F5),
  ink: RewindColors.cream,
  headlines: [
    SetupHeadline("YOU WENT\nPLACES.", at: Offset(24, 140), size: 66),
  ],
  callout: SetupCallout(
    "THE CAMERA\nCAME TOO.",
    center: Offset(201.5, 426),
    delayMs: 600,
  ),
  art: SetupArt.ducky(
    RewindAssets.globeDucky,
    Rect.fromLTWH(0, 471, 390.2, 310.4),
    ticks: [(RewindTick.forward, Rect.fromLTWH(194, 486, 11, 18))],
    pivot: Offset(195, 758),
    delayMs: 780,
  ),
);

const spotsSetupPage = SetupPage(
  key: "spots_setup",
  color: Color(0xFFFFCA39),
  pattern: Color(0xFFFFD24E),
  ink: RewindColors.ink,
  chrome: RewindChrome.dark,
  headlines: [
    SetupHeadline("YOU HAVE\nYOUR SPOTS.", at: Offset(24, 140), size: 54),
  ],
  callout: SetupCallout(
    "WE NOTICED.",
    center: Offset(215.2, 385.5),
    delayMs: 600,
  ),
  art: SetupArt.ducky(
    RewindAssets.chairDucky,
    Rect.fromLTWH(22, 401, 310.4, 373.1),
    ticks: [(RewindTick.forward, Rect.fromLTWH(229, 423, 11, 18))],
    pivot: Offset(176, 752),
    delayMs: 780,
  ),
);

const peopleSetupPage = SetupPage(
  key: "people_setup",
  color: Color(0xFF9D4AE4),
  pattern: Color(0xFF993EE9),
  ink: RewindColors.cream,
  headlines: [
    SetupHeadline(
      "SOME FACES\nKEPT SHOWING\nUP.",
      at: Offset(24, 140),
      size: 46,
    ),
  ],
  callout: SetupCallout(
    "LIKE, A LOT!",
    center: Offset(198, 463.9),
    turn: -3.1,
    delayMs: 600,
  ),
  art: SetupArt.ducky(
    RewindAssets.hugDucky,
    Rect.fromLTWH(-46, 379, 484.3, 484.3),
    pivot: Offset(195, 840),
    delayMs: 780,
  ),
);

const busiestDaySetupPage = SetupPage(
  key: "busiest_day_setup",
  color: Color(0xFFFF6727),
  pattern: Color(0xFFFC5D19),
  ink: RewindColors.cream,
  headlines: [
    SetupHeadline("ONE DAY,\nTHINGS GOT", at: Offset(24, 140), size: 59),
  ],
  callout: SetupCallout(
    "OUT OF HAND.",
    center: Offset(201.2, 350),
    onTop: true,
  ),
  art: SetupArt.image(
    RewindAssets.photoHeapDucky,
    Rect.fromLTWH(-75, 281, 540, 540),
    preset: RewindPreset.crowd,
    delayMs: 250,
  ),
);

const newFacesSetupPage = SetupPage(
  key: "new_faces_setup",
  color: Color(0xFF1EB736),
  pattern: Color(0xFF1DB034),
  ink: RewindColors.cream,
  headlines: [
    SetupHeadline("THE CAST GOT\nBIGGER", at: Offset(24, 140), size: 39),
  ],
  callout: SetupCallout(
    "WELCOME TO FAM!",
    center: Offset(186.6, 334.2),
    turn: -4.5,
  ),
  art: SetupArt.ducky(
    RewindAssets.famDucky,
    Rect.fromLTWH(-124, 350, 579, 547.8),
    pivot: Offset(195, 844),
  ),
);

const favouritesSetupPage = SetupPage(
  key: "favourites_setup",
  color: Color(0xFFFB4196),
  pattern: Color(0xFFFF4D9F),
  ink: RewindColors.cream,
  headlines: [
    SetupHeadline("SOME PHOTOS\nHIT DIFFERENT.", at: Offset(24, 140), size: 48),
  ],
  callout: SetupCallout(
    "AND THEY GOT A STAR!",
    center: Offset(199, 391),
    size: 29.01,
  ),
  art: SetupArt.ducky(
    RewindAssets.photosDucky,
    Rect.fromLTWH(-140, 392, 605.3, 426.5),
    pivot: Offset(195, 795),
  ),
);

const ritualSetupPage = SetupPage(
  key: "ritual_setup",
  color: Color(0xFFFFCA39),
  pattern: Color(0xFFFFD24E),
  ink: RewindColors.ink,
  chrome: RewindChrome.dark,
  headlines: [
    SetupHeadline("SOME THINGS\nYOU DID LIKE", at: Offset(24, 140), size: 50),
    SetupHeadline(
      "CLOCKWORK.",
      at: Offset(29.4, 233),
      size: 50,
      turn: 0.44,
      delayMs: 120,
    ),
  ],
  callout: SetupCallout(
    "ALMOST TIME!",
    center: Offset(217.7, 407.5),
    delayMs: 650,
    onTop: true,
  ),
  art: SetupArt.ducky(
    RewindAssets.cameraDucky,
    Rect.fromLTWH(27, 411, 296.3, 373),
    pivot: Offset(175, 762),
    delayMs: 830,
  ),
);

const likesSetupPage = SetupPage(
  key: "likes_setup",
  color: Color(0xFF2F65D7),
  pattern: Color(0xFF3670EB),
  ink: RewindColors.cream,
  headlines: [
    SetupHeadline("SOME PHOTOS\nGOT LIKES.", at: Offset(24, 140), size: 48),
  ],
  callout: SetupCallout("ONE GOT A LOT.", center: Offset(188.2, 383.5)),
  art: SetupArt.image(
    RewindAssets.polaroidHugDucky,
    Rect.fromLTWH(46, 434, 296, 328),
  ),
);

const badgeSetupPage = SetupPage(
  key: "badge_setup",
  color: Color(0xFF0DBE28),
  pattern: Color(0xFF11B72A),
  ink: RewindColors.cream,
  headlines: [
    SetupHeadline(
      "WE STUDIED\nYOUR CAMERA\nROLL.",
      at: Offset(24, 140),
      size: 45,
    ),
  ],
  callout: SetupCallout(
    "I HAVE A THEORY ABOUT YOU",
    center: Offset(196.5, 395),
    size: 23.87,
  ),
  art: SetupArt.image(
    RewindAssets.detectiveDucky,
    Rect.fromLTWH(39, 445, 286, 331),
    ticks: [(RewindTick.bold, Rect.fromLTWH(209, 424, 16, 23))],
    pivot: Offset(182, 777),
  ),
);

const setupPages = [
  paletteSetupPage,
  placesSetupPage,
  spotsSetupPage,
  peopleSetupPage,
  busiestDaySetupPage,
  newFacesSetupPage,
  favouritesSetupPage,
  ritualSetupPage,
  likesSetupPage,
  badgeSetupPage,
];
