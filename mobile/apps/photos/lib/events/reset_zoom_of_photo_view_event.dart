import "package:photos/events/event.dart";

class ResetZoomOfPhotoView extends Event {
  final int? uploadedFileID;
  final String? localID;

  ResetZoomOfPhotoView({required this.localID, required this.uploadedFileID});

  bool isSamePhoto({required int? uploadedFileID, required String? localID}) {
    if (this.uploadedFileID == uploadedFileID && this.localID == localID) {
      return true;
    }
    return false;
  }
}
