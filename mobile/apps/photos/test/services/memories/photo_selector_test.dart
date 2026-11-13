import "dart:math" show Random;

import "package:flutter_test/flutter_test.dart";
import "package:ml_linalg/vector.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/ml/face/detection.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/memories/photo_selector.dart";

const _embDim = 16;

EnteFile _file({
  required int uploadedFileID,
  required int creationTime,
  Location? location,
  int? generatedID,
}) {
  final f = EnteFile()
    ..uploadedFileID = uploadedFileID
    ..generatedID = generatedID ?? uploadedFileID
    ..creationTime = creationTime
    ..fileType = FileType.image;
  if (location != null) f.location = location;
  return f;
}

Memory _mem(EnteFile f) => Memory(f, -1);

// Equal seeds produce identical vectors; distinct seeds have low cosine
// similarity.
EmbeddingVector _emb(int fileID, {int? seed}) {
  final s = seed ?? fileID;
  final rng = Random(s);
  final raw = List<double>.generate(_embDim, (_) => rng.nextDouble() - 0.5);
  // Normalize so that dot-product ≈ cosine similarity.
  final norm = Vector.fromList(raw).norm();
  return EmbeddingVector(
    fileID: fileID,
    embedding: raw.map((v) => v / norm).toList(),
  );
}

// Produces an embedding above the 0.80 near-duplicate threshold.
EmbeddingVector _nearDuplicateEmb(int fileID, EmbeddingVector base) {
  final baseList = base.vector.toList();
  final perturbed = baseList
      .map((v) => v + (Random(fileID).nextDouble() - 0.5) * 0.01)
      .toList();
  final norm = Vector.fromList(perturbed).norm();
  return EmbeddingVector(
    fileID: fileID,
    embedding: perturbed.map((v) => v / norm).toList(),
  );
}

Vector get _positiveTextVector {
  final raw = List<double>.generate(_embDim, (i) => (i + 1).toDouble());
  final norm = Vector.fromList(raw).norm();
  return Vector.fromList(raw.map((v) => v / norm).toList());
}

const _hour = 3600 * 1000 * 1000;

final _baseTime = DateTime.utc(2023, 6, 15, 12).microsecondsSinceEpoch;

int _timeInYear(int year, {int hours = 0}) {
  return DateTime.utc(year, 6, 15, 12 + hours).microsecondsSinceEpoch;
}

Map<int, EmbeddingVector> _embMap(List<EmbeddingVector> embeddings) {
  return {for (final e in embeddings) e.fileID: e};
}

FaceWithoutEmbedding _face(String faceID, int fileID) {
  return FaceWithoutEmbedding(faceID, fileID, 0.9, Detection.empty(), 50.0);
}

