import "package:flutter_test/flutter_test.dart";
import "package:photos/core/constants.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/module/upload/service/existing_upload_resolver.dart";

void main() {
  test("already-uploaded input skips lookup and mapping", () async {
    final fixture = _Fixture();
    final pending = _file(localID: "local", uploadedFileID: 1);

    expect(await fixture.resolve(pending), isNull);
    expect(fixture.calls, isEmpty);
  });

  test("missing owner skips lookup and mapping", () async {
    final fixture = _Fixture();

    expect(
      await fixture.resolve(_file(localID: "local"), ownerID: null),
      isNull,
    );
    expect(fixture.calls, isEmpty);
  });

  test("no hash matches continues uploading", () async {
    final fixture = _Fixture();

    expect(await fixture.resolve(_file(localID: "local")), isNull);
    expect(fixture.calls, ["find:hash:${FileType.image.index}:10"]);
  });

  test("hash lookup failure propagates without side effects", () async {
    final fixture = _Fixture()..findError = _Error();

    await expectLater(
      fixture.resolve(_file(localID: "local")),
      throwsA(isA<_Error>()),
    );
    expect(fixture.calls, ["find:hash:${FileType.image.index}:10"]);
    expect(fixture.events, isEmpty);
  });

  test("case a deletes pending row before emitting deletion", () async {
    final existing = _file(
      localID: "local",
      uploadedFileID: 11,
      collectionID: 20,
    );
    final fixture = _Fixture(existingFiles: [existing]);
    final pending = _file(localID: "local", generatedID: 7);

    expect(await fixture.resolve(pending), same(existing));
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "delete:7",
      "event:deletedFromEverywhere:sameLocalSameCollection",
    ]);
    _expectDeletionEvent(
      fixture.events.single,
      pending,
      "sameLocalSameCollection",
    );
  });

  test(
    "case a emits deletion without deleting an absent pending row",
    () async {
      final existing = _file(
        localID: "local",
        uploadedFileID: 11,
        collectionID: 20,
      );
      final fixture = _Fixture(existingFiles: [existing]);
      final pending = _file(localID: "local");

      expect(await fixture.resolve(pending), same(existing));
      expect(fixture.calls, [
        "find:hash:${FileType.image.index}:10",
        "event:deletedFromEverywhere:sameLocalSameCollection",
      ]);
    },
  );

  test("case b updates local ID, deletes pending row, then emits", () async {
    final existing = _file(uploadedFileID: 12, collectionID: 30);
    final fixture = _Fixture(existingFiles: [existing]);
    final pending = _file(localID: "local", generatedID: 8);

    expect(await fixture.resolve(pending), same(existing));
    expect(existing.localID, "local");
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "update:12:local",
      "delete:8",
      "event:deletedFromEverywhere:fileMissingLocal",
    ]);
    _expectDeletionEvent(fixture.events.single, pending, "fileMissingLocal");
  });

  test("case c links matching local file from another collection", () async {
    final existing = _file(
      localID: "local",
      uploadedFileID: 13,
      collectionID: 30,
    );
    final linked = _file(
      localID: "local",
      uploadedFileID: 13,
      collectionID: 20,
    );
    final fixture = _Fixture(existingFiles: [existing], linkedFile: linked);
    final pending = _file(localID: "local", generatedID: 9);

    expect(await fixture.resolve(pending), same(linked));
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "link:20:local:13",
    ]);
    expect(fixture.linkedLocalFile, same(pending));
    expect(fixture.linkedExistingFile, same(existing));
    expect(fixture.events, isEmpty);
  });

  test("case d leaves a different local file untouched", () async {
    final existing = _file(
      localID: "other",
      uploadedFileID: 14,
      collectionID: 30,
    );
    final fixture = _Fixture(existingFiles: [existing]);

    expect(await fixture.resolve(_file(localID: "local")), isNull);
    expect(fixture.calls, ["find:hash:${FileType.image.index}:10"]);
    expect(fixture.events, isEmpty);
  });

  test("case priority remains a then b then c", () async {
    final caseC = _file(localID: "local", uploadedFileID: 13, collectionID: 30);
    final caseB = _file(uploadedFileID: 12, collectionID: 30);
    final caseA = _file(localID: "local", uploadedFileID: 11, collectionID: 20);
    final fixture = _Fixture(existingFiles: [caseC, caseB, caseA]);

    expect(await fixture.resolve(_file(localID: "local")), same(caseA));
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "event:deletedFromEverywhere:sameLocalSameCollection",
    ]);
  });

  test("case b remains preferred over case c", () async {
    final caseC = _file(localID: "local", uploadedFileID: 13, collectionID: 30);
    final caseB = _file(uploadedFileID: 12, collectionID: 30);
    final fixture = _Fixture(existingFiles: [caseC, caseB]);

    expect(await fixture.resolve(_file(localID: "local")), same(caseB));
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "update:12:local",
      "event:deletedFromEverywhere:fileMissingLocal",
    ]);
  });

  test("sandbox file ignores local ID for same-collection mapping", () async {
    final existing = _file(
      localID: "different",
      uploadedFileID: 11,
      collectionID: 20,
    );
    final fixture = _Fixture(existingFiles: [existing]);

    expect(
      await fixture.resolve(_file(localID: "${sharedMediaIdentifier}pending")),
      same(existing),
    );
  });

  test("sandbox file ignores local ID for cross-collection mapping", () async {
    final existing = _file(
      localID: "different",
      uploadedFileID: 13,
      collectionID: 30,
    );
    final linked = _file(uploadedFileID: 13, collectionID: 20);
    final fixture = _Fixture(existingFiles: [existing], linkedFile: linked);

    expect(
      await fixture.resolve(_file(localID: "${sharedMediaIdentifier}pending")),
      same(linked),
    );
  });

  test("delete failure prevents case a event", () async {
    final existing = _file(
      localID: "local",
      uploadedFileID: 11,
      collectionID: 20,
    );
    final fixture = _Fixture(existingFiles: [existing])..deleteError = _Error();

    await expectLater(
      fixture.resolve(_file(localID: "local", generatedID: 7)),
      throwsA(isA<_Error>()),
    );
    expect(fixture.calls, ["find:hash:${FileType.image.index}:10", "delete:7"]);
    expect(fixture.events, isEmpty);
  });

  test("event failure propagates after case a deletion", () async {
    final existing = _file(
      localID: "local",
      uploadedFileID: 11,
      collectionID: 20,
    );
    final fixture = _Fixture(existingFiles: [existing])..emitError = _Error();

    await expectLater(
      fixture.resolve(_file(localID: "local", generatedID: 7)),
      throwsA(isA<_Error>()),
    );
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "delete:7",
      "event:deletedFromEverywhere:sameLocalSameCollection",
    ]);
    expect(fixture.events, hasLength(1));
  });

  test("update failure prevents case b deletion and event", () async {
    final existing = _file(uploadedFileID: 12, collectionID: 30);
    final fixture = _Fixture(existingFiles: [existing])..updateError = _Error();

    await expectLater(
      fixture.resolve(_file(localID: "local", generatedID: 8)),
      throwsA(isA<_Error>()),
    );
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "update:12:local",
    ]);
    expect(existing.localID, isNull);
    expect(fixture.events, isEmpty);
  });

  test("link failure propagates without resolver event", () async {
    final existing = _file(
      localID: "local",
      uploadedFileID: 13,
      collectionID: 30,
    );
    final fixture = _Fixture(existingFiles: [existing])..linkError = _Error();

    await expectLater(
      fixture.resolve(_file(localID: "local")),
      throwsA(isA<_Error>()),
    );
    expect(fixture.calls, [
      "find:hash:${FileType.image.index}:10",
      "link:20:local:13",
    ]);
    expect(fixture.events, isEmpty);
  });
}

