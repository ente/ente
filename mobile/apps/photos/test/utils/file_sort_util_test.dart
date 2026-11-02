import "package:flutter_test/flutter_test.dart";
import "package:icu4x/icu4x.dart" as icu;
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
    sortFilesByName(files, FileSortOrder.filenameAscending, localeTag: "sv-SE");
    expect(files, [local, uploaded, renamed]);
    sortFilesByName(
      files,
      FileSortOrder.filenameDescending,
      localeTag: "sv-SE",
    );
    expect(files, [uploaded, renamed, local]);
  });

  test(
    "sorts numbers naturally and keeps ascending IDs in both directions",
    () {
      final files = [
        _file(30, "IMG10.jpg"),
        _file(20, "img02.JPG"),
        _file(10, "IMG2.jpg"),
        _file(40, "IMG2.heic"),
      ];
      sortFilesByName(
        files,
        FileSortOrder.filenameAscending,
        localeTag: "en-US",
      );
      expect(files.map((file) => file.uploadedFileID), [40, 10, 20, 30]);
      sortFilesByName(
        files,
        FileSortOrder.filenameDescending,
        localeTag: "en-US",
      );
      expect(files.map((file) => file.uploadedFileID), [30, 10, 20, 40]);
    },
  );

  test("uses the requested locale for case and accented letters", () {
    final files = [_file(1, "z.jpg"), _file(2, "ä.jpg"), _file(3, "a.jpg")];
    sortFilesByName(files, FileSortOrder.filenameAscending, localeTag: "de-DE");
    expect(files.map((file) => file.uploadedFileID), [2, 3, 1]);
    sortFilesByName(files, FileSortOrder.filenameAscending, localeTag: "sv-SE");
    expect(files.map((file) => file.uploadedFileID), [3, 1, 2]);
    final accents = [_file(2, "café.jpg"), _file(1, "CAFE.jpg")];
    sortFilesByName(
      accents,
      FileSortOrder.filenameAscending,
      localeTag: "en-US",
    );
    expect(accents.map((file) => file.uploadedFileID), [1, 2]);
  });

  test("numeric shortcut preserves ICU ordering across mixed names", () {
    final names = [
      "IMG0.jpg",
      "IMG000.jpg",
      "IMG2.jpg",
      "IMG02.jpg",
      "img10.JPG",
      "IMG2.heic",
      "IMG10_2.jpg",
      "IMG2_10.jpg",
      "١2.jpg",
      "١02.jpg",
      "café.jpg",
      "cafe\u0301.jpg",
      "ä.jpg",
      "z.jpg",
      "I.jpg",
      "ı.jpg",
      "IMG${List.filled(253, '9').join()}.jpg",
      "IMG1${List.filled(253, '0').join()}.jpg",
      "IMG${List.filled(254, '9').join()}.jpg",
      "IMG1${List.filled(254, '0').join()}.jpg",
    ];
    final files = [for (var i = 0; i < names.length; i++) _file(i, names[i])];
    for (final tag in ["en-US", "sv-SE", "tr-TR"]) {
      final locale = icu.Locale.fromString(tag)
        ..setUnicodeExtension("kn", "true");
      final collator = icu.Collator(
        locale,
        icu.CollatorOptions(
          strength: icu.CollatorStrength.primary,
          caseLevel: icu.CollatorCaseLevel.off,
          alternateHandling: icu.CollatorAlternateHandling.nonIgnorable,
        ),
      );
      for (final order in [
        FileSortOrder.filenameAscending,
        FileSortOrder.filenameDescending,
      ]) {
        final expected = List<EnteFile>.of(files)
          ..sort((a, b) {
            final comparison = collator.compare(a.displayName, b.displayName);
            return comparison == 0
                ? a.uploadedFileID!.compareTo(b.uploadedFileID!)
                : order.ascending
                ? comparison
                : -comparison;
          });
        final actual = List<EnteFile>.of(files);
        sortFilesByName(actual, order, localeTag: tag);
        expect(actual, expected, reason: "$tag, ${order.name}");
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
