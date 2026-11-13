import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_stage_policy.dart";

void main() {
  test("duplicate or clamped stages are skipped", () {
    const duplicateCover = ImageZoomStagePolicy(
      initialScale: 1,
      coverScale: 1,
      originalScale: 3,
      maxScale: 6,
    );
    expect(
      duplicateCover.nextDoubleTapStage(
        currentStage: ImageZoomStage.initial,
        currentScale: 1,
      ),
      ImageZoomStage.originalSize,
    );

    const duplicateOriginal = ImageZoomStagePolicy(
      initialScale: 1,
      coverScale: 2,
      originalScale: 2,
      maxScale: 6,
    );
    expect(
      duplicateOriginal.nextDoubleTapStage(
        currentStage: ImageZoomStage.covering,
        currentScale: 2,
      ),
      ImageZoomStage.initial,
    );

    const clamped = ImageZoomStagePolicy(
      initialScale: 1,
      coverScale: 2,
      originalScale: 3,
      maxScale: 1.5,
    );
    expect(
      clamped.nextDoubleTapStage(
        currentStage: ImageZoomStage.covering,
        currentScale: 1.5,
      ),
      ImageZoomStage.initial,
    );

    const allEqual = ImageZoomStagePolicy(
      initialScale: 1,
      coverScale: 1,
      originalScale: 1,
      maxScale: 1,
    );
    expect(
      allEqual.nextDoubleTapStage(
        currentStage: ImageZoomStage.initial,
        currentScale: 1,
      ),
      isNull,
    );
  });
}
