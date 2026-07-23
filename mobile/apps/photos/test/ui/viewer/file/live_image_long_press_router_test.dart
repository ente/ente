import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/file/live_image_long_press_router.dart";

void main() {
  test("untagged motion photos retain playback after probing", () async {
    var probes = 0;
    final router = LiveImageLongPressRouter(
      motionVideoIndex: null,
      probeMotionPhoto: () async {
        probes++;
        return MotionPhotoAvailability.present;
      },
    );

    expect(await router.resolve(), LiveImageLongPressAction.playback);
    expect(await router.resolve(), LiveImageLongPressAction.playback);
    expect(probes, 1);
  });

  test("untagged still photos fall back to text selection", () async {
    var probes = 0;
    final router = LiveImageLongPressRouter(
      motionVideoIndex: null,
      probeMotionPhoto: () async {
        probes++;
        return MotionPhotoAvailability.absent;
      },
    );

    expect(await router.resolve(), LiveImageLongPressAction.textSelection);
    expect(await router.resolve(), LiveImageLongPressAction.textSelection);
    expect(probes, 1);
  });

  test("an explicit absent marker skips the motion photo probe", () async {
    var probes = 0;
    final router = LiveImageLongPressRouter(
      motionVideoIndex: 0,
      probeMotionPhoto: () async {
        probes++;
        return MotionPhotoAvailability.present;
      },
    );

    expect(await router.resolve(), LiveImageLongPressAction.textSelection);
    expect(probes, 0);
  });
}
