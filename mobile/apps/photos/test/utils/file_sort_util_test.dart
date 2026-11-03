import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/utils/file_sort_util.dart";

void main() {
  test("sorts effective names including extensions with ascending ID ties", () {
    final renamed = _file(2, "z.jpg")
      ..pubMagicMetadata = PubMagicMetadata(editedName: "a.jpg");
    final local = EnteFile()
      ..title = "a.heic"
      ..generatedID = 3;
    final uploaded = _file(1, "a.jpg");
    final files = [renamed, local, uploaded];
    sortFilesByName(files, FileSortOrder.filenameAscending);
    expect(files, [local, uploaded, renamed]);
    sortFilesByName(files, FileSortOrder.filenameDescending);
    expect(files, [uploaded, renamed, local]);
  });

  test("sorts numbers naturally with case and leading-zero distinctions", () {
    final files = [
      _file(30, "IMG10.jpg"),
      _file(20, "img02.JPG"),
      _file(10, "IMG2.jpg"),
      _file(40, "IMG2.heic"),
      _file(5, "img2.jpg"),
    ];
    sortFilesByName(files, FileSortOrder.filenameAscending);
    expect(files.map((file) => file.uploadedFileID), [40, 10, 5, 20, 30]);
    sortFilesByName(files, FileSortOrder.filenameDescending);
    expect(files.map((file) => file.uploadedFileID), [30, 20, 5, 10, 40]);
  });

  test("uses locale-independent ordering for accented names", () {
    final files = [_file(1, "z.jpg"), _file(2, "ä.jpg"), _file(3, "a.jpg")];
    sortFilesByName(files, FileSortOrder.filenameAscending);
    expect(files.map((file) => file.uploadedFileID), [3, 1, 2]);
    sortFilesByName(files, FileSortOrder.filenameDescending);
    expect(files.map((file) => file.uploadedFileID), [2, 1, 3]);
  });

  test("selects the same first file as sorting without reordering input", () {
    final local = EnteFile()
      ..title = "a.heic"
      ..generatedID = 3;
    final renamed = _file(2, "z.jpg")
      ..pubMagicMetadata = PubMagicMetadata(editedName: "a.jpg");
    final samples = <List<EnteFile>>[
      [],
      [_file(1, "only.jpg")],
      [
        _file(30, "IMG10.jpg"),
        _file(20, "img02.JPG"),
        _file(10, "IMG2.jpg"),
        _file(5, "IMG010.jpg"),
        _file(1, "IMG2.jpg"),
      ],
      [
        _file(20, "café.jpg"),
        _file(10, "CAFE.jpg"),
        _file(30, "cafe\u0301.jpg"),
      ],
      [
        _file(1, "z.jpg"),
        _file(2, "ä.jpg"),
        _file(3, "a.jpg"),
        _file(4, "ı.jpg"),
      ],
      [renamed, local, _file(1, "a.jpg")],
    ];
    for (final order in [
      FileSortOrder.filenameAscending,
      FileSortOrder.filenameDescending,
    ]) {
      for (final sample in samples) {
        for (final files in [sample, sample.reversed.toList()]) {
          final original = List<EnteFile>.of(files);
          final sorted = List<EnteFile>.of(files);
          sortFilesByName(sorted, order);
          expect(
            firstFileByName(files, order),
            same(sorted.firstOrNull),
            reason: order.name,
          );
          expect(files, orderedEquals(original));
        }
      }
    }
  });

  test("album metadata round-trips every sort and defaults to date", () {
    for (final order in FileSortOrder.values) {
      final metadata = CollectionPubMagicMetadata.fromMap(order.metadata);
      expect(metadata.fileSortOrder, order);
      expect(
        CollectionPubMagicMetadata.fromMap(metadata.toJson()).fileSortOrder,
        order,
      );
    }
    expect(
      CollectionPubMagicMetadata.fromMap({}).fileSortOrder,
      FileSortOrder.newestFirst,
    );
    expect(
      CollectionPubMagicMetadata.fromMap({
        "sortBy": "unknown",
        "asc": true,
      }).fileSortOrder,
      FileSortOrder.oldestFirst,
    );
    expect(FileSortOrder.newestFirst.metadata["sortBy"], "date");
  });
}

EnteFile _file(int id, String name) => EnteFile()
  ..uploadedFileID = id
  ..title = name;
