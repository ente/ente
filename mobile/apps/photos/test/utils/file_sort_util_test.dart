import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/utils/file_sort_util.dart";

void main() {
  test(
    "natural filename order ignores ASCII case and keeps missing names last",
    () {
      final files = [
        _file(6, null),
        _file(4, "photo10.jpg"),
        _file(5, ""),
        _file(2, "Photo2.jpg"),
        _file(1, "apple.jpg"),
        _file(3, "photo3.jpg"),
      ];
      files.sort(compareFileNames);
      expect(files.map((f) => f.uploadedFileID), [1, 2, 3, 4, 5, 6]);
      files.sort((a, b) => compareFileNames(a, b, ascending: false));
      expect(files.map((f) => f.uploadedFileID), [4, 3, 2, 1, 5, 6]);
    },
  );

  test("uses the displayed filename after a rename", () {
    final renamed = _file(1, "z.jpg")
      ..pubMagicMetadata = PubMagicMetadata(editedName: "a.jpg");
    expect(compareFileNames(renamed, _file(2, "b.jpg")), lessThan(0));
  });

  test("equal names use stable remote, local and database identities", () {
    final first = _file(10, "Photo2.jpg");
    final second = _file(20, "photo2.jpg");
    for (final ascending in [false, true]) {
      expect(
        compareFileNames(first, second, ascending: ascending),
        lessThan(0),
      );
      final localA = EnteFile()
        ..title = "same"
        ..localID = "a";
      final localB = EnteFile()
        ..title = "same"
        ..localID = "b";
      expect(
        compareFileNames(localA, localB, ascending: ascending),
        lessThan(0),
      );
      localA.localID = localB.localID;
      localA.generatedID = 1;
      localB.generatedID = 2;
      expect(
        compareFileNames(localA, localB, ascending: ascending),
        lessThan(0),
      );
    }
  });

  test("numeric runs handle leading zeroes and numbers larger than an int", () {
    final names = [
      "photo100000000000000000001.jpg",
      "photo10.jpg",
      "photo02.jpg",
      "photo1.jpg",
    ];
    final files = [for (var i = 0; i < names.length; i++) _file(i, names[i])]
      ..sort(compareFileNames);
    expect(files.map((f) => f.title), [
      "photo1.jpg",
      "photo02.jpg",
      "photo10.jpg",
      "photo100000000000000000001.jpg",
    ]);
  });
}

EnteFile _file(int id, String? name) => EnteFile()
  ..uploadedFileID = id
  ..title = name;
