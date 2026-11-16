import "dart:async";

import "package:flutter/painting.dart" show Offset;
import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/pages/art_twin_page.dart";
import "package:photos/ui/rewind/pages/badge_reveal_page.dart";
import "package:photos/ui/rewind/pages/busiest_day_page.dart";
import "package:photos/ui/rewind/pages/colour_page.dart";
import "package:photos/ui/rewind/pages/cover_page.dart";
import "package:photos/ui/rewind/pages/crowd_favourite_page.dart";
import "package:photos/ui/rewind/pages/favourites_page.dart";
import "package:photos/ui/rewind/pages/globe_page.dart";
import "package:photos/ui/rewind/pages/mosaic_page.dart";
import "package:photos/ui/rewind/pages/new_faces_page.dart";
import "package:photos/ui/rewind/pages/people_race_page.dart";
import "package:photos/ui/rewind/pages/photo_booth_page.dart";
import "package:photos/ui/rewind/pages/photos_count_page.dart";
import "package:photos/ui/rewind/pages/places_quiz_page.dart";
import "package:photos/ui/rewind/pages/ritual_streak_page.dart";
import "package:photos/ui/rewind/pages/scrapbook_page.dart";
import "package:photos/ui/rewind/pages/setup_page.dart";
import "package:photos/ui/rewind/pages/setup_pages.dart";
import "package:photos/ui/rewind/pages/spots_page.dart";
import "package:photos/ui/rewind/pages/timelapse_page.dart";
import "package:photos/ui/rewind/pages/top_percent_page.dart";
import "package:photos/ui/rewind/pages/tour_page.dart";
import "package:photos/ui/rewind/pages/tower_page.dart";
import "package:photos/ui/rewind/pages/warp_page.dart";
import "package:photos/ui/rewind/pages/weekly_habit_page.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/ui/rewind/story/rewind_media.dart";
import "package:photos/ui/rewind/story/rewind_rituals.dart";
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

List<RewindChapter> rewindChapters(
  rust.RewindReport report,
  RewindRituals? rituals,
) => [
  RewindChapter([const CoverPage().key], (_) async => const [CoverPage()]),
  _warp(report),
  _totals(report.totals),
  _tower(report),
  _colour(report.colour),
  _places(report.places, showDistance: report.globe == null),
  _tour(report.tour),
  _globe(report.globe),
  _spots(report.spots),
  _peopleRace(report.peopleRace),
  _timelapse(report),
  _busiestDay(report.busiestDay),
  _newFaces(report.newFaces),
  _favourites(report.favourites),
  _weeklyHabit(report.weeklyHabit),
  _crowdFavourite(report.crowdFavourite),
  ritualStreakChapter(rituals),
  _mosaic(report),
  _badge(report.badge),
  _scrapbook(report),
];

List<RewindChapter> rewindPhotoCardChapters(rust.RewindReport report) => [
  _warp(report),
  _tower(report),
  _globe(report.globe),
  _timelapse(report),
  _mosaic(report),
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
    final top = totals.topPercent;
    return [
      PhotosCountPage(
        totals.files,
        media.glimpses(totals.fileIds, PhotosCountPage.maxPhotos),
      ),
      if (top != null) TopPercentPage(percent: top, count: totals.files),
    ];
  });
}

RewindChapter _tour(rust.Tour? tour) => RewindChapter([
  TourPage.pageKey,
], (_) async => [if (tour != null) TourPage(tour)]);

RewindChapter _warp(rust.RewindReport report) =>
    RewindChapter([WarpPage.pageKey], (media) async {
      final warp = report.warp;
      if (warp == null) return const [];
      final first = _file(media, warp.fileIds.inner.last);
      final panels = media.extraPhotos(
        warp.fileIds,
        warp.fileIds.length,
        preloadRemote: true,
      );
      if (first == null || panels.length < WarpPage.minimumPanels) {
        return const [];
      }
      return [WarpPage(photos: panels, first: first)];
    });

RewindChapter _tower(rust.RewindReport report) =>
    RewindChapter([TowerPage.pageKey], (media) async {
      final totals = report.totals;
      if (totals == null || totals.files < TowerPage.minimumPrints) {
        return const [];
      }
      final photos = media.extraPhotos(
        report.mosaic?.fileIds ?? totals.fileIds,
        TowerPage.tiles,
      );
      return photos.isEmpty
          ? const []
          : [TowerPage(prints: totals.files, photos: photos)];
    });

