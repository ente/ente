import "dart:io";

import "package:archive/archive_io.dart";
import "package:computer/computer.dart";
import "package:path/path.dart";

enum LivePhotoArchivePartType { image, video }

class LivePhotoArchivePart {
  const LivePhotoArchivePart({
    required this.type,
    required this.fileName,
    required this.bytes,
  });

  final LivePhotoArchivePartType type;
  final String fileName;
  final List<int> bytes;
}

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

List<LivePhotoArchivePart> decodeLivePhotoArchive(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final parts = <LivePhotoArchivePart>[];
  for (final entry in archive) {
    if (!entry.isFile) {
      continue;
    }
    final type = switch (entry.name) {
      final name when name.startsWith("image") =>
        LivePhotoArchivePartType.image,
      final name when name.startsWith("video") =>
        LivePhotoArchivePartType.video,
      _ => null,
    };
    if (type != null) {
      parts.add(
        LivePhotoArchivePart(
          type: type,
          fileName: entry.name,
          bytes: entry.content,
        ),
      );
    }
  }
  return parts;
}
