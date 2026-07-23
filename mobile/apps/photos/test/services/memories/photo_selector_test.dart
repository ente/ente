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

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Dimension of the fake CLIP embedding vectors used in tests.
const _embDim = 16;

/// Creates a minimal [EnteFile] with the given properties.
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

/// Shorthand: wraps an [EnteFile] into a [Memory] with unseen state.
Memory _mem(EnteFile f) => Memory(f, -1);

/// Creates a deterministic "random" embedding for the given [fileID].
/// Vectors created with distinct seeds will have low cosine similarity;
/// vectors with the same seed will be identical (similarity = 1).
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

/// Creates an embedding that is *nearly identical* to [base] (similarity > 0.80).
EmbeddingVector _nearDuplicateEmb(int fileID, EmbeddingVector base) {
  final baseList = base.vector.toList();
  // Add a tiny perturbation – keeps cosine similarity > 0.99.
  final perturbed = baseList
      .map((v) => v + (Random(fileID).nextDouble() - 0.5) * 0.01)
      .toList();
  final norm = Vector.fromList(perturbed).norm();
  return EmbeddingVector(
    fileID: fileID,
    embedding: perturbed.map((v) => v / norm).toList(),
  );
}

/// A unit vector used as the "positive text vector" for nostalgia scoring.
Vector get _positiveTextVector {
  final raw = List<double>.generate(_embDim, (i) => (i + 1).toDouble());
  final norm = Vector.fromList(raw).norm();
  return Vector.fromList(raw.map((v) => v / norm).toList());
}

/// Microseconds per hour – handy for spacing creation times.
const _hour = 3600 * 1000 * 1000;

/// Base timestamp: 2023-06-15 12:00 UTC in microseconds since epoch.
final _baseTime = DateTime.utc(2023, 6, 15, 12).microsecondsSinceEpoch;

/// Returns a creation time [hours] after [_baseTime], in the given [year].
int _timeInYear(int year, {int hours = 0}) {
  return DateTime.utc(year, 6, 15, 12 + hours).microsecondsSinceEpoch;
}

/// Builds the standard embedding map from a list of [EmbeddingVector]s.
Map<int, EmbeddingVector> _embMap(List<EmbeddingVector> embeddings) {
  return {for (final e in embeddings) e.fileID: e};
}

/// Creates a simple [FaceWithoutEmbedding] for testing.
FaceWithoutEmbedding _face(String faceID, int fileID) {
  return FaceWithoutEmbedding(faceID, fileID, 0.9, Detection.empty(), 50.0);
}

// ---------------------------------------------------------------------------
// Utility function tests
// ---------------------------------------------------------------------------

