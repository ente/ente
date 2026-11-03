import "dart:io";

import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:photos/module/live_photo/archive.dart";
import "package:photos/src/rust/frb_generated.dart";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(EntePhotosRust.init);

  test("extracts a Live Photo through the Rust bridge", () async {
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

  test("maps invalid archives through the Rust bridge", () async {
    final directory = await Directory.systemTemp.createTemp(
      "invalid_live_photo_archive_",
    );
    addTearDown(() => directory.delete(recursive: true));

    final archive = File("${directory.path}/live-photo.zip");
    await archive.writeAsBytes([1, 2, 3]);
    final output = await Directory("${directory.path}/output").create();

    await expectLater(
      extractLivePhotoArchive(archiveFile: archive, outputDirectory: output),
      throwsA(isA<FormatException>()),
    );
  });
}
