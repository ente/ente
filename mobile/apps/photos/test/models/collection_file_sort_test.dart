import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/models/metadata/collection_magic.dart";

void main() {
  test("legacy and unknown sort keys retain Boolean date direction", () {
    for (final asc in [null, false, true]) {
      for (final sortBy in [null, "futureOrder"]) {
        final metadata = CollectionPubMagicMetadata.fromMap({
          "asc": asc,
          "sortBy": sortBy,
        });
        expect(
          metadata.sortOrder,
          asc == true ? FileSortOrder.oldestFirst : FileSortOrder.newestFirst,
        );
        expect(metadata.toJson()["sortBy"], sortBy);
      }
    }
  });

  test("all sorts survive encoded metadata and switching back to dates", () {
    final stored = <String, dynamic>{
      "coverID": 42,
      "caption": "Demo",
      "futureField": 7,
    };
    for (final order in [
      FileSortOrder.filenameAscending,
      FileSortOrder.filenameDescending,
      FileSortOrder.oldestFirst,
      FileSortOrder.newestFirst,
    ]) {
      stored.addAll(order.metadata);
      final decoded = CollectionPubMagicMetadata.fromEncodedJson(
        jsonEncode(stored),
      );
      expect(decoded.sortOrder, order);
      expect(decoded.asc, order.ascending);
      expect(decoded.coverID, 42);
      expect(decoded.description, "Demo");
      expect(stored["futureField"], 7);
      expect(
        CollectionPubMagicMetadata.fromMap(decoded.toJson()).sortOrder,
        order,
      );
    }
  });
}
