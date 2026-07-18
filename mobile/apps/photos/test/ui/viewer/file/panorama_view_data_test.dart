import "dart:ui";

import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/panorama_view_data.dart";

void main() {
  group("PanoramaViewData.fromXmp", () {
    test("parses Pixel GPano metadata (issue #11435 sample)", () {
      // GPano values from the Pixel 8a sample panorama attached to
      // https://github.com/ente-io/ente/issues/11435
      final data = PanoramaViewData.fromXmp(const {
        "GPano:CroppedAreaLeftPixels": "6183",
        "GPano:CroppedAreaTopPixels": "1040",
        "GPano:CroppedAreaImageWidthPixels": "2520",
        "GPano:CroppedAreaImageHeightPixels": "1664",
        "GPano:FullPanoWidthPixels": "8762",
        "GPano:FullPanoHeightPixels": "4381",
        "GPano:InitialViewHeadingDegrees": "305",
        "GPano:ProjectionType": "equirectangular",
      });

      expect(data, isNotNull);
      expect(data!.croppedArea, const Rect.fromLTWH(6183, 1040, 2520, 1664));
      expect(data.fullWidth, 8762);
      expect(data.fullHeight, 4381);
    });

    test("initial longitude points at the cropped area center", () {
      const data = PanoramaViewData(
        fullWidth: 8762,
        fullHeight: 4381,
        croppedArea: Rect.fromLTWH(6183, 1040, 2520, 1664),
      );
      // Crop center sits at u = (6183 + 1260) / 8762 = 0.8495 of the full
      // canvas; the widget's longitude 0 faces u = 0 and longitude L faces
      // u = 1 - L / 360, hence L = (1 - 0.8495) * 360.
      expect(data.initialLongitude, closeTo(54.19, 0.01));
      // Matches the recorded compass heading of the sample within rounding:
      // GPano:InitialViewHeadingDegrees = 305 = 0.8495 * 360.
      final uCenter = 1 - data.initialLongitude / 360;
      expect(uCenter * 360, closeTo(305.8, 0.1));
    });

    test("initial longitude is normalized to [-180, 180]", () {
      const data = PanoramaViewData(
        fullWidth: 1000,
        fullHeight: 500,
        croppedArea: Rect.fromLTWH(100, 100, 200, 300),
      );
      // uCenter = 0.2 -> raw longitude 288 -> normalized -72.
      expect(data.initialLongitude, closeTo(-72, 0.001));
    });

    test("derives full height and top for Samsung-style metadata", () {
      final data = PanoramaViewData.fromXmp(const {
        "GPano:CroppedAreaLeftPixels": "1024",
        "GPano:CroppedAreaImageWidthPixels": "6144",
        "GPano:CroppedAreaImageHeightPixels": "1536",
        "GPano:FullPanoWidthPixels": "8192",
        "GPano:ProjectionType": "cylindrical",
      });

      expect(data, isNotNull);
      expect(data!.fullHeight, 4096);
      expect(data.croppedArea, const Rect.fromLTWH(1024, 1280, 6144, 1536));
    });

    test("re-centers inconsistently rotated metadata", () {
      final data = PanoramaViewData.fromXmp(const {
        "GPano:CroppedAreaLeftPixels": "100",
        "GPano:CroppedAreaTopPixels": "200",
        "GPano:CroppedAreaImageWidthPixels": "1000",
        "GPano:CroppedAreaImageHeightPixels": "3000",
        "GPano:FullPanoWidthPixels": "8000",
        "GPano:FullPanoHeightPixels": "4000",
      });

      expect(data, isNotNull);
      expect(data!.croppedArea, const Rect.fromLTWH(2500, 1500, 3000, 1000));
      expect(data.fullWidth, 8000);
      expect(data.fullHeight, 4000);
    });

    test("returns null when GPano crop metadata is missing", () {
      expect(
        PanoramaViewData.fromXmp(const {
          "GPano:ProjectionType": "equirectangular",
        }),
        isNull,
      );
      expect(PanoramaViewData.fromXmp(const {}), isNull);
    });
  });
}
