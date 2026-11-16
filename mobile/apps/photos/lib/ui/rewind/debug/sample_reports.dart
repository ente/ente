import "dart:math";
import "dart:typed_data" show Uint32List, Uint8List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:photos/src/rust/api/rewind_api.dart" as rust;

final rewindSampleReports = {
  "Busy year": _busyYear,
  "Top 10%, four places": _topTenYear,
  "Three places, no distance": _threePlacesYear,
  "Sparse year": _sparseYear,
  "One file": rust.RewindReport(
    totals: rust.Totals(files: 1, fileIds: _ids(100000, 1)),
  ),
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
      fileIds: _ids(firstFileId, 9),
    );

rust.TourStop _stop(String city, String country, int month, int day, int n) =>
    rust.TourStop(
      city: city,
      countryCode: country,
      month: month,
      day: day,
      photoCount: n,
    );

const _continents = [
  (5.0, 20.0, 30.0),
  (50.0, 15.0, 17.0),
  (48.0, 90.0, 36.0),
  (21.0, 78.0, 11.0),
  (45.0, -100.0, 28.0),
  (-15.0, -60.0, 21.0),
  (-25.0, 134.0, 14.0),
  (64.0, 15.0, 9.0),
];

rust.GlobePlace _place(
  String name,
  String country,
  double latitude,
  double longitude,
  int photos,
  int firstFileId,
) => rust.GlobePlace(
  name: name,
  countryCode: country,
  latitudeMicrodegrees: (latitude * 1e6).round(),
  longitudeMicrodegrees: (longitude * 1e6).round(),
  photoCount: photos,
  fileIds: _ids(firstFileId, 3),
);

rust.Globe sampleGlobe(
  List<rust.GlobePlace> places,
  List<int> route,
  int distanceKm,
) {
  const rowCount = 96;
  final rows = <int>[];
  final land = <bool>[];
  final visited = <bool>[];
  double radians(double degrees) => degrees * pi / 180;
  bool near(double latitude, double longitude, (double, double, double) blob) {
    final (centre, meridian, reach) = blob;
    final cosine =
        sin(radians(latitude)) * sin(radians(centre)) +
        cos(radians(latitude)) *
            cos(radians(centre)) *
            cos(radians(longitude - meridian));
    return acos(cosine.clamp(-1.0, 1.0)) * 180 / pi < reach;
  }

  for (var row = 0; row < rowCount; row++) {
    final latitude = -90 + (row + 0.5) * 180 / rowCount;
    final dots = max(1, (2 * rowCount * cos(radians(latitude))).round());
    rows.add(dots);
    for (var dot = 0; dot < dots; dot++) {
      final longitude = -180 + (dot + 0.5) * 360 / dots;
      land.add(_continents.any((blob) => near(latitude, longitude, blob)));
      visited.add(
        near(latitude, longitude, _continents[3]) ||
            near(latitude, longitude, _continents[7]),
      );
    }
  }
  Uint8List bits(List<bool> flags) {
    final bytes = Uint8List((flags.length + 7) ~/ 8);
    for (final (at, flag) in flags.indexed) {
      if (flag) bytes[at >> 3] |= 1 << (at & 7);
    }
    return bytes;
  }

  return rust.Globe(
    rows: Uint32List.fromList(rows),
    land: bits(land),
    visited: bits(visited),
    places: places,
    route: Uint32List.fromList(route),
    distanceKm: distanceKm,
    cityCount: places.length,
    countryCount: 3,
  );
}

List<String> _faceIds(int firstFileId, int count) => [
  for (var index = 0; index < count; index++)
    "${firstFileId + index}_31250_18750_56250_50000",
];

