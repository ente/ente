import "dart:io";
import "dart:typed_data";

import "package:archive/archive_io.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart";
import "package:photos/module/live_photo/archive.dart";

void main() {
  late Directory tempDirectory;
  late Directory outputDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      "live_photo_archive_test_",
    );
    outputDirectory = await Directory(
      join(tempDirectory.path, "output"),
    ).create();
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test("extracts one flat image and video entry", () async {
    final archiveFile = await _writeArchive(tempDirectory, [
      ArchiveFile.bytes("image.jpg", [1, 2, 3]),
      ArchiveFile.bytes("video.mov", [4, 5, 6]),
    ]);

    final result = await extractLivePhotoArchive(
      archiveFile: archiveFile,
      outputDirectory: outputDirectory,
    );

    expect(result.image.fileName, "image.jpg");
    expect(await result.image.file.readAsBytes(), [1, 2, 3]);
    expect(result.video.fileName, "video.mov");
    expect(await result.video.file.readAsBytes(), [4, 5, 6]);
  });

  test("rejects entries with paths", () async {
    final archiveFile = await _writeArchive(tempDirectory, [
      ArchiveFile.bytes("image/../../outside.jpg", [1, 2, 3]),
      ArchiveFile.bytes("video.mov", [4, 5, 6]),
    ]);

    await expectLater(
      extractLivePhotoArchive(
        archiveFile: archiveFile,
        outputDirectory: outputDirectory,
      ),
      throwsFormatException,
    );
    expect(outputDirectory.listSync(), isEmpty);
  });

  test("limits the bytes produced by decompression", () async {
    final archive = Archive()
      ..add(ArchiveFile.bytes("image.jpg", Uint8List(18 * 1024 * 1024)))
      ..add(ArchiveFile.bytes("video.mov", [4, 5, 6]));
    final encoded = Uint8List.fromList(ZipEncoder().encode(archive));
    final imageDirectoryEntry = _indexOfSignature(encoded, [
      0x50,
      0x4b,
      0x01,
      0x02,
    ]);
    // Forge a small declared size while retaining the full deflate stream.
    encoded.buffer.asByteData().setUint32(
      imageDirectoryEntry + 24,
      1,
      Endian.little,
    );
    final archiveFile = await File(
      join(tempDirectory.path, "forged-size.zip"),
    ).writeAsBytes(encoded);

    await expectLater(
      extractLivePhotoArchive(
        archiveFile: archiveFile,
        outputDirectory: outputDirectory,
      ),
      throwsFormatException,
    );
  });
}

Future<File> _writeArchive(
  Directory directory,
  List<ArchiveFile> entries,
) async {
  final archive = Archive();
  for (final entry in entries) {
    archive.add(entry);
  }
  return File(
    join(directory.path, "live-photo.zip"),
  ).writeAsBytes(ZipEncoder().encode(archive));
}

int _indexOfSignature(Uint8List bytes, List<int> signature) {
  for (var index = 0; index <= bytes.length - signature.length; index++) {
    if (bytes[index] == signature[0] &&
        bytes[index + 1] == signature[1] &&
        bytes[index + 2] == signature[2] &&
        bytes[index + 3] == signature[3]) {
      return index;
    }
  }
  throw StateError("ZIP directory entry not found");
}
