import "dart:io";

import "package:archive/archive.dart";
import "package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/module/live_photo/archive.dart";
import "package:photos/src/rust/frb_generated.dart";

void main() {
  final library = Platform.environment["ENTE_PHOTOS_FRB_LIBRARY"] ?? "";

  group(
    "Live Photo archive Rust bridge",
    () {
      setUpAll(
        () =>
            EntePhotosRust.init(externalLibrary: ExternalLibrary.open(library)),
      );

      test("extracts a Live Photo", () async {
        final directory = await Directory.systemTemp.createTemp(
          "live_photo_archive_",
        );
        addTearDown(() => directory.delete(recursive: true));

        final archiveFile = File("${directory.path}/live-photo.zip");
        await archiveFile.writeAsBytes(
          ZipEncoder().encode(
            Archive()
              ..addFile(ArchiveFile("image.jpg", 3, [1, 2, 3]))
              ..addFile(ArchiveFile("video.mov", 3, [4, 5, 6])),
          ),
        );
        final output = await Directory("${directory.path}/output").create();

        final files = await extractLivePhotoArchive(
          archiveFile: archiveFile,
          outputDirectory: output,
        );

        expect(files.image.fileName, "image.jpg");
        expect(files.video.fileName, "video.mov");
        expect(await files.image.file.readAsBytes(), [1, 2, 3]);
        expect(await files.video.file.readAsBytes(), [4, 5, 6]);
      });

      test("rejects an incomplete Live Photo without output", () async {
        final directory = await Directory.systemTemp.createTemp(
          "incomplete_live_photo_archive_",
        );
        addTearDown(() => directory.delete(recursive: true));

        final archiveFile = File("${directory.path}/live-photo.zip");
        await archiveFile.writeAsBytes(
          ZipEncoder().encode(
            Archive()..addFile(ArchiveFile("image.jpg", 3, [1, 2, 3])),
          ),
        );
        final output = await Directory("${directory.path}/output").create();

        await expectLater(
          extractLivePhotoArchive(
            archiveFile: archiveFile,
            outputDirectory: output,
          ),
          throwsA(isA<FormatException>()),
        );
        expect(await output.list().isEmpty, isTrue);
      });
    },
    skip: library.isEmpty
        ? "Set ENTE_PHOTOS_FRB_LIBRARY to run against Rust"
        : false,
  );
}
