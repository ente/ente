import "package:photos/models/file/file.dart";

class DummyFile extends EnteFile {
  final String groupID;
  final int index;

  DummyFile({required this.groupID, required this.index}) {
    // Negative IDs distinguish dummies from real files.
    generatedID = -(groupID.hashCode + index);
  }

  bool get isDummy => true;

  @override
  String get tag {
    return "dummy_${groupID}_$index";
  }
}
