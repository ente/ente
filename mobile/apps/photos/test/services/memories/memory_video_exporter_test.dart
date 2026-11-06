import "dart:io";
import "dart:math";
import "dart:typed_data";

import "package:flutter_test/flutter_test.dart";
import "package:native_video_editor/native_video_editor.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/services/memories/memory_video_exporter.dart";

void main() {
  const track = MemoryMusicTrack(
    id: "track-1",
    url: "https://example.com/track-1.mp3",
  );
  late Directory directory;
  late List<SlideshowExportRequest> requests;
  late List<double> progress;

  EnteFile makeFile(int id, FileType type, {String? title}) => EnteFile()
    ..generatedID = id
    ..localID = "local-$id"
    ..title = title ?? "file-$id.jpg"
    ..fileType = type;

  MemoryVideoExporter createExporter() {
    return MemoryVideoExporter(
      resolveFile: (file) async => File("${directory.path}/${file.localID}"),
      resolveThumbnail: (file) async => Uint8List.fromList([1, 2, 3]),
      resolveMusic: (track) async => File("${directory.path}/${track.id}.mp3"),
      export: (request, {onProgress}) async {
        requests.add(request);
        onProgress?.call(0.5);
        onProgress?.call(1);
        return request.outputPath;
      },
      outputDirectory: () => "${directory.path}/",
      random: Random(7),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp("memory-video-export-");
    requests = <SlideshowExportRequest>[];
    progress = <double>[];
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test("builds the viewer's slideshow from the selected items", () async {
    final output = await createExporter().export(
      files: [
        makeFile(1, FileType.image),
        makeFile(2, FileType.video),
        makeFile(3, FileType.livePhoto),
      ],
      musicTrack: track,
      muteVideos: true,
      onProgress: progress.add,
    );

    final request = requests.single;
    expect(output.path, request.outputPath);
    expect(request.outputPath, startsWith("${directory.path}/memory-"));
    expect(request.outputPath, endsWith(".mp4"));
    expect(request.width, 1080);
    expect(request.height, 1920);
    expect(request.crossfade, const Duration(milliseconds: 600));
    expect(request.items.map((item) => item.type), [
      SlideshowItemType.photo,
      SlideshowItemType.video,
      SlideshowItemType.photo,
    ]);
    expect(request.items[0].path, "${directory.path}/local-1");
    expect(request.items[0].duration, const Duration(seconds: 5));
    expect(request.items[1].isMuted, isTrue);
    expect(request.music?.path, "${directory.path}/track-1.mp3");
    expect(request.music?.fadeIn, const Duration(milliseconds: 900));
    expect(progress.last, 1);
    expect(progress, orderedEquals([...progress]..sort()));
  });

  test("alternates the zoom direction and keeps pans subtle", () async {
    await createExporter().export(
      files: [makeFile(1, FileType.image), makeFile(2, FileType.image)],
      musicTrack: null,
      muteVideos: false,
    );

    final motions = requests.single.items.map((item) => item.motion!).toList();
    expect(motions[0].startScale, lessThan(motions[0].endScale));
    expect(motions[1].startScale, greaterThan(motions[1].endScale));
    for (final motion in motions) {
      for (final offset in [motion.startOffset, motion.endOffset]) {
        expect(offset.dx.abs(), lessThanOrEqualTo(0.0125));
        expect(offset.dy.abs(), lessThanOrEqualTo(0.0125));
      }
    }
    expect(requests.single.music, isNull);
  });

  test("resolves files a few at a time", () async {
    var inFlight = 0;
    var peak = 0;
    final exporter = MemoryVideoExporter(
      resolveFile: (file) async {
        inFlight++;
        peak = max(peak, inFlight);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return File("${directory.path}/${file.localID}");
      },
      export: (request, {onProgress}) async {
        requests.add(request);
        return request.outputPath;
      },
      outputDirectory: () => "${directory.path}/",
    );

    await exporter.export(
      files: [for (var id = 1; id <= 7; id++) makeFile(id, FileType.image)],
      musicTrack: null,
      muteVideos: false,
      onProgress: progress.add,
    );

    expect(peak, 3);
    expect(requests.single.items.map((item) => item.path), [
      for (var id = 1; id <= 7; id++) "${directory.path}/local-$id",
    ]);
    expect(progress, orderedEquals([...progress]..sort()));
  });

  test("renders RAW photos from their thumbnail", () async {
    final exporter = MemoryVideoExporter(
      resolveThumbnail: (file) async => Uint8List.fromList([1, 2, 3]),
      resolveThumbnailFromServer: (_) async =>
          fail("An available thumbnail should not be downloaded again"),
      export: (request, {onProgress}) async {
        requests.add(request);
        expect(await File(request.items.single.path).readAsBytes(), [1, 2, 3]);
        return request.outputPath;
      },
      outputDirectory: () => "${directory.path}/",
    );

    await exporter.export(
      files: [
        makeFile(1, FileType.image, title: "shot.DNG")..uploadedFileID = 1,
      ],
      musicTrack: null,
      muteVideos: false,
    );

    expect(requests.single.items.single.path, endsWith(".jpg"));
    expect(await directory.list().toList(), isEmpty);
  });

  test("cleans up a downloaded thumbnail when export fails", () async {
    var remoteDownloads = 0;
    final exporter = MemoryVideoExporter(
      resolveThumbnail: (_) async => null,
      resolveThumbnailFromServer: (_) async {
        remoteDownloads++;
        return Uint8List.fromList([1, 2, 3]);
      },
      export: (request, {onProgress}) async {
        expect(await File(request.items.single.path).readAsBytes(), [1, 2, 3]);
        throw StateError("Export failed");
      },
      outputDirectory: () => "${directory.path}/",
    );

    await expectLater(
      exporter.export(
        files: [
          makeFile(1, FileType.image, title: "shot.DNG")..uploadedFileID = 1,
        ],
        musicTrack: null,
        muteVideos: false,
      ),
      throwsStateError,
    );

    expect(remoteDownloads, 1);
    expect(await directory.list().toList(), isEmpty);
  });

  test(
    "does not download thumbnails for files that were never uploaded",
    () async {
      final exporter = MemoryVideoExporter(
        resolveThumbnail: (_) async => null,
        resolveThumbnailFromServer: (_) async => fail("File has no cloud copy"),
        export: (request, {onProgress}) async =>
            fail("Export requires a thumbnail"),
        outputDirectory: () => "${directory.path}/",
      );

      await expectLater(
        exporter.export(
          files: [makeFile(1, FileType.image, title: "shot.DNG")],
          musicTrack: null,
          muteVideos: false,
        ),
        throwsA(isA<MemoryVideoExportException>()),
      );
    },
  );

  for (final extension in ["jpg", "dng"]) {
    test(
      "recovers $extension when a thumbnail load clears the local ID",
      () async {
        final file = makeFile(1, FileType.image, title: "shot.$extension")
          ..uploadedFileID = 1;
        final remoteFile = await File(
          "${directory.path}/remote.jpg",
        ).writeAsBytes([1]);
        var remoteDownloads = 0;
        final exporter = MemoryVideoExporter(
          resolveFile: (file) async {
            file.localID = null;
            return null;
          },
          resolveThumbnail: (file) async {
            file.localID = null;
            return null;
          },
          resolveFileFromServer: (_) async {
            remoteDownloads++;
            return remoteFile;
          },
          resolveThumbnailFromServer: (_) async {
            remoteDownloads++;
            return remoteFile.readAsBytes();
          },
          export: (request, {onProgress}) async {
            expect(await File(request.items.single.path).readAsBytes(), [1]);
            return request.outputPath;
          },
          outputDirectory: () => "${directory.path}/",
        );

        await exporter.export(
          files: [file],
          musicTrack: null,
          muteVideos: false,
        );

        expect(remoteDownloads, 1);
        expect(await directory.list().map((entry) => entry.path).toList(), [
          remoteFile.path,
        ]);
      },
    );
  }

  test("downloads the uploaded copy when the local path is stale", () async {
    final remoteFile = await File(
      "${directory.path}/remote.jpg",
    ).writeAsBytes([1]);
    var remoteDownloads = 0;
    final exporter = MemoryVideoExporter(
      resolveFile: (_) async => File("${directory.path}/missing.jpg"),
      resolveFileFromServer: (_) async {
        remoteDownloads++;
        return remoteFile;
      },
      export: (request, {onProgress}) async {
        requests.add(request);
        return request.outputPath;
      },
      outputDirectory: () => "${directory.path}/",
    );

    await exporter.export(
      files: [makeFile(1, FileType.image)..uploadedFileID = 1],
      musicTrack: null,
      muteVideos: false,
    );

    expect(remoteDownloads, 1);
    expect(requests.single.items.single.path, remoteFile.path);
  });

  test("cleans up a partially written thumbnail", () async {
    final partialFile = File("${directory.path}/partial.jpg");
    final exporter = MemoryVideoExporter(
      resolveThumbnail: (_) async => Uint8List.fromList([1, 2, 3]),
      export: (request, {onProgress}) async => fail("Thumbnail write failed"),
      outputDirectory: () => "${directory.path}/",
    );

    await expectLater(
      IOOverrides.runZoned(
        () => exporter.export(
          files: [makeFile(1, FileType.image, title: "shot.DNG")],
          musicTrack: null,
          muteVideos: false,
        ),
        createFile: (_) => _PartialWriteFile(partialFile),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await directory.list().toList(), isEmpty);
  });

  test("stops after a failed batch and cleans up its thumbnails", () async {
    final resolved = <int>[];
    final exporter = MemoryVideoExporter(
      resolveFile: (file) async {
        resolved.add(file.generatedID!);
        return null;
      },
      resolveThumbnail: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return Uint8List.fromList([1, 2, 3]);
      },
      export: (request, {onProgress}) async {
        requests.add(request);
        return request.outputPath;
      },
      outputDirectory: () => "${directory.path}/",
    );

    await expectLater(
      exporter.export(
        files: [
          makeFile(1, FileType.image),
          makeFile(2, FileType.image, title: "shot.DNG"),
          for (var id = 3; id <= 7; id++) makeFile(id, FileType.image),
        ],
        musicTrack: null,
        muteVideos: false,
      ),
      throwsA(isA<MemoryVideoExportException>()),
    );
    expect(resolved, [1, 3]);
    expect(requests, isEmpty);
    expect(await directory.list().toList(), isEmpty);
  });
}

class _PartialWriteFile extends Fake implements File {
  final File file;

  _PartialWriteFile(this.file);

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    await file.writeAsBytes(bytes.take(1).toList(), mode: mode, flush: flush);
    throw const FileSystemException("Thumbnail write failed");
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
}
