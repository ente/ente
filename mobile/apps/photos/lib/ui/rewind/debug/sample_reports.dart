import "dart:typed_data" show Uint32List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:photos/src/rust/api/rewind_api.dart" as rust;

final rewindSampleReports = {
  "Busy year": _busyYear,
  "Top 10%, four places": _topTenYear,
  "Top 25%, three places, no distance": _topQuarterYear,
  "Sparse year": _sparseYear,
  "One file": const rust.RewindReport(totals: rust.Totals(files: 1)),
  "No chapters": const rust.RewindReport(),
};

Int64List _ids(int first, int count) => Int64List.fromList([
  for (var index = 0; index < count; index++) first + index,
]);

rust.RewindCity _city(String name, int photoCount, int firstFileId) =>
    rust.RewindCity(
      name: name,
      country: "",
      photoCount: photoCount,
      fileIds: _ids(firstFileId, 3),
    );

List<String> _faceIds(int firstFileId, int count) => [
  for (var index = 0; index < count; index++)
    "${firstFileId + index}_31250_18750_56250_50000",
];

final _busyYear = rust.RewindReport(
  totals: const rust.Totals(files: 12480, topPercent: 1),
  colour: rust.ColourOfTheYear(
    colour: rust.RewindColour.cherryBomb,
    percent: 19,
    fileIds: _ids(100100, 18),
  ),
  places: rust.Places(
    cities: [
      rust.RewindCity(
        name: "Goa",
        country: "India",
        photoCount: 212,
        fileIds: _ids(100200, 3),
      ),
      rust.RewindCity(
        name: "Oslo",
        country: "Norway",
        photoCount: 118,
        fileIds: _ids(100210, 3),
      ),
      rust.RewindCity(
        name: "Mumbai",
        country: "India",
        photoCount: 96,
        fileIds: _ids(100220, 3),
      ),
      rust.RewindCity(
        name: "Tromsø",
        country: "Norway",
        photoCount: 64,
        fileIds: _ids(100230, 3),
      ),
      rust.RewindCity(
        name: "Kochi",
        country: "India",
        photoCount: 54,
        fileIds: _ids(100240, 3),
      ),
      rust.RewindCity(
        name: "Delhi",
        country: "India",
        photoCount: 47,
        fileIds: _ids(100250, 3),
      ),
    ],
    distanceKm: 9120,
  ),
  spots: rust.Spots(spotCount: 3, photoCount: 1555, fileIds: _ids(100300, 18)),
  peopleRace: rust.PeopleRace(
    people: [
      rust.RacePerson(
        personId: "person_maya",
        photoCount: 1204,
        monthlyCounts: Uint32List.fromList([
          40,
          90,
          150,
          210,
          290,
          380,
          480,
          590,
          700,
          860,
          1030,
          1204,
        ]),
        faceIds: _faceIds(100400, 5),
        fileIds: _ids(100400, 8),
      ),
      rust.RacePerson(
        personId: "person_leo",
        photoCount: 806,
        monthlyCounts: Uint32List.fromList([
          70,
          140,
          210,
          290,
          360,
          430,
          500,
          560,
          620,
          690,
          750,
          806,
        ]),
        faceIds: _faceIds(100410, 5),
        fileIds: _ids(100410, 8),
      ),
      rust.RacePerson(
        personId: "person_sam",
        photoCount: 512,
        monthlyCounts: Uint32List.fromList([
          50,
          110,
          160,
          200,
          250,
          300,
          330,
          360,
          400,
          440,
          480,
          512,
        ]),
        faceIds: _faceIds(100420, 5),
        fileIds: _ids(100420, 8),
      ),
    ],
  ),
  busiestDay: rust.BusiestDay(
    month: 8,
    day: 14,
    photoCount: 342,
    fileIds: _ids(100500, 16),
  ),
  newFaces: rust.NewFaces(
    count: 6,
    faces: [
      rust.NewFace(personId: "person_ana", faceIds: _faceIds(100600, 3)),
      rust.NewFace(personId: "person_ravi", faceIds: _faceIds(100610, 3)),
      rust.NewFace(clusterId: "cluster_one", faceIds: _faceIds(100620, 3)),
      rust.NewFace(clusterId: "cluster_two", faceIds: _faceIds(100630, 3)),
      rust.NewFace(clusterId: "cluster_three", faceIds: _faceIds(100640, 3)),
      rust.NewFace(clusterId: "cluster_four", faceIds: _faceIds(100650, 3)),
    ],
  ),
  favourites: rust.Favourites(photoCount: 128, fileIds: _ids(100700, 12)),
  weeklyHabit: const rust.WeeklyHabit(weekday: 7, hour: 18, percent: 23),
  crowdFavourite: const rust.CrowdFavourite(
    photos: [
      rust.LikedPhoto(fileId: 100800, likeCount: 48),
      rust.LikedPhoto(fileId: 100801, likeCount: 31),
      rust.LikedPhoto(fileId: 100802, likeCount: 22),
    ],
  ),
  badge: const rust.Badge(id: rust.RewindBadge.sunChaser, value: 142),
  scrapbook: rust.Scrapbook(fileIds: _ids(100900, 12)),
);

final _sparseYear = rust.RewindReport(
  totals: const rust.Totals(files: 180),
  busiestDay: rust.BusiestDay(
    month: 3,
    day: 2,
    photoCount: 24,
    fileIds: _ids(200100, 6),
  ),
  favourites: rust.Favourites(photoCount: 4, fileIds: _ids(200200, 4)),
  weeklyHabit: const rust.WeeklyHabit(weekday: 6, hour: 11, percent: 31),
  badge: const rust.Badge(id: rust.RewindBadge.limitedEdition),
  scrapbook: rust.Scrapbook(fileIds: _ids(200300, 6)),
);

final _topTenYear = rust.RewindReport(
  totals: const rust.Totals(files: 4826, topPercent: 10),
  colour: rust.ColourOfTheYear(
    colour: rust.RewindColour.lemonDrop,
    percent: 17,
    fileIds: _ids(300100, 7),
  ),
  places: rust.Places(
    cities: [
      _city("Bengaluru", 640, 300200),
      _city("Lisbon", 88, 300210),
      _city("Porto", 41, 300220),
      _city("Sintra", 23, 300230),
    ],
    distanceKm: 8212,
  ),
  spots: rust.Spots(spotCount: 3, photoCount: 412, fileIds: _ids(300300, 6)),
  badge: const rust.Badge(id: rust.RewindBadge.weekendStar, value: 64),
  scrapbook: rust.Scrapbook(fileIds: _ids(300900, 12)),
);

final _topQuarterYear = rust.RewindReport(
  totals: const rust.Totals(files: 1500, topPercent: 25),
  colour: rust.ColourOfTheYear(
    colour: rust.RewindColour.marshmallow,
    percent: 41,
    fileIds: _ids(400100, 18),
  ),
  places: rust.Places(
    cities: [
      _city("Tromsø", 31, 400200),
      _city("Oslo", 30, 400210),
      _city("Bergen", 1, 400220),
    ],
    distanceKm: 0,
  ),
  spots: rust.Spots(spotCount: 3, photoCount: 96, fileIds: _ids(400300, 4)),
  badge: const rust.Badge(id: rust.RewindBadge.mixedBag),
);
