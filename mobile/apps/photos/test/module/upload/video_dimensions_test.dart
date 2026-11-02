import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:native_video_editor/native_video_editor.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/upload/model/media_upload_data.dart";
import "package:photos/module/upload/upload_metadata.dart";
import "package:photos/module/upload/video_dimensions.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel("native_video_editor");
  late Directory directory;
  late File source;
  late Map<String, Object> videoInfo;
  MethodCall? inspection;
  bool failInspection = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp("upload-dimensions-");
    source = await File("${directory.path}/original.mp4").writeAsBytes([0]);
    videoInfo = {
      "duration": 1000,
      "width": 1920,
      "height": 1080,
      "displayWidth": 1080,
      "displayHeight": 1920,
      "rotation": 90,
    };
    inspection = null;
    failInspection = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          inspection = call;
          if (failInspection) {
            throw PlatformException(code: "metadata_unavailable");
          }
          return videoInfo;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
    "prepares source display dimensions even without a video thumbnail",
    () async {
      final file = EnteFile()..fileType = FileType.video;
      final dimensions = await getVideoUploadDimensions(source);
      final metadata = await prepareUploadMetadata(
        file,
        MediaUploadData(
          sourceFile: source,
          thumbnail: null,
          isDeleted: false,
          fileHash: "hash",
          derivedMetadata: DerivedMediaMetadata(
            width: dimensions?.width,
            height: dimensions?.height,
          ),
        ),
        null,
      );

      expect(inspection?.method, "getVideoInfo");
      expect(inspection?.arguments, {"videoPath": source.path});
      expect(metadata.publicMetadata[widthKey], 1080);
      expect(metadata.publicMetadata[heightKey], 1920);
      expect(metadata.publicMetadata[noThumbKey], isTrue);
    },
  );

  test("reuses metadata from a thumbnail of the same source", () async {
    failInspection = true;
    videoInfo = {
      ...videoInfo,
      "width": 1080,
      "height": 1920,
      "displayWidth": 1920,
      "displayHeight": 1080,
      "rotation": 270,
    };

    final dimensions = await getVideoUploadDimensions(
      source,
      sourceVideoInfo: NativeVideoInfo.fromMap(videoInfo),
    );

    expect(dimensions, (width: 1920, height: 1080));
    expect(inspection, isNull);
  });

  test("unreadable source prepares explicit null dimensions", () async {
    failInspection = true;
    final file = EnteFile()..fileType = FileType.video;
    final dimensions = await getVideoUploadDimensions(source);
    final metadata = await prepareUploadMetadata(
      file,
      MediaUploadData(
        sourceFile: source,
        thumbnail: Uint8List.fromList([0]),
        isDeleted: false,
        fileHash: "hash",
        derivedMetadata: DerivedMediaMetadata(
          width: dimensions?.width,
          height: dimensions?.height,
        ),
      ),
      null,
    );

    expect(dimensions, isNull);
    expect(metadata.publicMetadata, {widthKey: null, heightKey: null});
  });
}
