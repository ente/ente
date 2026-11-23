import "dart:typed_data" show Uint8List;

import "package:collection/collection.dart";
import "package:flutter/painting.dart" show Alignment;
import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:logging/logging.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/memories/memory_sources.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

typedef RewindBlurryFace = ({
  FaceWithoutEmbedding face,
  List<RewindFace> shownIn,
});
typedef RewindBlurryFaces = ({EnteFile file, List<RewindBlurryFace> faces});
typedef _FaceCrop = ({String faceId, Uint8List crop});

class RewindMedia {
  RewindMedia._(
    this._files,
    this._people, {
    required bool waitsForOriginals,
    _Samples? samples,
  }) : _waitsForOriginals = waitsForOriginals,
       _samples = samples;

  static final _logger = Logger("RewindMedia");
  static const _sampleFaceCount = 5;
  static const _eyeLine = 0.4;

  static Future<RewindMedia> load({bool waitsForOriginals = false}) async {
    final people = await _namedPeople();
    return RewindMedia._(
      await _showableFiles(people.values),
      people,
      waitsForOriginals: waitsForOriginals,
    );
  }

  static Future<RewindMedia> sampled() async {
    final people = await _namedPeople();
    final files = await _showableFiles(people.values);
    final photos = files.entries
        .where((entry) => entry.value.fileType != FileType.video)
        .sortedBy<num>((entry) => -(entry.value.creationTime ?? 0))
        .map((entry) => entry.key)
        .take(400)
        .toList();
    return RewindMedia._(
      files,
      people,
      waitsForOriginals: true,
      samples: _Samples(photos, [
        for (final person in people.values)
          if (_isShown(person)) person.remoteID,
      ]),
    );
  }

  static Future<Map<int, EnteFile>> _showableFiles(
    Iterable<PersonEntity> people,
  ) async {
    final files = await getFilesAndMapForMemories(
      useLocalIntIds: isLocalGalleryMode,
      requireLocalId: isLocalGalleryMode,
    );
    for (final person in people) {
      if (!person.data.hideFromMemories) continue;
      for (final fileId in person.data.manuallyAssigned) {
        files.remove(fileId);
      }
      final faceIds = await MLDataDB.instance.getFaceIDsForPerson(
        person.remoteID,
      );
      for (final faceId in faceIds) {
        files.remove(tryGetFileIdFromFaceId(faceId));
      }
    }
    return files;
  }

  static Future<Map<String, PersonEntity>> _namedPeople() async {
    if (isLocalGalleryMode) return const {};
    return PersonService.instance.getPersonsMap();
  }

  static bool _isShown(PersonEntity person) =>
      !person.data.isIgnored &&
      !person.data.hideFromMemories &&
      person.data.name.trim().isNotEmpty;

  final Map<int, EnteFile> _files;
  final Map<String, PersonEntity> _people;
  final bool _waitsForOriginals;
  final _Samples? _samples;
  final _used = <int>{};
  final _handedOut = <EnteFile>[];
  final _galleries = <EnteFile>[];
  final _faces = <String, Future<RewindFace?>>{};
  final _blurryFaces = <int, Map<String, FaceWithoutEmbedding>>{};
  final _shownFaces = <String, List<RewindFace>>{};

  IMLDataDB<int> get _ml =>
      isLocalGalleryMode ? MLDataDB.localGalleryInstance : MLDataDB.instance;

  List<RewindBlurryFaces> get blurryFaces => [
    for (final MapEntry(key: fileId, value: faces) in _blurryFaces.entries)
      (
        file: _files[fileId]!,
        faces: [
          for (final face in faces.values)
            (face: face, shownIn: _shownFaces[face.faceID] ?? const []),
        ],
      ),
  ];

  static Future<bool> sharpen(RewindBlurryFaces blurry) async {
    var sharpened = false;
    for (final (:face, :shownIn) in blurry.faces) {
      final crop = await _sharpen(blurry.file, face);
      if (crop == null) continue;
      sharpened = true;
      for (final shown in shownIn) {
        shown.sharpen(crop);
      }
    }
    return sharpened;
  }

