import "package:photos/events/event.dart";

class DetailsSheetEvent extends Event {
  final String fileTag;
  final int? uploadedFileID;
  final String? localID;
  final bool opened;

  DetailsSheetEvent({
    required this.fileTag,
    required this.localID,
    required this.uploadedFileID,
    required this.opened,
  });

  bool isSameFile({String? fileTag, int? uploadedFileID, String? localID}) =>
      fileTag != null
      ? this.fileTag == fileTag
      : this.uploadedFileID == uploadedFileID && this.localID == localID;
}
