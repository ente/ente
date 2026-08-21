import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";

void main() {
  group("week group range", () {
    test("includes Monday through the final microsecond of Sunday", () {
      final monday = DateTime(2026, 8, 17);
      final nextMonday = DateTime(2026, 8, 24);
      final sundayFinalMicrosecond = nextMonday.subtract(
        const Duration(microseconds: 1),
      );

      final range = GroupType.week.getGroupRange(
        _fileAt(sundayFinalMicrosecond),
      );

      expect(range, (
        monday.microsecondsSinceEpoch,
        sundayFinalMicrosecond.microsecondsSinceEpoch,
      ));
    });
  });
}

EnteFile _fileAt(DateTime date) {
  return EnteFile()..creationTime = date.microsecondsSinceEpoch;
}