void _expectDeletionEvent(
  LocalPhotosUpdatedEvent event,
  EnteFile pending,
  String source,
) {
  expect(event.updatedFiles, [same(pending)]);
  expect(event.type, EventType.deletedFromEverywhere);
  expect(event.source, source);
}

EnteFile _file({
  String? localID,
  int? generatedID,
  int? uploadedFileID,
  int? collectionID,
  FileType fileType = FileType.image,
}) => EnteFile()
  ..localID = localID
  ..generatedID = generatedID
  ..uploadedFileID = uploadedFileID
  ..collectionID = collectionID
  ..fileType = fileType;

class _Fixture {
  _Fixture({List<EnteFile>? existingFiles, EnteFile? linkedFile})
    : existingFiles = existingFiles ?? [],
      linkedFile = linkedFile ?? _file(uploadedFileID: 99, collectionID: 20) {
    resolver = ExistingUploadResolver(
      findUploadedFiles: (hash, fileType, ownerID) async {
        calls.add("find:$hash:${fileType.index}:$ownerID");
        if (findError != null) throw findError!;
        return this.existingFiles;
      },
      deleteGeneratedFile: (generatedID) async {
        calls.add("delete:$generatedID");
        if (deleteError != null) throw deleteError!;
      },
      updateUploadedFileLocalID: (uploadedFileID, localID) async {
        calls.add("update:$uploadedFileID:$localID");
        if (updateError != null) throw updateError!;
      },
      linkExistingUpload:
          (
            collectionID, {
            required localFileToUpload,
            required existingUploadedFile,
          }) async {
            calls.add(
              "link:$collectionID:${localFileToUpload.localID}:"
              "${existingUploadedFile.uploadedFileID}",
            );
            linkedLocalFile = localFileToUpload;
            linkedExistingFile = existingUploadedFile;
            if (linkError != null) throw linkError!;
            return this.linkedFile;
          },
      emitLocalPhotosUpdated: (event) {
        calls.add("event:${event.type.name}:${event.source}");
        events.add(event);
        if (emitError != null) throw emitError!;
      },
    );
  }

  static const fileHash = "hash";
  static const defaultOwnerID = 10;
  static const targetCollectionID = 20;

  final List<EnteFile> existingFiles;
  final EnteFile linkedFile;
  final calls = <String>[];
  final events = <LocalPhotosUpdatedEvent>[];
  late final ExistingUploadResolver resolver;
  EnteFile? linkedLocalFile;
  EnteFile? linkedExistingFile;
  Object? deleteError;
  Object? findError;
  Object? emitError;
  Object? updateError;
  Object? linkError;
  Future<EnteFile?> resolve(
    EnteFile pending, {
    int? ownerID = defaultOwnerID,
  }) => resolver.resolve(
    fileHash: fileHash,
    fileToUpload: pending,
    targetCollectionID: targetCollectionID,
    ownerID: ownerID,
  );
}

class _Error extends Error {}
