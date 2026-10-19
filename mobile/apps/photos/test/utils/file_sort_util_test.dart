import "dart:typed_data" show Uint32List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/src/rust/frb_generated.dart";
import "package:photos/utils/file_sort_util.dart";

void main() {
  test("sends effective names and IDs to Rust and applies its order", () async {
    final api = _FileSortApi();
    EntePhotosRust.initMock(api: api);
    addTearDown(EntePhotosRust.dispose);
    final renamed = _file(2, "z.jpg")
      ..pubMagicMetadata = PubMagicMetadata(editedName: "a.jpg");
    final local = EnteFile()
      ..title = "a.heic"
      ..generatedID = 3;
    final uploaded = _file(1, "a.jpg");
    final files = [renamed, local, uploaded];
    await sortFilesByName(
      files,
      FileSortOrder.filenameAscending,
      localeTag: "sv-SE",
    );
    expect(api.names, ["a.jpg", "a.heic", "a.jpg"]);
    expect(api.ids, [BigInt.from(2), BigInt.from(3), BigInt.one]);
    expect(api.locale, "sv-SE");
    expect(api.ascending, isTrue);
    expect(files, [local, uploaded, renamed]);
    await sortFilesByName(
      files,
      FileSortOrder.filenameDescending,
      localeTag: "sv-SE",
    );
    expect(api.ascending, isFalse);
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

class _FileSortApi extends Fake implements EntePhotosRustApi {
  List<String>? names;
  List<BigInt>? ids;
  String? locale;
  bool? ascending;

  @override
  Future<Uint32List> crateApiFileSortApiSortedFilenameIndices({
    required List<String> names,
    required Int64List fileIds,
    required String locale,
    required bool ascending,
  }) async {
    this.names = names;
    ids = fileIds.toList();
    this.locale = locale;
    this.ascending = ascending;
    return Uint32List.fromList([1, 2, 0]);
  }
}
