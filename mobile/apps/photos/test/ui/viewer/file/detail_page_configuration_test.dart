import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/gallery_file_viewer_filmstrip.dart";

void main() {
  test("gallery filmstrip defaults off and copyWith preserves opt-in", () {
    final file = EnteFile()..fileType = FileType.image;

    final genericConfig = DetailPageConfiguration([file], 0, "generic");
    expect(genericConfig.showGalleryFilmstrip, isFalse);

    final galleryConfig = DetailPageConfiguration(
      [file],
      0,
      "gallery",
      showGalleryFilmstrip: true,
    );
    expect(galleryConfig.copyWith().showGalleryFilmstrip, isTrue);
  });

  test("gallery filmstrip requires an eligible gallery", () {
    for (final scenario in [
      (
        name: "eligible gallery",
        isEnabled: true,
        isMinimalistic: false,
        isGuestView: false,
        itemCount: 2,
        expected: true,
      ),
      (
        name: "not opted in",
        isEnabled: false,
        isMinimalistic: false,
        isGuestView: false,
        itemCount: 2,
        expected: false,
      ),
      (
        name: "minimalistic viewer",
        isEnabled: true,
        isMinimalistic: true,
        isGuestView: false,
        itemCount: 2,
        expected: false,
      ),
      (
        name: "guest view",
        isEnabled: true,
        isMinimalistic: false,
        isGuestView: true,
        itemCount: 2,
        expected: false,
      ),
      (
        name: "single file",
        isEnabled: true,
        isMinimalistic: false,
        isGuestView: false,
        itemCount: 1,
        expected: false,
      ),
    ]) {
      expect(
        shouldShowGalleryFileViewerFilmstrip(
          isEnabled: scenario.isEnabled,
          isMinimalistic: scenario.isMinimalistic,
          isGuestView: scenario.isGuestView,
          itemCount: scenario.itemCount,
        ),
        scenario.expected,
        reason: scenario.name,
      );
    }
  });
}