RewindChapter _globe(rust.Globe? globe) =>
    RewindChapter([GlobePage.pageKey], (media) async {
      if (globe == null) return const [];
      return [
        GlobePage(globe, [
          for (final place in globe.places)
            media.photos(place.fileIds, 1).firstOrNull,
        ]),
      ];
    });

RewindChapter _timelapse(rust.RewindReport report) =>
    RewindChapter([TimelapsePage.pageKey], (media) async {
      final lapse = report.timelapse;
      if (lapse == null) return const [];
      final frames = <RewindLapseFrame>[
        for (final frame in lapse.frames)
          if (_file(media, frame.fileId) case final file?)
            (
              file: file,
              month: frame.month,
              day: frame.day,
              leftEye: Offset(frame.leftEyeX / 1e5, frame.leftEyeY / 1e5),
              rightEye: Offset(frame.rightEyeX / 1e5, frame.rightEyeY / 1e5),
            ),
      ];
      final name = lapse.isMe ? null : media.personName(lapse.personId);
      if (frames.length < TimelapsePage.minimumFrames ||
          (!lapse.isMe && name == null)) {
        return const [];
      }
      return [
        TimelapsePage(frames: frames, name: name, photoCount: lapse.photoCount),
      ];
    });

EnteFile? _file(RewindMedia media, int fileId) =>
    media.extraPhotos(Int64List.fromList([fileId]), 1).firstOrNull;

RewindChapter _mosaic(rust.RewindReport report) =>
    RewindChapter([MosaicPage.pageKey], (media) async {
      final mosaic = report.mosaic;
      if (mosaic == null) return const [];
      final files = media.extraPhotos(mosaic.fileIds, mosaic.fileIds.length);
      if (files.length < MosaicPage.minimumTiles) return const [];
      final me = switch (mosaic.mePersonId) {
        final id? => await media.person(id, mosaic.meFaceIds),
        null => null,
      };
      final favourite = switch (mosaic.topPersonId) {
        final id? when me?.crop == null => await media.person(
          id,
          mosaic.topFaceIds,
        ),
        _ => null,
      };
      return [
        MosaicPage(
          files: files,
          subject: me?.crop ?? favourite?.crop,
          subjectName: me?.crop == null ? favourite?.name : null,
        ),
      ];
    });

RewindChapter _colour(rust.ColourOfTheYear? colour) => RewindChapter(
  [paletteSetupPage.key, ColourPage.pageKey, ArtTwinPage.pageKey],
  (media) async {
    if (colour == null) return const [];
    final photos = media.photos(colour.fileIds, 9);
    if (photos.isEmpty) return const [];
    return [
      paletteSetupPage,
      ColourPage(colour, photos),
      ArtTwinPage(colour.colour),
    ];
  },
);

RewindChapter _places(rust.Places? places, {required bool showDistance}) {
  return RewindChapter.revealed(placesSetupPage, PlacesQuizPage.pageKey, (
    media,
  ) {
    if (places == null) return null;
    final stamps = [
      for (final (rank, city) in places.cities.take(_quizCities).indexed)
        _placeStamp(media, city, rank < _podiumPlaces),
    ];
    return stamps.length < 3
        ? null
        : PlacesQuizPage(places, stamps, showDistance: showDistance);
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
    [peopleSetupPage.key, PeopleRacePage.pageKey, ...PhotoBoothPage.pageKeys],
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
      return [
        peopleSetupPage,
        PeopleRacePage(runners),
        for (final (place, runner) in runners.indexed)
          ?await _photoBooth(media, runner, place),
      ];
    },
  );
}

Future<PhotoBoothPage?> _photoBooth(
  RewindMedia media,
  RaceRunner runner,
  int place,
) async {
  final photos = media.photos(
    runner.person.fileIds,
    _boothStrips * RewindBoothStrip.frames,
  );
  if (photos.length < RewindBoothStrip.frames) return null;
  return PhotoBoothPage(
    person: runner.face,
    count: runner.person.photoCount,
    photos: photos,
    focus: await media.faceFocus(runner.person.personId, photos),
    place: place,
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

RewindChapter ritualStreakChapter(RewindRituals? rituals) => RewindChapter(
  [ritualStreakSetupKey, RitualStreakPage.pageKey],
  (_) async => [
    if (rituals != null) ...[
      ritualStreakSetupPage(rituals),
      RitualStreakPage(rituals),
    ],
  ],
);

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
