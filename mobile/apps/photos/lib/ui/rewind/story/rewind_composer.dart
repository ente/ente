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

List<RewindChapter> rewindChapters(rust.RewindReport report) => [
  RewindChapter([const CoverPage().key], (_) async => const [CoverPage()]),
  _totals(report.totals),
  _colour(report.colour),
  _places(report.places),
  _spots(report.spots),
  _peopleRace(report.peopleRace),
  _busiestDay(report.busiestDay),
  _newFaces(report.newFaces),
  _favourites(report.favourites),
  _weeklyHabit(report.weeklyHabit),
  _crowdFavourite(report.crowdFavourite),
  _badge(report.badge),
  _scrapbook(report),
];

const _quizCities = 6;
const _minimumPolaroids = 3;
const _boothPhotos = 4;
const _newFaceBubbles = 6;
const _minimumNewFaces = 3;

RewindChapter _totals(rust.Totals? totals) {
  return RewindChapter([PhotosCountPage.pageKey, TopPercentPage.pageKey], (
    _,
  ) async {
    if (totals == null) return const [];
    final top = totals.topPerMille;
    return [
      PhotosCountPage(totals.files),
      if (top != null) TopPercentPage(perMille: top, count: totals.files),
    ];
  });
}

RewindChapter _colour(rust.ColourOfTheYear? colour) {
  return RewindChapter.revealed(paletteSetupPage, ColourPage.pageKey, (media) {
    if (colour == null) return null;
    final photos = media.photos(colour.fileIds, 9);
    return photos.isEmpty ? null : ColourPage(colour, photos);
  });
}

RewindChapter _places(rust.Places? places) {
  return RewindChapter.revealed(placesSetupPage, PlacesQuizPage.pageKey, (
    media,
  ) {
    if (places == null) return null;
    final stamps = [
      for (final city in places.cities.take(_quizCities))
        (city: city, photo: media.photos(city.fileIds, 1).firstOrNull),
    ];
    return stamps.length < 3 ? null : PlacesQuizPage(places, stamps);
  });
}

RewindChapter _spots(rust.Spots? spots) {
  return RewindChapter.revealed(spotsSetupPage, SpotsPage.pageKey, (media) {
    if (spots == null) return null;
    final photos = media.photos(spots.fileIds, 9);
    return photos.length < _minimumPolaroids ? null : SpotsPage(spots, photos);
  });
}

RewindChapter _peopleRace(rust.PeopleRace? race) {
  return RewindChapter(
    [peopleSetupPage.key, PeopleRacePage.pageKey, PhotoBoothPage.pageKey],
    (media) async {
      if (race == null ||
          race.people.length < 3 ||
          race.people.any((person) => person.monthlyCounts.length != 12)) {
        return const [];
      }
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

RewindChapter _busiestDay(rust.BusiestDay? day) {
  return RewindChapter.revealed(busiestDaySetupPage, "busiest_day", (media) {
    if (day == null) return null;
    final photos = media.photos(day.fileIds, 8);
    return photos.length < 2 ? null : BusiestDayPage(day, photos);
  });
}

RewindChapter _newFaces(rust.NewFaces? newFaces) {
  return RewindChapter.revealed(newFacesSetupPage, "new_faces", (media) async {
    if (newFaces == null) return null;
    final faces = <RewindFace>[];
    for (final face in newFaces.faces) {
      if (faces.length == _newFaceBubbles) break;
      final resolved = switch ((face.personId, face.clusterId)) {
        (final personId?, _) => await media.person(personId, face.faceIds),
        (_, final clusterId?) => await media.cluster(clusterId, face.faceIds),
        _ => null,
      };
      if (resolved?.crop != null) faces.add(resolved!);
    }
    return faces.length < _minimumNewFaces
        ? null
        : NewFacesPage(newFaces, faces);
  });
}

RewindChapter _favourites(rust.Favourites? favourites) {
  return RewindChapter.revealed(favouritesSetupPage, "favourites", (media) {
    if (favourites == null) return null;
    final photos = media.photos(favourites.fileIds, 9);
    return photos.isEmpty ? null : FavouritesPage(favourites, photos);
  });
}

RewindChapter _weeklyHabit(rust.WeeklyHabit? habit) {
  return RewindChapter.revealed(
    ritualSetupPage,
    "weekly_habit",
    (_) => habit == null ? null : WeeklyHabitPage(habit),
  );
}

RewindChapter _crowdFavourite(rust.CrowdFavourite? crowd) {
  return RewindChapter.revealed(likesSetupPage, "crowd_favourite", (media) {
    for (final liked in crowd?.photos ?? const <rust.LikedPhoto>[]) {
      final file = media.photo(liked.fileId);
      if (file != null) return CrowdFavouritePage(liked, file);
    }
    return null;
  });
}

RewindChapter _badge(rust.Badge? badge) {
  return RewindChapter.revealed(
    badgeSetupPage,
    "badge",
    (_) => badge == null ? null : BadgeRevealPage(badge),
  );
}

RewindChapter _scrapbook(rust.RewindReport report) {
  final scrapbook = report.scrapbook;
  final racers = report.peopleRace?.people ?? const <rust.RacePerson>[];
  final cities = report.places?.cities ?? const <rust.RewindCity>[];
  return RewindChapter(["scrapbook"], (media) async {
    if (scrapbook == null) return const [];
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