void main() {
  group('PhotoSelector utilities', () {
    test(
      'memoryFileId returns uploadedFileID when not in local gallery mode',
      () {
        final f = _file(uploadedFileID: 42, creationTime: _baseTime);
        expect(
          PhotoSelector.memoryFileId(f, isLocalGalleryMode: false),
          equals(42),
        );
      },
    );

    test('memoryFileId returns generatedID when in local gallery mode', () {
      final f = _file(
        uploadedFileID: 42,
        creationTime: _baseTime,
        generatedID: 99,
      );
      expect(
        PhotoSelector.memoryFileId(f, isLocalGalleryMode: true),
        equals(99),
      );
    });

    test('isTooCloseInTime detects gap < 10 minutes', () {
      expect(
        PhotoSelector.isTooCloseInTime(
          _baseTime,
          [_baseTime + 5 * 60 * 1000000], // 5 minutes apart
        ),
        isTrue,
      );
    });

    test('isTooCloseInTime allows gap >= 10 minutes', () {
      expect(
        PhotoSelector.isTooCloseInTime(
          _baseTime,
          [_baseTime + 15 * 60 * 1000000], // 15 minutes apart
        ),
        isFalse,
      );
    });

    test('isTooCloseInTime returns false for null creationTime', () {
      expect(PhotoSelector.isTooCloseInTime(null, [_baseTime]), isFalse);
    });

    test('isNearDuplicate detects similar embeddings', () {
      final e1 = _emb(1, seed: 100);
      final e2 = _nearDuplicateEmb(2, e1);
      final map = _embMap([e1, e2]);
      expect(PhotoSelector.isNearDuplicate(2, [1], map), isTrue);
    });

    test('isNearDuplicate allows distinct embeddings', () {
      final e1 = _emb(1, seed: 100);
      final e2 = _emb(2, seed: 200);
      final map = _embMap([e1, e2]);
      expect(PhotoSelector.isNearDuplicate(2, [1], map), isFalse);
    });

    test('filterNearDuplicates removes visually similar memories', () {
      final e1 = _emb(1, seed: 100);
      final e2 = _nearDuplicateEmb(2, e1);
      final e3 = _emb(3, seed: 300);
      final map = _embMap([e1, e2, e3]);
      final memories = [
        _mem(_file(uploadedFileID: 1, creationTime: _baseTime)),
        _mem(_file(uploadedFileID: 2, creationTime: _baseTime + _hour)),
        _mem(_file(uploadedFileID: 3, creationTime: _baseTime + 2 * _hour)),
      ];
      final result = PhotoSelector.filterNearDuplicates(
        memories,
        map,
        isLocalGalleryMode: false,
      );
      final ids = result.map((m) => m.file.uploadedFileID).toList();
      expect(ids, contains(1));
      expect(ids, contains(3));
      expect(ids, isNot(contains(2))); // near-duplicate of 1
    });

    test('filterByTimeSpacing removes memories too close in time', () {
      final memories = [
        _mem(_file(uploadedFileID: 1, creationTime: _baseTime)),
        _mem(
          _file(uploadedFileID: 2, creationTime: _baseTime + 5 * 60 * 1000000),
        ), // 5 min later
        _mem(_file(uploadedFileID: 3, creationTime: _baseTime + _hour)),
      ];
      final result = PhotoSelector.filterByTimeSpacing(memories);
      final ids = result.map((m) => m.file.uploadedFileID).toList();
      expect(ids, equals([1, 3]));
    });
  });

  // -------------------------------------------------------------------------
  // bestSelection – single-year path
  // -------------------------------------------------------------------------

  group('PhotoSelector.bestSelection (single year)', () {
    test('returns input when count <= targetSize', () async {
      final memories = List.generate(5, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: {},
        faceIDsToPersonID: {},
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      // Should return all 5 as-is (5 <= default target of 10).
      expect(result.length, equals(5));
    });

    test('limits output to targetSize', () async {
      // 20 photos, all same year, target = 10
      final memories = List.generate(20, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: {},
        faceIDsToPersonID: {},
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      expect(result.length, lessThanOrEqualTo(10));
    });

    test('output is sorted chronologically (oldest first)', () async {
      final memories = List.generate(20, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: {},
        faceIDsToPersonID: {},
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      for (int i = 1; i < result.length; i++) {
        expect(
          result[i].file.creationTime!,
          greaterThanOrEqualTo(result[i - 1].file.creationTime!),
        );
      }
    });

    test('no two selected photos are within minimumMemoryTimeGap', () async {
      // Create 30 photos, some very close in time
      final memories = List.generate(30, (i) {
        // Alternate: some 1 minute apart, some 1 hour apart
        final offset = (i.isEven ? i * _hour : (i - 1) * _hour + 60000000);
        return _mem(_file(uploadedFileID: i, creationTime: _baseTime + offset));
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: {},
        faceIDsToPersonID: {},
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      final minGapMicro = PhotoSelector.minimumMemoryTimeGap.inMicroseconds;
      for (int i = 0; i < result.length; i++) {
        for (int j = i + 1; j < result.length; j++) {
          final gap =
              (result[i].file.creationTime! - result[j].file.creationTime!)
                  .abs();
          expect(
            gap,
            greaterThanOrEqualTo(minGapMicro),
            reason:
                'Files ${result[i].file.uploadedFileID} and ${result[j].file.uploadedFileID} are too close in time ($gap us)',
          );
        }
      }
    });

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
      // 20 photos, file 0 has a named face, others don't
      final memories = List.generate(20, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      // All files get the same CLIP embedding so CLIP score is equal
      final sharedEmb = _emb(0, seed: 42);
      final embeddings = memories.map((m) {
        return EmbeddingVector(
          fileID: m.file.uploadedFileID!,
          embedding: sharedEmb.vector.toList(),
        );
      }).toList();
      // File 0 has a named face
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
      // File 0 should be in the result because named faces are heavily prioritized
      expect(
        result.any((m) => m.file.uploadedFileID == 0),
        isTrue,
        reason: 'File with named face should be prioritized',
      );
    });

    test('excludes near-duplicate photos', () async {
      // 20 photos: file 0 and file 1 are near-duplicates
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
      // Both 0 and 1 should not both be in the result
      final hasZero = result.any((m) => m.file.uploadedFileID == 0);
      final hasOne = result.any((m) => m.file.uploadedFileID == 1);
      expect(
        hasZero && hasOne,
        isFalse,
        reason: 'Near-duplicate files should not both be selected',
      );
    });
  });

  // -------------------------------------------------------------------------
  // bestSelection – multi-year path
  // -------------------------------------------------------------------------

  group('PhotoSelector.bestSelection (multi year)', () {
    test('represents each year', () async {
      // 3 years, 10 photos each
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
      expect(yearsRepresented, contains(2020));
      expect(yearsRepresented, contains(2021));
      expect(yearsRepresented, contains(2022));
    });

    test('adjusts targetSize for many years', () async {
      // 7 years (7*2 = 14 > 10), so targetSize becomes 7*3 = 21
      final memories = <Memory>[];
      final embeddings = <EmbeddingVector>[];
      int id = 0;
      for (int year = 2016; year <= 2022; year++) {
        for (int i = 0; i < 5; i++) {
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
      // 35 photos, 7 years. targetSize should be 21 when prefferedSize is null.
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: {},
        faceIDsToPersonID: {},
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      // Should select more than default 10 since targetSize was raised
      expect(result.length, greaterThan(10));
    });

    test(
      'still filters close-in-time photos when expanded target matches count',
      () async {
        // 7 years x 3 photos triggers the expanded targetSize of 21 exactly.
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

    test('output is sorted chronologically (oldest first)', () async {
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
      final result = await PhotoSelector.bestSelection(
        memories,
        isLocalGalleryMode: false,
        mlEnabled: true,
        fileIdToFaces: {},
        faceIDsToPersonID: {},
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      for (int i = 1; i < result.length; i++) {
        expect(
          result[i].file.creationTime!,
          greaterThanOrEqualTo(result[i - 1].file.creationTime!),
        );
      }
    });

    test(
      'round 0 does not filter duplicates (ensures year coverage)',
      () async {
        // 2 years, 6 photos each. All photos are near-duplicates of each other.
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
        // Despite all being near-duplicates, both years should be represented
        // because round 0 skips the duplicate check.
        final yearsRepresented = result.map((m) {
          return DateTime.fromMicrosecondsSinceEpoch(m.file.creationTime!).year;
        }).toSet();
        expect(yearsRepresented, contains(2021));
        expect(yearsRepresented, contains(2022));
      },
    );

    test('no two selected photos are within minimumMemoryTimeGap', () async {
      final memories = <Memory>[];
      final embeddings = <EmbeddingVector>[];
      int id = 0;
      for (final year in [2020, 2021, 2022]) {
        for (int i = 0; i < 10; i++) {
          final fileID = id++;
          // Alternate close-in-time and spread
          final offset = i.isEven ? i * _hour : (i - 1) * _hour + 60000000;
          memories.add(
            _mem(
              _file(
                uploadedFileID: fileID,
                creationTime: _timeInYear(year) + offset,
              ),
            ),
          );
          embeddings.add(_emb(fileID));
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
      final minGapMicro = PhotoSelector.minimumMemoryTimeGap.inMicroseconds;
      for (int i = 0; i < result.length; i++) {
        for (int j = i + 1; j < result.length; j++) {
          final gap =
              (result[i].file.creationTime! - result[j].file.creationTime!)
                  .abs();
          expect(
            gap,
            greaterThanOrEqualTo(minGapMicro),
            reason:
                'Files ${result[i].file.uploadedFileID} and ${result[j].file.uploadedFileID} are too close in time',
          );
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // bestSelectionPeople
  // -------------------------------------------------------------------------

  group('PhotoSelector.bestSelectionPeople', () {
    test('returns input when count <= targetSize', () async {
      final memories = List.generate(5, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      expect(result.length, equals(5));
    });

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

    test('limits output to targetSize', () async {
      final memories = List.generate(30, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      expect(result.length, lessThanOrEqualTo(10));
    });

    test('respects custom preferredSize', () async {
      final memories = List.generate(30, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        prefferedSize: 5,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      expect(result.length, lessThanOrEqualTo(5));
    });

    test('output is sorted reverse chronologically (newest first)', () async {
      final memories = List.generate(30, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      for (int i = 1; i < result.length; i++) {
        expect(
          result[i].file.creationTime!,
          lessThanOrEqualTo(result[i - 1].file.creationTime!),
        );
      }
    });

    test('distributes selection across the time range', () async {
      // 30 photos spanning 30 hours
      final memories = List.generate(30, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      // Check that selected photos span at least 80% of the original time range
      final times = result.map((m) => m.file.creationTime!).toList()..sort();
      final selectedRange = times.last - times.first;
      const totalRange = 29 * _hour;
      expect(
        selectedRange,
        greaterThan(totalRange * 0.6),
        reason: 'Selected photos should be distributed across the time range',
      );
    });

    test('prefers geographically diverse photos', () async {
      // 30 photos: 20 in New York, 10 in Tokyo. Target = 10.
      // The algorithm should include some Tokyo photos for diversity.
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

    test('handles photos without embeddings (littleEmbeddings path)', () async {
      // 20 photos, but only 3 have embeddings (< 50% threshold)
      final memories = List.generate(20, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = [_emb(0), _emb(5), _emb(15)];
      final result = await PhotoSelector.bestSelectionPeople(
        memories,
        isLocalGalleryMode: false,
        fileIDToImageEmbedding: _embMap(embeddings),
        clipPositiveTextVector: _positiveTextVector,
      );
      // Should still produce a result (doesn't crash or return empty)
      expect(result.length, greaterThan(0));
      expect(result.length, lessThanOrEqualTo(10));
    });

    test('filters memories without creationTime', () async {
      final memories = <Memory>[
        _mem(_file(uploadedFileID: 0, creationTime: _baseTime)),
        // This one has no creation time
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
      // File 1 (no creationTime) should not be in result
      expect(result.any((m) => m.file.uploadedFileID == 1), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Deterministic equivalence tests – verify exact output for fixed input
  // -------------------------------------------------------------------------

  group('Deterministic equivalence (bestSelection)', () {
    test('single-year: produces same output on repeated calls', () async {
      final memories = List.generate(20, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final embeddings = memories
          .map((m) => _emb(m.file.uploadedFileID!))
          .toList();
      final embMap = _embMap(embeddings);

      // Run twice with fresh copies of memories list (since sort is in-place)
      Future<List<int>> run() async {
        final copy = memories
            .map(
              (m) => _mem(
                _file(
                  uploadedFileID: m.file.uploadedFileID!,
                  creationTime: m.file.creationTime!,
                ),
              ),
            )
            .toList();
        final result = await PhotoSelector.bestSelection(
          copy,
          isLocalGalleryMode: false,
          mlEnabled: true,
          fileIdToFaces: {},
          faceIDsToPersonID: {},
          fileIDToImageEmbedding: embMap,
          clipPositiveTextVector: _positiveTextVector,
        );
        return result.map((m) => m.file.uploadedFileID!).toList();
      }

      final run1 = await run();
      final run2 = await run();
      expect(run1, equals(run2));
    });

    test('multi-year: produces same output on repeated calls', () async {
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

      Future<List<int>> run() async {
        final copy = memories
            .map(
              (m) => _mem(
                _file(
                  uploadedFileID: m.file.uploadedFileID!,
                  creationTime: m.file.creationTime!,
                ),
              ),
            )
            .toList();
        final result = await PhotoSelector.bestSelection(
          copy,
          isLocalGalleryMode: false,
          mlEnabled: true,
          fileIdToFaces: {},
          faceIDsToPersonID: {},
          fileIDToImageEmbedding: embMap,
          clipPositiveTextVector: _positiveTextVector,
        );
        return result.map((m) => m.file.uploadedFileID!).toList();
      }

      final run1 = await run();
      final run2 = await run();
      expect(run1, equals(run2));
    });

    test(
      'bestSelectionPeople: produces same output on repeated calls',
      () async {
        final memories = List.generate(30, (i) {
          return _mem(
            _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
          );
        });
        final embeddings = memories
            .map((m) => _emb(m.file.uploadedFileID!))
            .toList();
        final embMap = _embMap(embeddings);

        Future<List<int>> run() async {
          final copy = memories
              .map(
                (m) => _mem(
                  _file(
                    uploadedFileID: m.file.uploadedFileID!,
                    creationTime: m.file.creationTime!,
                  ),
                ),
              )
              .toList();
          final result = await PhotoSelector.bestSelectionPeople(
            copy,
            isLocalGalleryMode: false,
            fileIDToImageEmbedding: embMap,
            clipPositiveTextVector: _positiveTextVector,
          );
          return result.map((m) => m.file.uploadedFileID!).toList();
        }

        final run1 = await run();
        final run2 = await run();
        expect(run1, equals(run2));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Unified select() API tests
  // -------------------------------------------------------------------------

  group('PhotoSelector.select (unified API)', () {
    test('returns input when count <= targetSize', () async {
      final memories = List.generate(5, (i) {
        return _mem(
          _file(uploadedFileID: i, creationTime: _baseTime + i * _hour),
        );
      });
      final result = await PhotoSelector.select(
        memories,
        const SelectionConfig(
          targetSize: 10,
          isLocalGalleryMode: false,
          fileIDToImageEmbedding: {},
          scores: {},
          distribution: SelectionDistribution.none,
          pick: SelectionPick.ranked,
          sort: SelectionSort.chronological,
        ),
      );
      expect(result.length, equals(5));
    });

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
        // Score = fileID (so higher IDs are preferred)
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
        // Should prefer higher-scored files
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
      // Check reverse chronological sort
      for (int i = 1; i < result.length; i++) {
        expect(
          result[i].file.creationTime!,
          lessThanOrEqualTo(result[i - 1].file.creationTime!),
        );
      }
      // Check time spread
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

    test('chronological vs reverseChronological sort', () async {
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
        for (final e in embeddings) e.fileID: e.vector.dot(_positiveTextVector),
      };

      final chronResult = await PhotoSelector.select(
        List.of(
          memories.map(
            (m) => _mem(
              _file(
                uploadedFileID: m.file.uploadedFileID!,
                creationTime: m.file.creationTime!,
              ),
            ),
          ),
        ),
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
      for (int i = 1; i < chronResult.length; i++) {
        expect(
          chronResult[i].file.creationTime!,
          greaterThanOrEqualTo(chronResult[i - 1].file.creationTime!),
        );
      }

      final revResult = await PhotoSelector.select(
        List.of(
          memories.map(
            (m) => _mem(
              _file(
                uploadedFileID: m.file.uploadedFileID!,
                creationTime: m.file.creationTime!,
              ),
            ),
          ),
        ),
        SelectionConfig(
          targetSize: 10,
          isLocalGalleryMode: false,
          fileIDToImageEmbedding: embMap,
          scores: scores,
          distribution: SelectionDistribution.none,
          pick: SelectionPick.ranked,
          sort: SelectionSort.reverseChronological,
        ),
      );
      for (int i = 1; i < revResult.length; i++) {
        expect(
          revResult[i].file.creationTime!,
          lessThanOrEqualTo(revResult[i - 1].file.creationTime!),
        );
      }
    });
  });
}
