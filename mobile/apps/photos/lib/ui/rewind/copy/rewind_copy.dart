import "package:flutter/widgets.dart";
import "package:photos/locale.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_copy_en.dart";
import "package:photos/ui/rewind/copy/rewind_copy_nl.dart";

typedef RewindLines = ({String you, String me});

typedef RewindSetupLines = ({List<String> headlines, String callout});

typedef RewindBadgeCopy = ({
  String title,
  String pronunciation,
  String definition,
});

enum RewindSetup {
  palette,
  places,
  people,
  busiestDay,
  newFaces,
  favourites,
  ritual,
  ritualStreak,
  likes,
  mosaic,
  badge,
}

abstract class RewindCopy {
  const RewindCopy();

  static RewindCopy of(BuildContext context) =>
      forLocale(context.findAncestorWidgetOfExactType<Localizations>()?.locale);

  static Future<RewindCopy> current() async => forLocale(await getLocale());

  static RewindCopy forLocale(Locale? locale) => switch (locale?.languageCode) {
    "nl" => const DutchRewindCopy(),
    _ => const EnglishRewindCopy(),
  };

  String number(int value);
  String photoTally(String number, int count);
  String photos(int count) => photoTally(number(count), count);
  String photoUnit(int count);
  String shortDate(int day, int month, int year);
  String monthBanner(int month);
  String monthName(int month);

  String get close;
  String get playMusic;
  String get muteMusic;
  String get share;
  String get shareVideo;
  String get nextCard;
  String pageOf(int page, int count);
  String get dismiss;

  String get watch;
  String get watchAgain;
  String get resume;
  String get newStatus;
  String get newSticker;
  String progress(int page, int count);

  String get readyTitle;
  String get readyBody;
  String get newCardsTitle;
  String get newCardsBody;

  RewindLines get coverTagline;
  String get tapToStart;

  RewindSetupLines setup(RewindSetup setup);

  String tunnelAgo(int days);
  String get tunnelStartTitle;
  RewindLines get tunnelStartBody;
  String get tunnelGoOnHint;
  String get tunnelFlyBackHint;
  String tunnelMomentEyebrow(DateTime day);
  String get tunnelMomentTitle;
  RewindLines get tunnelMomentBody;
  String get tunnelLoading;
  String get tunnelFlyAgain;

  RewindLines get photosCountKicker;
  String memoriesUnit(int count);

  RewindLines get topPercentKicker;
  String topPercent(int percent);
  String memoriesSaved(int count);

  String get placesQuestion;
  String get placesHint;
  String placesPicked(String city);
  RewindLines placesHeading({required bool travelled});
  String distance(int km);
  String placesWon(String city, int photos);
  String placesNext(List<String> cities);
  String placesPlaced(String city, int place);
  String placesHad(String city, int photos);

  RewindLines get globeKicker;
  String globeLaps(double laps);
  String globeLapShare(int percent);
  String get globeHint;
  String globeLabel(int km, String laps);
  String globeTally(int cities, int countries);

  String get raceQuestion;
  String get raceHint;
  String racePicked(String name);
  String raceOvertakes(String passer, String passed);
  String raceWinner(String name);
  RewindLines get raceCalledIt;
  String get raceClose;
  String get raceMissed;
  RewindLines get racePick;

  RewindLines boothBilling(int place);
  String boothPhotos(int count);

  RewindLines busiestDayKicker(int day, int month);
  String get busiestDayLine;

  String newFacesTitle(int count);
  RewindLines newFacesLine(int count);

  String colourName(rust.RewindColour colour);
  RewindLines colourLine(int percent, rust.RewindColour colour);

  String get favouritesTitle;
  String get myFavouritesTitle;
  String get myFavouriteTitle;
  String get favouritesLine;
  String get favouriteLine;
  String get favouritesLabel;

  RewindLines get habitKicker;
  String clockHour(int hour);
  String habitTitle(int weekday, int hour);
  RewindLines habitLine(int percent, int weekday);
  String habitLabel(String title, String line);
  String weekdayInitial(int weekday);

  String get crowdFavouriteTitle;
  RewindLines get crowdFavouriteLine;
  String get crowdFavouriteLabel;

  RewindLines get streakKicker;
  String checkInsLabel(int count);
  String ritualsContinuedLabel(int count);
  String get mostActiveMonthLabel;
  String streakLabel({
    required int streak,
    required int checkIns,
    required int month,
    required int continued,
  });

  RewindLines get mosaicSelf;
  String get familiarFace;
  String mosaicMoments(int count);
  String get mosaicHint;

  RewindBadgeCopy badge(rust.RewindBadge badge);
  String badgePronunciation(String pronunciation);
  String get badgeHeading;
  String get badgeHeadingLabel;
  String badgeLabel(String title);
  String get badgeHint;

  String get scrapbookPhotos;
  String get scrapbookColour;
  String get scrapbookPeople;
  String get scrapbookPlaces;
  String get scrapbookTop;

  String get finaleTop;
  String get finaleBottom;
  String get finaleLabel;
  String get saveVideo;
  String get savedVideo;
  String get shareRewind;

  String get endCardTagline;

  String get videoTitle;
  List<String> get videoQuips;
  String get videoPreparing;
  String get videoWrapped;
  String get videoDone;
  String get videoAlmostDone;
  String get videoKeepOpen;
  String get cancel;
  String get alreadySaved;
  String get backingUp;
  String get savedAndBackingUp;
}
