import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/db/social_db.dart";
import "package:photos/models/social/comment.dart";
import "package:photos/models/social/reaction.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previousPathProvider = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp("social_db_test_");
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  setUp(() => SocialDB.instance.clearAllData());

  tearDownAll(() async {
    await (await SocialDB.instance.database).close();
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  test("heart state stays inside the requested collection scope", () async {
    await SocialDB.instance.upsertReactions([
      _reaction(id: "hidden", collectionID: 20, userID: 1),
      _reaction(id: "deleted", collectionID: 20, userID: 2, isDeleted: true),
      _reaction(
        id: "comment-reaction",
        collectionID: 10,
        userID: 2,
        commentID: "comment",
      ),
    ]);

    expect(
      await SocialDB.instance.hasUserReactedToFileInCollections(100, 1, [10]),
      isFalse,
    );
    expect(
      await SocialDB.instance.hasUserReactedToFileInCollections(100, 1, [
        10,
        20,
      ]),
      isTrue,
    );
    expect(
      await SocialDB.instance.hasUserReactedToFileInCollections(100, 2, [
        10,
        20,
      ]),
      isFalse,
    );
  });

  test("latest comment stays inside the eligible collection scope", () async {
    await SocialDB.instance.upsertComments([
      _comment(id: "visible", collectionID: 10, createdAt: 10),
      _comment(id: "hidden", collectionID: 20, createdAt: 20),
    ]);

    final visibleLatest = await SocialDB.instance.getLatestCommentForFile(
      100,
      candidateCollectionIDs: [10],
    );
    expect(visibleLatest?.id, "visible");
  });

  test("comment count stays inside the requested collection scope", () async {
    await SocialDB.instance.upsertComments([
      _comment(id: "visible", collectionID: 10, createdAt: 10),
      _comment(id: "hidden", collectionID: 20, createdAt: 20),
      _comment(id: "deleted", collectionID: 20, createdAt: 30, isDeleted: true),
    ]);

    expect(
      await SocialDB.instance.getCommentCountForFileInCollections(100, [10]),
      1,
    );
    expect(
      await SocialDB.instance.getCommentCountForFileInCollections(100, [
        10,
        20,
      ]),
      2,
    );
  });
}

Reaction _reaction({
  required String id,
  required int collectionID,
  required int userID,
  bool isDeleted = false,
  String? commentID,
}) {
  return Reaction(
    id: id,
    collectionID: collectionID,
    fileID: 100,
    commentID: commentID,
    data: "❤",
    isDeleted: isDeleted,
    userID: userID,
    createdAt: 1,
    updatedAt: 1,
  );
}

Comment _comment({
  required String id,
  required int collectionID,
  required int createdAt,
  bool isDeleted = false,
}) {
  return Comment(
    id: id,
    collectionID: collectionID,
    fileID: 100,
    data: id,
    isDeleted: isDeleted,
    userID: 1,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
