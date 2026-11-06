import "dart:async";

import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/pages/badge_reveal_page.dart";
import "package:photos/ui/rewind/pages/busiest_day_page.dart";
import "package:photos/ui/rewind/pages/colour_page.dart";
import "package:photos/ui/rewind/pages/cover_page.dart";
import "package:photos/ui/rewind/pages/crowd_favourite_page.dart";
import "package:photos/ui/rewind/pages/favourites_page.dart";
import "package:photos/ui/rewind/pages/new_faces_page.dart";
import "package:photos/ui/rewind/pages/people_race_page.dart";
import "package:photos/ui/rewind/pages/photo_booth_page.dart";
import "package:photos/ui/rewind/pages/photos_count_page.dart";
import "package:photos/ui/rewind/pages/places_quiz_page.dart";
import "package:photos/ui/rewind/pages/scrapbook_page.dart";
import "package:photos/ui/rewind/pages/setup_page.dart";
import "package:photos/ui/rewind/pages/setup_pages.dart";
import "package:photos/ui/rewind/pages/spots_page.dart";
import "package:photos/ui/rewind/pages/top_percent_page.dart";
import "package:photos/ui/rewind/pages/weekly_habit_page.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/ui/rewind/story/rewind_media.dart";

class RewindChapter {
  const RewindChapter(this.keys, this.compose);

  RewindChapter.revealed(
    SetupPage setup,
    String revealKey,
    FutureOr<RewindPage?> Function(RewindMedia media) reveal,
  ) : this([setup.key, revealKey], (media) async {
        final page = await reveal(media);
        return page == null ? const [] : [setup, page];
      });

  final List<String> keys;
  final Future<List<RewindPage>> Function(RewindMedia media) compose;
}

List<String> rewindOutline(rust.RewindReport report) => [
  for (final chapter in rewindChapters(report)) ...chapter.keys,
];

List<RewindChapter> rewindChapters(rust.RewindReport report) => [
  RewindChapter([const CoverPage().key], (_) async => const [CoverPage()]),
  ?_totals(report.totals),
  ?_colour(report.colour),
  ?_places(report.places),
  ?_spots(report.spots),
  ?_peopleRace(report.peopleRace),
  ?_busiestDay(report.busiestDay),
  ?_newFaces(report.newFaces),
  ?_favourites(report.favourites),
  ?_weeklyHabit(report.weeklyHabit),
  ?_crowdFavourite(report.crowdFavourite),
  ?_badge(report.badge),
  ?_scrapbook(report),
];

const _quizCities = 6;
const _minimumPolaroids = 3;
const _boothPhotos = 4;
const _newFaceBubbles = 6;
const _minimumNewFaces = 3;

RewindChapter? _totals(rust.Totals? totals) {
  if (totals == null) return null;
  final top = totals.topPercent;
  final ranked = top != null && top <= 25 ? top : null;
  return RewindChapter(
    [PhotosCountPage.pageKey, if (ranked != null) TopPercentPage.pageKey],
    (_) async => [
      PhotosCountPage(totals.files),
      if (ranked != null) TopPercentPage(percent: ranked, count: totals.files),
    ],
  );
}

RewindChapter? _colour(rust.ColourOfTheYear? colour) {
  if (colour == null) return null;
  return RewindChapter.revealed(paletteSetupPage, ColourPage.pageKey, (media) {
    final photos = media.photos(colour.fileIds, 9);
    return photos.isEmpty ? null : ColourPage(colour, photos);
  });
}

RewindChapter? _places(rust.Places? places) {
  if (places == null) return null;
  return RewindChapter.revealed(placesSetupPage, PlacesQuizPage.pageKey, (
    media,
  ) {
    final stamps = [
      for (final city in places.cities.take(_quizCities))
        (city: city, photo: media.photos(city.fileIds, 1).firstOrNull),
    ];
    return stamps.length < 3 ? null : PlacesQuizPage(places, stamps);
  });
}

RewindChapter? _spots(rust.Spots? spots) {
  if (spots == null) return null;
  return RewindChapter.revealed(spotsSetupPage, SpotsPage.pageKey, (media) {
    final photos = media.photos(spots.fileIds, 9);
    return photos.length < _minimumPolaroids ? null : SpotsPage(spots, photos);
  });
}

