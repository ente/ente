import "package:photos/events/event.dart";
import "package:photos/models/file/file.dart";

class DetailsSheetEvent extends Event {
  static final _unknownFileIdentities = Expando<Object>();

  static Object identityFor(EnteFile file) {
    if (file.generatedID != null) return "generated:${file.generatedID}";
    if (file.localID != null) return "local:${file.localID}";
    if (file.uploadedFileID != null) return "remote:${file.uploadedFileID}";
    return _unknownFileIdentities[file] ??= Object();
  }

  final Object fileIdentity;
  final int? uploadedFileID;
  final String? localID;
  final bool opened;

  DetailsSheetEvent({
    required this.fileIdentity,
    required this.localID,
    required this.uploadedFileID,
    required this.opened,
  });

  bool isSameFile({
    Object? fileIdentity,
    int? uploadedFileID,
    String? localID,
  }) => fileIdentity != null
      ? this.fileIdentity == fileIdentity
      : this.uploadedFileID == uploadedFileID && this.localID == localID;
}