void main() {
  group('PhotoSelector.bestSelection (single year)', () {
    test(
      'skips no-ML time buckets that cannot satisfy the min-gap filter',
      () async {
        const minute = 60 * 1000000;
        final memories = [
          _mem(_file(uploadedFileID: 0, creationTime: _baseTime)),
          _mem(_file(uploadedFileID: 1, creationTime: _baseTime + 7 * minute)),
          _mem(_file(uploadedFileID: 2, creationTime: _baseTime + 8 * minute)),
          _mem(_file(uploadedFileID: 3, creationTime: _baseTime + 9 * minute)),
          _mem(_file(uploadedFileID: 4, creationTime: _baseTime + 20 * minute)),
        ];

        final result = await PhotoSelector.bestSelection(
          memories,
          prefferedSize: 3,
          isLocalGalleryMode: false,
          mlEnabled: false,
          fileIdToFaces: const {},
          faceIDsToPersonID: const {},
          fileIDToImageEmbedding: const {},
          clipPositiveTextVector: _positiveTextVector,
        );

        expect(result.map((m) => m.file.uploadedFileID), equals([0, 4]));
      },
    );

    test('prioritizes files with named faces', () async {
      final memories = List.generate(20, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final sharedEmb = _emb(0, seed: 42);
      final embeddings = memories.map((m) {
        return EmbeddingVector(
          fileID: m.file.uploadedFileID!,
          embedding: sharedEmb.vector.toList(),
        );
      }).toList();
      final fileIdToFaces = <int, List<FaceWithoutEmbedding>>{
        0: [_face('face_0', 0)],
      };
      final faceIDsToPersonID = {'face_0': 'person_1'};
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: fileIdToFaces,
        faceIDsToPersonID: faceIDsToPersonID,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      expect(
        result.any((m) => m.file.uploadedFileID == 0),
        isTrue,
        reason: 'File with named face should be prioritized',
      );
    });

    test('excludes near-duplicate photos', () async {
      final e0 = _emb(0, seed: 100);
      final e1 = _nearDuplicateEmb(1, e0);
      final embeddings = <EmbeddingVector>[e0, e1];
      for (int i = 2; i < 20; i++) {
        embeddings.add(_emb(i));
      }
      final memories = List.generate(20, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: {},
        faceIDsToPersonID: {},
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      final hasZero = result.any((m) => m.file.uploadedFileID == 0);
      final hasOne = result.any((m) => m.file.uploadedFileID == 1);
      expect(
        hasZero && hasOne,
        isFalse,
        reason: 'Near-duplicate files should not both be selected',
      );
    });
  });

  group('PhotoSelector.bestSelection (multi year)', () {
    test(
      'still filters close-in-time photos when expanded target matches count',
      () async {
        final memories = <Memory>[];
        final embeddings = <EmbeddingVector>[];
        final fileIdToFaces = <int, List<FaceWithoutEmbedding>>{};
        final faceIDsToPersonID = <String, String>{};
        int id = 0;

        for (int year = 2016; year <= 2022; year++) {
          for (int i = 0; i < 3; i++) {
            final fileID = id++;
            final creationTime = switch (i) {
              0 => _timeInYear(year),
              1 => _timeInYear(year) + 5 * 60 * 1000000,
              _ => _timeInYear(year, hours: 1),
            };

            memories.add(
              _mem(_file(uploadedFileID: fileID, creationTime: creationTime)),
            );
            embeddings.add(_emb(fileID));

            final faceID = 'face_$fileID';
            fileIdToFaces[fileID] = List.generate(3 - i, (_) {
              return _face(faceID, fileID);
            });
            faceIDsToPersonID[faceID] = 'person_$fileID';
          }
        }

        final result = await PhotoSelector.bestSelection(
          memories,
          isLocalGalleryMode: false,
          mlEnabled: true,
          fileIdToFaces: fileIdToFaces,
          faceIDsToPersonID: faceIDsToPersonID,
          fileIDToImageEmbedding: _embMap(embeddings),
          clipPositiveTextVector: _positiveTextVector,
        );

        expect(
          result.length,
          equals(14),
          reason:
              'Round-robin filtering should still run when fileCount == expanded targetSize',
        );
        for (int i = 1; i < result.length; i++) {
          expect(
            result[i].file.creationTime!,
            greaterThanOrEqualTo(result[i - 1].file.creationTime!),
          );
        }
      },
    );

    test(
      'round 0 does not filter duplicates (ensures year coverage)',
      () async {
        final base = _emb(0, seed: 42);
        final memories = <Memory>[];
        final embeddings = <EmbeddingVector>[];
        int id = 0;
        for (final year in [2021, 2022]) {
          for (int i = 0; i < 6; i++) {
            final fileID = id++;
            memories.add(
              _mem(
                _file(
                  uploadedFileID: fileID,
                  creationTime: _timeInYear(year, hours: i),
                ),
              ),
            );
            embeddings.add(_nearDuplicateEmb(fileID, base));
          }
        }
        final result = await PhotoSelector.bestSelection(
          memories,
          isLocalGalleryMode: false,
          mlEnabled: true,
          fileIdToFaces: {},
          faceIDsToPersonID: {},
          fileIDToImageEmbedding: _embMap(embeddings),
          clipPositiveTextVector: _positiveTextVector,
        );
        final yearsRepresented = result.map((m) {
          return DateTime.fromMicrosecondsSinceEpoch(m.file.creationTime!).year;
        }).toSet();
        expect(yearsRepresented, contains(2021));
        expect(yearsRepresented, contains(2022));
      },
    );
  });

  group('PhotoSelector.bestSelectionPeople', () {
    test(
      'ignores unrelated embeddings when precomputing people scores',
      () async {
        final memories = List.generate(20, (i) {
          return _mem(
            _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
          );
        });
        final embeddings =
            memories.map((m) => _emb(m.file.uploadedFileID!)).toList()
              ..add(EmbeddingVector(fileID: 9999, embedding: const [1.0, 0.0]));

        final result = await PhotoSelector.bestSelectionPeople(
          memories,
          isLocalGalleryMode: false,
          fileIDToImageEmbedding: _embMap(embeddings),
          clipPositiveTextVector: _positiveTextVector,
        );

        expect(result, isNotEmpty);
        expect(result.length, lessThanOrEqualTo(10));
      },
    );

    test('prefers geographically diverse photos', () async {
      const nyLoc = Location(latitude: 40.7128, longitude: -74.0060);
      const tokyoLoc = Location(latitude: 35.6762, longitude: 139.6503);
      final memories = <Memory>[];
      final embeddings = <EmbeddingVector>[];
      for (int i = 0; i < 20; i++) {
        final fid = i;
        memories.add(
          _mem(
            _file(
              uploadedFileID: fid,
              creationTime: _baseTime + i * _hour,
              location: nyLoc,
            ),
          ),
        );
        embeddings.add(_emb(fid));
      }
      for (int i = 0; i < 10; i++) {
        final fid = 20 + i;
        memories.add(
          _mem(
            _file(
              uploadedFileID: fid,
              creationTime: _baseTime + (20 + i) * _hour,
              location: tokyoLoc,
            ),
          ),
        );
        embeddings.add(_emb(fid));
      }
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      final tokyoCount = result.where((m) {
        final loc = m.file.location;
        return loc != null && loc.latitude == tokyoLoc.latitude;
      }).length;
      expect(
        tokyoCount,
        greaterThan(0),
        reason: 'Geographic diversity should include Tokyo photos',
      );
    });

    test('filters memories without creationTime', () async {
      final memories = <Memory>[
        _mem(_file(uploadedFileID: 0, creationTime: _baseTime)),
        _mem(
          EnteFile()
            ..uploadedFileID = 1
            ..generatedID = 1
            ..fileType = FileType.image,
        ),
        ...List.generate(19, (i) {
          return _mem(
            _file(
              uploadedFileID: i + 2,
              creationTime: _baseTime + (i + 1) * _hour,
            ),
          );
        }),
      ];
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      expect(result.any((m) => m.file.uploadedFileID == 1), isFalse);
    });
  });

  group('PhotoSelector.select (unified API)', () {
    test(
      'flat distribution selects by score and respects targetSize',
      () async {
        final memories = List.generate(20, (i) {
          return _mem(
            _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
          );
        });
        final embeddings = memories
            .map((m) => _emb(m.file.uploadedFileID!))
            .toList();
        final embMap = _embMap(embeddings);
        final scores = {
          for (final m in memories)
            m.file.uploadedFileID!: m.file.uploadedFileID!.toDouble(),
        };
        final result = await PhotoSelector.select(
          memories,
          SelectionConfig(
            targetSize: 10,
            isLocalGalleryMode: false,
            fileIDToImageEmbedding: embMap,
            scores: scores,
            distribution: SelectionDistribution.none,
            pick: SelectionPick.ranked,
            sort: SelectionSort.chronological,
          ),
        );
        expect(result.length, lessThanOrEqualTo(10));
        expect(
          result.any((m) => m.file.uploadedFileID == 19),
          isTrue,
          reason: 'Highest-scored file should be selected',
        );
      },
    );

    test('timeBuckets distribution spreads across time range', () async {
      final memories = List.generate(30, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final embMap = _embMap(embeddings);
      final scores = {
        for (final e in embeddings) e.fileID: e.vector.dot(_positiveTextVector),
      };
      final result = await PhotoSelector.select(
        memories,
        SelectionConfig(
          targetSize: 10,
          isLocalGalleryMode: false,
          fileIDToImageEmbedding: embMap,
          scores: scores,
          distribution: SelectionDistribution.timeBuckets,
          pick: SelectionPick.geographicFarthest,
          sort: SelectionSort.reverseChronological,
          preNarrowTopPercent: 0.3,
        ),
      );
      expect(result.length, lessThanOrEqualTo(10));
      for (int i = 1; i < result.length; i++) {
        expect(
          result[i].file.creationTime!,
          lessThanOrEqualTo(result[i - 1].file.creationTime!),
        );
      }
      final times = result.map((m) => m.file.creationTime!).toList()..sort();
      if (times.length > 1) {
        final selectedRange = times.last - times.first;
        const totalRange = 29 * _hour;
        expect(selectedRange, greaterThan(totalRange * 0.6));
      }
    });

    test('yearRoundRobin distribution represents each year', () async {
      final memories = <Memory>[];
      final embeddings = <EmbeddingVector>[];
      int id = 0;
      for (final year in [2020, 2021, 2022]) {
        for (int i = 0; i < 10; i++) {
          final fileID = id++;
          memories.add(
            _mem(
              _file(
                uploadedFileID: fileID,
                creationTime: _timeInYear(year, hours: i),
              ),
            ),
          );
          embeddings.add(_emb(fileID));
        }
      }
      final embMap = _embMap(embeddings);
      final scores = {
        for (final e in embeddings) e.fileID: e.vector.dot(_positiveTextVector),
      };
      final result = await PhotoSelector.select(
        memories,
        SelectionConfig(
          targetSize: 10,
          isLocalGalleryMode: false,
          fileIDToImageEmbedding: embMap,
          scores: scores,
          distribution: SelectionDistribution.yearRoundRobin,
          pick: SelectionPick.ranked,
          sort: SelectionSort.chronological,
          skipDuplicateCheckOnFirstRound: true,
        ),
      );
      final yearsRepresented = result.map((m) {
        return DateTime.fromMicrosecondsSinceEpoch(m.file.creationTime!).year;
      }).toSet();
      expect(yearsRepresented, contains(2020));
      expect(yearsRepresented, contains(2021));
      expect(yearsRepresented, contains(2022));
    });
  });
}
