import "dart:io";

import "package:archive/archive_io.dart";
import "package:computer/computer.dart";
import "package:path/path.dart";
import "package:photos/src/rust/api/live_photo_api.dart" as rust;
import "package:photos/utils/device_storage_error.dart";

class LivePhotoArchivePart {
  const LivePhotoArchivePart({required this.fileName, required this.file});

  final String fileName;
  final File file;
}

typedef ExtractedLivePhotoArchive = ({
  LivePhotoArchivePart image,
  LivePhotoArchivePart video,
});

Future<void> _computeLivePhotoArchive(Map<String, dynamic> args) async {
  final String archivePath = args['archivePath'];
  final String imagePath = args['imagePath'];
  final String videoPath = args['videoPath'];
  final encoder = ZipFileEncoder();
  encoder.create(archivePath);
  await encoder.addFile(File(imagePath), "image${extension(imagePath)}");
  await encoder.addFile(File(videoPath), "video${extension(videoPath)}");
  await encoder.close();
}

Future<void> createLivePhotoArchive({
  required String archivePath,
  required String imagePath,
  required String videoPath,
}) {
  return Computer.shared().compute(
    _computeLivePhotoArchive,
    param: {
      'archivePath': archivePath,
      'imagePath': imagePath,
      'videoPath': videoPath,
    },
    taskName: 'zip',
  );
}

Future<ExtractedLivePhotoArchive> extractLivePhotoArchive({
  required File archiveFile,
  required Directory outputDirectory,
}) async {
  try {
    final files = await rust.extractLivePhotoArchive(
      archivePath: archiveFile.path,
      outputDirectory: outputDirectory.path,
    );
    return (
      image: LivePhotoArchivePart(
        fileName: files.image.fileName,
        file: File(files.image.filePath),
      ),
      video: LivePhotoArchivePart(
        fileName: files.video.fileName,
        file: File(files.video.filePath),
      ),
    );
  } on rust.LivePhotoArchiveError_StorageFull {
    throw const DeviceStorageFullException();
  } on rust.LivePhotoArchiveError_Format catch (error) {
    throw FormatException(error.message);
  }
}
