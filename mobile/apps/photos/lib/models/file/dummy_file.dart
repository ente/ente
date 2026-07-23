import "package:photos/models/file/file.dart";

/// A dummy file used to fill empty spaces in gallery grid rows to help with
/// swipe-to-select.
/// Can be uniquely identified by groupID and index within the group.
class DummyFile extends EnteFile {
  final String groupID;
  final int index;

  DummyFile({required this.groupID, required this.index}) {
    // Set a unique generatedID based on groupID and index
    // Using a negative number to distinguish from real files
    generatedID = -(groupID.hashCode + index);
  }

  bool get isDummy => true;

  @override
  String get tag {
    return "dummy_${groupID}_$index";
  }
}
