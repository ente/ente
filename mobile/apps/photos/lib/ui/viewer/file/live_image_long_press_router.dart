enum MotionPhotoAvailability { unknown, absent, present }

enum LiveImageLongPressAction { playback, textSelection }

class LiveImageLongPressRouter {
  LiveImageLongPressRouter({
    required int? motionVideoIndex,
    required Future<MotionPhotoAvailability> Function() probeMotionPhoto,
  }) : _availability = switch (motionVideoIndex) {
         final index? when index > 0 => MotionPhotoAvailability.present,
         0 => MotionPhotoAvailability.absent,
         _ => MotionPhotoAvailability.unknown,
       },
       _probeMotionPhoto = probeMotionPhoto;

  MotionPhotoAvailability _availability;
  final Future<MotionPhotoAvailability> Function() _probeMotionPhoto;

  Future<LiveImageLongPressAction> resolve() async {
    if (_availability == MotionPhotoAvailability.unknown) {
      final availability = await _probeMotionPhoto();
      if (availability != MotionPhotoAvailability.unknown) {
        _availability = availability;
      }
    }
    return _availability == MotionPhotoAvailability.present
        ? LiveImageLongPressAction.playback
        : LiveImageLongPressAction.textSelection;
  }
}