  static Future<Uint8List?> _sharpen(
    EnteFile file,
    FaceWithoutEmbedding face,
  ) async {
    try {
      await _cropFrom(file, face, useFullFile: true);
      if (!await areFullFaceCropsCached([face.faceID])) return null;
      return await _cropFrom(file, face, useFullFile: false);
    } catch (error, stackTrace) {
      _logger.warning(
        "Could not sharpen face ${face.faceID}",
        error,
        stackTrace,
      );
      return null;
    }
  }

  List<EnteFile> photos(Int64List ids, int slots) => _pick(ids.inner, slots);

  EnteFile? photo(int id) => _pick([id], 1).firstOrNull;

  List<EnteFile> extraPhotos(
    Int64List ids,
    int slots, {
    bool preloadRemote = false,
  }) {
    final files = [
      for (final id in ids.inner.map(_fileId).toSet()) ?_files[id],
    ].take(slots).toList();
    if (preloadRemote) {
      _handedOut.addAll(files.where((file) => file.isRemoteOnlyFile));
    }
    return files;
  }

  List<EnteFile> gallery(Int64List ids, int slots) {
    final files = extraPhotos(ids, slots);
    _galleries.addAll(files);
    return files;
  }

  List<EnteFile> _pick(Iterable<int> ids, int slots) {
    final fresh = <int>[];
    final repeats = <int>[];
    for (final id in ids.map(_fileId).toSet()) {
      if (!_files.containsKey(id)) continue;
      (_used.contains(id) ? repeats : fresh).add(id);
    }
    final picked = [...fresh, ...repeats].take(slots).toList();
    _used.addAll(picked);
    final files = [for (final id in picked) _files[id]!];
    _handedOut.addAll(files);
    return files;
  }

  List<EnteFile> takeHandedOut() => _take(_handedOut);

  List<EnteFile> takeGalleries() => _take(_galleries);

  static List<EnteFile> _take(List<EnteFile> files) {
    final taken = List.of(files);
    files.clear();
    return taken;
  }

  String? personName(String personId) =>
      _nameOf(_samples?.person(personId) ?? personId);

  Future<RewindFace?> person(String personId, List<String> faceIds) {
    return _faces[personId] ??= _resolve(personId, faceIds, named: true);
  }

  Future<RewindFace?> cluster(String clusterId, List<String> faceIds) async {
    final cached = _faces[clusterId];
    final face =
        await (cached ??
            (_faces[clusterId] = _resolve(clusterId, faceIds, named: false)));
    if (cached == null || face?.crop != null) return face;
    return _faces[clusterId] = _resolve(clusterId, faceIds, named: false);
  }

  Future<Map<EnteFile, Alignment>> faceFocus(
    String personId,
    List<EnteFile> files,
  ) async {
    if (_samples != null || files.isEmpty) return const {};
    try {
      final wanted = Set<EnteFile>.identity()..addAll(files);
      final focus = Map<EnteFile, Alignment>.identity();
      final areas = Map<EnteFile, double>.identity();
      for (final faceId in await _ml.getFaceIDsForPerson(personId)) {
        final file = _files[tryGetFileIdFromFaceId(faceId)];
        final box = _faceBox(faceId);
        if (file == null || box == null || !wanted.contains(file)) continue;
        if (box.area <= (areas[file] ?? 0)) continue;
        areas[file] = box.area;
        focus[file] = Alignment(box.x * 2 - 1, box.y * 2 - 1);
      }
      return focus;
    } catch (error, stackTrace) {
      _logger.warning("No face focus for $personId", error, stackTrace);
      return const {};
    }
  }

  static ({double x, double y, double area})? _faceBox(String faceId) {
    final parts = faceId.split("_");
    if (parts.length < 5) return null;
    final edges = [
      for (final part in parts.sublist(parts.length - 4))
        (int.tryParse(part) ?? -1) / 100000,
    ];
    if (edges.any((edge) => edge < 0)) return null;
    final [left, top, right, bottom] = edges;
    return (
      x: (left + right) / 2,
      y: top + (bottom - top) * _eyeLine,
      area: (right - left) * (bottom - top),
    );
  }

