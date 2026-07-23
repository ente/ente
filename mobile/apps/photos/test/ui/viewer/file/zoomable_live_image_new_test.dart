import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mockito/mockito.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/ui/viewer/file/file_widget.dart";
import "package:photos/ui/viewer/file/zoomable_live_image_new.dart";

void main() {
  test("FileWidget forwards still-photo long presses", () {
    final file = EnteFile()
      ..generatedID = 1
      ..fileType = FileType.image;
    void onTextSelectionStart(LongPressStartDetails _) {}

    final built = FileWidget(
      file,
      tagPrefix: "test",
      onTextSelectionStart: onTextSelectionStart,
    ).build(_MockBuildContext());

    expect(built, isA<ZoomableLiveImageNew>());
    expect(
      (built as ZoomableLiveImageNew).onTextSelectionStart,
      same(onTextSelectionStart),
    );
  });
}

class _MockBuildContext extends Mock implements BuildContext {}