RewindChapter? _peopleRace(rust.PeopleRace? race) {
  if (race == null ||
      race.people.length < 3 ||
      race.people.any((person) => person.monthlyCounts.length != 12)) {
    return null;
  }
  return RewindChapter(
    [peopleSetupPage.key, PeopleRacePage.pageKey, PhotoBoothPage.pageKey],
    (media) async {
      final people = race.people.take(3).toList();
      final faces = await Future.wait([
        for (final person in people)
          media.person(person.personId, person.faceIds),
      ]);
      final runners = [
        for (final (i, person) in people.indexed)
          if (faces[i] case final face?) (face: face, person: person),
      ];
      if (runners.length < 3) return const [];
      final winner = runners.first;
      final booth = media.photos(winner.person.fileIds, _boothPhotos);
      final hasBooth = booth.length >= _boothPhotos;
      return [
        peopleSetupPage,
        PeopleRacePage(runners),
        if (hasBooth)
          PhotoBoothPage(
            person: winner.face,
            count: winner.person.photoCount,
            photos: booth,
            focus: await media.faceFocus(winner.person.personId, booth),
          ),
      ];
    },
  );
}

RewindChapter? _busiestDay(rust.BusiestDay? day) {
  if (day == null) return null;
  return RewindChapter.revealed(busiestDaySetupPage, "busiest_day", (media) {
    final photos = media.photos(day.fileIds, 8);
    return photos.length < 2 ? null : BusiestDayPage(day, photos);
  });
}

RewindChapter? _newFaces(rust.NewFaces? newFaces) {
  if (newFaces == null) return null;
  return RewindChapter.revealed(newFacesSetupPage, "new_faces", (media) async {
    final resolved = await Future.wait([
      for (final face in newFaces.faces)
        if (face.personId case final personId?)
          media.person(personId, face.faceIds)
        else if (face.clusterId case final clusterId?)
          media.cluster(clusterId, face.faceIds),
    ]);
    final faces = [
      for (final face in resolved)
        if (face?.crop != null) face!,
    ].take(_newFaceBubbles).toList();
    return faces.length < _minimumNewFaces
        ? null
        : NewFacesPage(newFaces, faces);
  });
}

RewindChapter? _favourites(rust.Favourites? favourites) {
  if (favourites == null) return null;
  return RewindChapter.revealed(favouritesSetupPage, "favourites", (media) {
    final photos = media.photos(favourites.fileIds, 9);
    return photos.isEmpty ? null : FavouritesPage(favourites, photos);
  });
}

RewindChapter? _weeklyHabit(rust.WeeklyHabit? habit) {
  if (habit == null) return null;
  return RewindChapter.revealed(
    ritualSetupPage,
    "weekly_habit",
    (_) => WeeklyHabitPage(habit),
  );
}

RewindChapter? _crowdFavourite(rust.CrowdFavourite? crowd) {
  if (crowd == null) return null;
  return RewindChapter.revealed(likesSetupPage, "crowd_favourite", (media) {
    for (final liked in crowd.photos) {
      final file = media.photo(liked.fileId);
      if (file != null) return CrowdFavouritePage(liked, file);
    }
    return null;
  });
}

RewindChapter? _badge(rust.Badge? badge) {
  if (badge == null) return null;
  return RewindChapter.revealed(
    badgeSetupPage,
    "badge",
    (_) => BadgeRevealPage(badge),
  );
}

RewindChapter? _scrapbook(rust.RewindReport report) {
  final scrapbook = report.scrapbook;
  if (scrapbook == null) return null;
  final racers = report.peopleRace?.people ?? const <rust.RacePerson>[];
  final cities = report.places?.cities ?? const <rust.RewindCity>[];
  return RewindChapter(["scrapbook"], (media) async {
    final photos = media.photos(scrapbook.fileIds, 6);
    if (photos.isEmpty) return const [];
    final people = <RewindFace>[
      for (final racer in racers)
        ?await media.person(racer.personId, racer.faceIds),
    ];
    return [
      ScrapbookPage(
        report: report,
        photos: photos,
        people: people,
        cityNames: [for (final city in cities.take(3)) city.name],
      ),
    ];
  });
}
