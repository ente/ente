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
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";

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
const _podiumPlaces = 3;
const _stampsPerPlace = 3;
const _galleryPhotos = 9;
const _minimumPolaroids = 3;
const _boothStrips = 3;
const _newFaceBubbles = 6;
const _newFacePhotos = 9;
const _minimumNewFaces = 3;

RewindChapter _totals(rust.Totals? totals) {
  return RewindChapter([PhotosCountPage.pageKey, TopPercentPage.pageKey], (
    media,
  ) async {
    if (totals == null) return const [];
    final top = totals.topPerMille;
    return [
      PhotosCountPage(
        totals.files,
        media.glimpses(totals.fileIds, PhotosCountPage.maxPhotos),
      ),
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
      for (final (rank, city) in places.cities.take(_quizCities).indexed)
        _placeStamp(media, city, rank < _podiumPlaces),
    ];
    return stamps.length < 3 ? null : PlacesQuizPage(places, stamps);
  });
}

PlaceStamp _placeStamp(RewindMedia media, rust.RewindCity city, bool podium) {
  final picked = media.photos(city.fileIds, podium ? _stampsPerPlace : 1);
  return (
    city: city,
    photo: picked.firstOrNull,
    extras: picked.skip(1).toList(),
    gallery: podium
        ? media.extraPhotos(city.fileIds, _galleryPhotos)
        : const [],
  );
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
      final booth = media.photos(
        winner.person.fileIds,
        _boothStrips * RewindBoothStrip.frames,
      );
      final hasBooth = booth.length >= RewindBoothStrip.frames;
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
    final faces = <NewFaceBubble>[];
    for (final face in newFaces.faces) {
      if (faces.length == _newFaceBubbles) break;
      final resolved = await _newFace(media, face);
      if (resolved != null) faces.add(resolved);
    }
    return faces.length < _minimumNewFaces
        ? null
        : NewFacesPage(newFaces, faces);
  });
}

Future<NewFaceBubble?> _newFace(RewindMedia media, rust.NewFace newFace) async {
  final face = switch ((newFace.personId, newFace.clusterId)) {
    (final personId?, _) => await media.person(personId, newFace.faceIds),
    (_, final clusterId?) => await media.cluster(clusterId, newFace.faceIds),
    _ => null,
  };
  if (face?.crop == null) return null;
  return (
    face: face!,
    photos: media.extraPhotos(newFace.fileIds, _newFacePhotos),
  );
}

RewindChapter _favourites(rust.Favourites? favourites) {
  return RewindChapter.revealed(favouritesSetupPage, "favourites", (media) {
    if (favourites == null) return null;
    final photos = media.photos(favourites.fileIds, 9);
    return photos.isEmpty ? null : FavouritesPage(favourites, photos);
  });
}

RewindChapter _weeklyHabit(rust.WeeklyHabit? habit) {
  return RewindChapter.revealed(ritualSetupPage, "weekly_habit", (media) {
    if (habit == null) return null;
    final hourPhotos = media.photos(
      habit.hourFileIds,
      WeeklyHabitPage.maxHourPhotos,
    );
    return WeeklyHabitPage(
      habit,
      hourPhotos,
      hourPhotos.isEmpty
          ? const []
          : media.photos(habit.fileIds, WeeklyHabitPage.maxRingPhotos),
    );
  });
}

RewindChapter _crowdFavourite(rust.CrowdFavourite? crowd) {
  return RewindChapter.revealed(likesSetupPage, "crowd_favourite", (media) {
    for (final liked in crowd?.photos ?? const <rust.LikedPhoto>[]) {
      final file = media.photo(liked.fileId);
      if (file != null) return CrowdFavouritePage(file);
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