final _busyYear = rust.RewindReport(
  totals: rust.Totals(files: 15059, topPercent: 1, fileIds: _ids(100000, 24)),
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
        fileIds: _ids(100200, 9),
      ),
      rust.RewindCity(
        name: "Oslo",
        country: "Norway",
        photoCount: 118,
        fileIds: _ids(100210, 9),
      ),
      rust.RewindCity(
        name: "Mumbai",
        country: "India",
        photoCount: 96,
        fileIds: _ids(100220, 9),
      ),
      rust.RewindCity(
        name: "Tromsø",
        country: "Norway",
        photoCount: 64,
        fileIds: _ids(100230, 9),
      ),
      rust.RewindCity(
        name: "Kochi",
        country: "India",
        photoCount: 54,
        fileIds: _ids(100240, 9),
      ),
      rust.RewindCity(
        name: "Delhi",
        country: "India",
        photoCount: 47,
        fileIds: _ids(100250, 9),
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
      rust.NewFace(
        personId: "person_ana",
        faceIds: _faceIds(100600, 3),
        fileIds: _ids(100600, 9),
      ),
      rust.NewFace(
        personId: "person_ravi",
        faceIds: _faceIds(100610, 3),
        fileIds: _ids(100610, 9),
      ),
      rust.NewFace(
        clusterId: "cluster_one",
        faceIds: _faceIds(100620, 3),
        fileIds: _ids(100620, 9),
      ),
      rust.NewFace(
        clusterId: "cluster_two",
        faceIds: _faceIds(100630, 3),
        fileIds: _ids(100630, 9),
      ),
      rust.NewFace(
        clusterId: "cluster_three",
        faceIds: _faceIds(100640, 3),
        fileIds: _ids(100640, 9),
      ),
      rust.NewFace(
        clusterId: "cluster_four",
        faceIds: _faceIds(100650, 3),
        fileIds: _ids(100650, 9),
      ),
    ],
  ),
  favourites: rust.Favourites(photoCount: 128, fileIds: _ids(100700, 12)),
  weeklyHabit: rust.WeeklyHabit(
    weekday: 7,
    hour: 18,
    percent: 23,
    hourFileIds: _ids(100800, 3),
    fileIds: _ids(100803, 33),
  ),
  crowdFavourite: const rust.CrowdFavourite(
    photos: [
      rust.LikedPhoto(fileId: 100800, likeCount: 48),
      rust.LikedPhoto(fileId: 100801, likeCount: 31),
      rust.LikedPhoto(fileId: 100802, likeCount: 22),
    ],
  ),
  badge: const rust.Badge(id: rust.RewindBadge.sunChaser, value: 142),
  scrapbook: rust.Scrapbook(fileIds: _ids(100900, 12)),
  tour: rust.Tour(
    stops: [
      _stop("Mumbai", "IN", 1, 3, 96),
      _stop("Goa", "IN", 1, 17, 212),
      _stop("Kochi", "IN", 2, 21, 54),
      _stop("Delhi", "IN", 4, 6, 47),
      _stop("Oslo", "NO", 7, 12, 118),
      _stop("Tromsø", "NO", 7, 19, 64),
      _stop("Bergen", "NO", 7, 23, 39),
      _stop("Copenhagen", "DK", 7, 26, 28),
      _stop("Bengaluru", "IN", 9, 5, 33),
      _stop("Jaipur", "IN", 11, 14, 41),
      _stop("Udaipur", "IN", 11, 17, 22),
    ],
    cityCount: 11,
    countryCount: 3,
  ),
  globe: sampleGlobe(
    [
      _place("Mumbai", "IN", 19.08, 72.88, 96, 101000),
      _place("Goa", "IN", 15.49, 73.83, 212, 101010),
      _place("Kochi", "IN", 9.93, 76.27, 54, 101020),
      _place("Delhi", "IN", 28.61, 77.21, 47, 101030),
      _place("Oslo", "NO", 59.91, 10.75, 118, 101040),
      _place("Tromsø", "NO", 69.65, 18.96, 64, 101050),
      _place("Bergen", "NO", 60.39, 5.32, 39, 101060),
      _place("Copenhagen", "DK", 55.68, 12.57, 28, 101070),
      _place("Bengaluru", "IN", 12.97, 77.59, 33, 101080),
      _place("Jaipur", "IN", 26.91, 75.79, 41, 101090),
    ],
    [0, 1, 0, 2, 0, 3, 0, 4, 5, 6, 7, 0, 8, 0, 9, 0],
    29120,
  ),
  warp: rust.Warp(fileIds: _ids(102000, 240)),
  mosaic: rust.Mosaic(
    fileIds: _ids(102000, 400),
    mePersonId: "person_me",
    meFaceIds: _faceIds(102000, 5),
    topPersonId: "person_maya",
    topFaceIds: _faceIds(100400, 5),
  ),
);

final _sparseYear = rust.RewindReport(
  totals: rust.Totals(files: 180, fileIds: _ids(200000, 24)),
  busiestDay: rust.BusiestDay(
    month: 3,
    day: 2,
    photoCount: 24,
    fileIds: _ids(200100, 6),
  ),
  favourites: rust.Favourites(photoCount: 4, fileIds: _ids(200200, 4)),
  weeklyHabit: rust.WeeklyHabit(
    weekday: 6,
    hour: 11,
    percent: 31,
    hourFileIds: _ids(200700, 1),
    fileIds: _ids(200701, 6),
  ),
  badge: const rust.Badge(id: rust.RewindBadge.limitedEdition),
  scrapbook: rust.Scrapbook(fileIds: _ids(200300, 6)),
);

final _topTenYear = rust.RewindReport(
  totals: rust.Totals(files: 4916, topPercent: 10, fileIds: _ids(300000, 24)),
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
  tour: rust.Tour(
    stops: [
      _stop("Bengaluru", "IN", 1, 1, 640),
      _stop("Lisbon", "PT", 5, 2, 88),
      _stop("Porto", "PT", 5, 6, 41),
      _stop("Sintra", "PT", 5, 9, 23),
    ],
    cityCount: 4,
    countryCount: 2,
  ),
);

final _threePlacesYear = rust.RewindReport(
  totals: rust.Totals(files: 2765, fileIds: _ids(400000, 24)),
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
