import "dart:io";

import "package:archive/archive_io.dart";
import "package:computer/computer.dart";
import "package:path/path.dart";

// Live Photo components are already compressed media. This allows generous
// container overhead while preventing a small archive from expanding without
// bound on device storage.
const _maxExpandedArchiveRatio = 20;
const _maxExpandedArchiveOverhead = 16 * 1024 * 1024;
final _livePhotoEntryPattern = RegExp(
  r'^(image|video)(?:\.[A-Za-z0-9]{1,16})?$',
);

class LivePhotoArchivePart {
  const LivePhotoArchivePart({required this.fileName, required this.file});

  final String fileName;
  final File file;
}

typedef ExtractedLivePhotoArchive = ({
  LivePhotoArchivePart image,
  LivePhotoArchivePart video,
});

class _CappedOutputFileStream extends OutputFileStream {
  _CappedOutputFileStream(String path, this.maxLength)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  final int maxLength;

  @override
  void writeByte(int value) {
    _checkLength(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _checkLength(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  void _checkLength(int additionalBytes) {
    if (length + additionalBytes > maxLength) {
      throw const FormatException("Live Photo archive expands beyond limit");
    }
  }
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

Future<ExtractedLivePhotoArchive> extractLivePhotoArchive({
  required File archiveFile,
  required Directory outputDirectory,
}) async {
  ArchiveFile? imageEntry;
  ArchiveFile? videoEntry;
  final input = InputFileStream(archiveFile.path);
  try {
    ZipDecoder().decodeStream(
      input,
      callback: (entry) {
        if (!entry.isFile || entry.isSymbolicLink) {
          throw const FormatException(
            "Live Photo archives may only contain files",
          );
        }
        final match = _livePhotoEntryPattern.firstMatch(entry.name);
        if (match == null) {
          throw FormatException(
            "Unexpected Live Photo archive entry: ${entry.name}",
          );
        }
        if (match.group(1) == "image") {
          if (imageEntry != null) {
            throw const FormatException(
              "Live Photo archive contains multiple images",
            );
          }
          imageEntry = entry;
        } else {
          if (videoEntry != null) {
            throw const FormatException(
              "Live Photo archive contains multiple videos",
            );
          }
          videoEntry = entry;
        }
      },
    );
    if (imageEntry == null || videoEntry == null) {
      throw const FormatException(
        "Live Photo archive must contain one image and one video",
      );
    }

    final archiveSize = await archiveFile.length();
    final maxExpandedSize =
        archiveSize * _maxExpandedArchiveRatio + _maxExpandedArchiveOverhead;
    if (imageEntry!.size + videoEntry!.size > maxExpandedSize) {
      throw const FormatException("Live Photo archive expands beyond limit");
    }

    final image = await _extractPart(
      imageEntry!,
      outputDirectory,
      "image",
      maxExpandedSize,
    );
    final remainingSize = maxExpandedSize - await image.file.length();
    return (
      image: image,
      video: await _extractPart(
        videoEntry!,
        outputDirectory,
        "video",
        remainingSize,
      ),
    );
  } finally {
    await input.close();
  }
}

Future<LivePhotoArchivePart> _extractPart(
  ArchiveFile entry,
  Directory outputDirectory,
  String outputName,
  int maxSize,
) async {
  final file = File(
    join(outputDirectory.path, "$outputName${extension(entry.name)}"),
  );
  final output = _CappedOutputFileStream(file.path, maxSize);
  try {
    entry.writeContent(output);
  } finally {
    await output.close();
  }
  return LivePhotoArchivePart(fileName: entry.name, file: file);
}
