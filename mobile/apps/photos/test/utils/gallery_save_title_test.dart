import "package:photos/utils/gallery_save_title.dart";
import "package:test/test.dart";

void main() {
  group("sanitizePreAndroid11MediaStoreTitle", () {
    test("replaces fragment delimiters before the extension", () {
      expect(
        sanitizePreAndroid11MediaStoreTitle("trip#1#edited.mp4"),
        "trip_1_edited.mp4",
      );
    });

    test("preserves fragment delimiters after the extension", () {
      expect(sanitizePreAndroid11MediaStoreTitle("trip.mp4#1"), "trip.mp4#1");
    });

    test("preserves titles without a fragment delimiter", () {
      expect(
        sanitizePreAndroid11MediaStoreTitle("trip.edited.mp4"),
        "trip.edited.mp4",
      );
    });

    test("preserves titles without an extension", () {
      expect(sanitizePreAndroid11MediaStoreTitle("trip#1"), "trip#1");
    });
  });
}
