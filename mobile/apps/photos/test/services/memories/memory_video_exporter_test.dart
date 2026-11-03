import "dart:io";
import "dart:math";

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

  EnteFile makeFile(int id, FileType type) => EnteFile()
    ..generatedID = id
    ..localID = "local-$id"
    ..fileType = type;

  MemoryVideoExporter createExporter({bool failResolve = false}) {
    return MemoryVideoExporter(
      resolveFile: (file) async =>
          failResolve ? null : File("${directory.path}/${file.localID}"),
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
      resolveMusic: (track) async => File("${directory.path}/${track.id}.mp3"),
      export: (request, {onProgress}) async {
        requests.add(request);
        return request.outputPath;
      },
      outputDirectory: () => "${directory.path}/",
      random: Random(7),
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

  test("fails before exporting when an item cannot be loaded", () async {
    await expectLater(
      createExporter(failResolve: true).export(
        files: [makeFile(1, FileType.image)],
        musicTrack: null,
        muteVideos: false,
      ),
      throwsA(isA<MemoryVideoExportException>()),
    );
    expect(requests, isEmpty);
  });
}