  int _fileId(int id) => _samples?.photo(id) ?? id;

  Future<RewindFace?> _resolve(
    String id,
    List<String> faceIds, {
    required bool named,
  }) async {
    final samples = _samples;
    if (samples != null) return _sampleFace(samples, id, named: named);
    final name = named ? _nameOf(id) : null;
    if (named && name == null) return null;
    if (!named && !await _isShownCluster(id)) return null;
    final found = await _cover(id) ?? await _crop(faceIds);
    final face = RewindFace(name: name, crop: found?.crop);
    if (found != null) (_shownFaces[found.faceId] ??= []).add(face);
    return face;
  }

  Future<bool> _isShownCluster(String clusterId) async {
    final personId = (await _ml.getClusterIDToPersonID())[clusterId];
    final person = _people[personId];
    return person == null ||
        (!person.data.isIgnored && !person.data.hideFromMemories);
  }

  String? _nameOf(String personId) {
    final person = _people[personId];
    if (person == null || !_isShown(person)) return null;
    return person.data.name.trim();
  }

  Future<RewindFace?> _sampleFace(
    _Samples samples,
    String id, {
    required bool named,
  }) async {
    final personId = samples.person(id);
    if (personId == null) {
      return RewindFace(name: named ? _Samples.nameFrom(id) : null);
    }
    final faceIds = await _ml.getFaceIDsForPersonOrderedByScore(
      personId,
      limit: _sampleFaceCount,
    );
    final found = await _crop(faceIds) ?? await _cover(personId);
    return RewindFace(
      name: named ? _nameOf(personId) : null,
      crop: found?.crop,
    );
  }

  Future<_FaceCrop?> _cover(String personOrClusterId) async {
    try {
      final faceId = await checkUsedFaceIDForPersonOrClusterId(
        personOrClusterId,
      );
      return faceId == null ? null : await _crop([faceId]);
    } catch (error, stackTrace) {
      _logger.warning("No cover for $personOrClusterId", error, stackTrace);
      return null;
    }
  }

  Future<_FaceCrop?> _crop(List<String> faceIds) async {
    for (final faceId in faceIds) {
      try {
        final fileId = getFileIdFromFaceId<int>(faceId);
        final file = _files[fileId];
        if (file == null) continue;
        final faces = await _ml.getFacesForGivenFileID(fileId);
        final face = faces?.firstWhereOrNull((face) => face.faceID == faceId);
        if (face == null) continue;
        final crop = await _cropOf(fileId, file, face);
        if (crop != null) return (faceId: faceId, crop: crop);
      } catch (error, stackTrace) {
        _logger.warning("No crop for face $faceId", error, stackTrace);
      }
    }
    return null;
  }

  Future<Uint8List?> _cropOf(
    int fileId,
    EnteFile file,
    FaceWithoutEmbedding face,
  ) async {
    if (_waitsForOriginals) {
      return await _cropFrom(file, face, useFullFile: true) ??
          await _cropFrom(file, face, useFullFile: false);
    }
    if (!await areFullFaceCropsCached([face.faceID])) {
      (_blurryFaces[fileId] ??= {})[face.faceID] = face;
    }
    return _cropFrom(file, face, useFullFile: false);
  }

  static Future<Uint8List?> _cropFrom(
    EnteFile file,
    FaceWithoutEmbedding face, {
    required bool useFullFile,
  }) async {
    final crops = await getCachedFaceCrops(
      file,
      [face],
      useFullFile: useFullFile,
      useTempCache: false,
    );
    return crops?[face.faceID];
  }
}

class _Samples {
  _Samples(this._photos, this._people);

  final List<int> _photos;
  final List<String> _people;
  final _assigned = <String, String>{};

  int? photo(int id) => _photos.isEmpty ? null : _photos[id % _photos.length];

  String? person(String sampleId) {
    if (_people.isEmpty) return null;
    return _assigned[sampleId] ??= _people[_assigned.length % _people.length];
  }

  static String nameFrom(String sampleId) {
    final word = sampleId.split("_").last;
    return word.isEmpty ? sampleId : word[0].toUpperCase() + word.substring(1);
  }
}
