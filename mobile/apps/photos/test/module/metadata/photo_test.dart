import "package:flutter_test/flutter_test.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/module/metadata/photo.dart";
import "package:photos/src/rust/api/metadata_api.dart";

void main() {
  test("media detection replaces prior state and preserves other metadata", () {
    final file = EnteFile()
      ..pubMmdEncodedJson = '{"mediaType":1,"mvi":42,"caption":"Keep me"}';
    applyMediaTypeMetadata(file, false, null);
    expect(file.pubMagicMetadata!.mediaType, 0);
    expect(file.pubMagicMetadata!.mvi, isNull);
    expect(file.pubMagicMetadata!.caption, "Keep me");
    applyMediaTypeMetadata(file, true, 1234);
    expect(file.pubMagicMetadata!.mediaType, 1);
    expect(file.pubMagicMetadata!.mvi, 1234);
  });

  test("local discovery supplies oriented mosaic dimensions", () {
    final file = fileFromAsset(
      "Camera",
      AssetEntity(
        id: "rotated",
        typeInt: 1,
        width: 4000,
        height: 3000,
        orientation: 90,
        createDateSecond: 1704110400,
        modifiedDateSecond: 1704110400,
      ),
    );
    expect((file.width, file.height), (3000, 4000));
    expect(file.metadataVersion, -1);
  });

  test("keeps an earlier MediaStore modification time without EXIF", () {
    final file = fileFromAsset(
      "EnteThumbnailBench",
      AssetEntity(
        id: "bench",
        typeInt: 1,
        width: 4032,
        height: 3024,
        title: "bench-IMG_8606_rotate_90_cw_contains_text.HEIC",
        createDateSecond: 1786506608,
        modifiedDateSecond: 1786450130,
      ),
    );

    expect(file.creationTime, 1786450130 * Duration.microsecondsPerSecond);
    applyCreationTimeMetadata(file, null);
    expect(file.creationTime, 1786450130 * Duration.microsecondsPerSecond);
  });

  test(
    "refined dimensions invalidate the model cache and preserve other fields",
    () {
      final file = EnteFile()
        ..pubMmdEncodedJson = '{"w":4000,"h":3000,"caption":"Keep me"}';
      expect(file.width, 4000);
      expect(file.pubMagicMetadata!.caption, "Keep me");
      applyDisplayDimensions(file, 1200, 1600);
      expect((file.width, file.height), (1200, 1600));
      expect(file.pubMagicMetadata!.caption, "Keep me");
      applyDisplayDimensions(file, 0, 100);
      expect((file.width, file.height), (1200, 1600));
    },
  );

  test("uses the parsed instant without applying the offset twice", () {
    const metadata = PhotoMetadata(
      dimensions: null,
      isPanorama: false,
      motionVideoStart: null,
      location: null,
      captureDateTime: CaptureDateTime(
        dateTime: "2024-01-01T12:00:00.123456",
        offsetTime: "-00:30",
        timestampMicros: 1704112200123456,
      ),
    );
    final date = metadata.creationDateTime!;
    expect(date.time.toUtc(), DateTime.utc(2024, 1, 1, 12, 30, 0, 123, 456));
    expect(date.dateTime, "2024-01-01T12:00:00.123456");
    expect(date.offsetTime, "-00:30");
  });

  test("resolves an offset-free time locally without inventing an offset", () {
    const metadata = PhotoMetadata(
      dimensions: null,
      isPanorama: false,
      motionVideoStart: null,
      location: null,
      captureDateTime: CaptureDateTime(
        dateTime: "2024-01-01T12:00:00",
        offsetTime: null,
        timestampMicros: null,
      ),
    );
    final date = metadata.creationDateTime!;
    expect(date.time, DateTime(2024, 1, 1, 12));
    expect(date.offsetTime, isNull);
  });
}
