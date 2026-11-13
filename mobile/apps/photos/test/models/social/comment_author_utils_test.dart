import "package:photos/models/api/collection/user.dart";
import "package:photos/models/social/comment.dart";
import "package:photos/models/social/comment_author_utils.dart";
import "package:test/test.dart";

void main() {
  group("CommentAuthorResolver", () {
    test("does not reuse names for anonymous comments with same userID", () {
      final resolver = CommentAuthorResolver();
      final first = _comment(id: "comment-1", userID: -1, anonUserID: "anon-a");
      final second = _comment(
        id: "comment-2",
        userID: -1,
        anonUserID: "anon-b",
      );
      final anonDisplayNames = {"anon-a": "Alice", "anon-b": "Bob"};

      final firstUser = resolver.resolve(
        comment: first,
        anonDisplayNames: anonDisplayNames,
        registeredUserResolver: _registeredUser,
      );
      final secondUser = resolver.resolve(
        comment: second,
        anonDisplayNames: anonDisplayNames,
        registeredUserResolver: _registeredUser,
      );

      expect(firstUser.label, "Alice");
      expect(secondUser.label, "Bob");
    });
  });

  group("MissingAnonProfileSyncTracker", () {
    test(
      "requests sync only for missing anonymous IDs not already attempted",
      () {
        final tracker = MissingAnonProfileSyncTracker();
        final comments = [
          _comment(id: "comment-1", userID: -1, anonUserID: "anon-a"),
          _comment(id: "comment-2", userID: -1, anonUserID: "anon-b"),
          _comment(id: "comment-3", userID: 7),
        ];

        expect(
          tracker.nextIDsToSync(
            collectionID: 10,
            comments: comments,
            anonDisplayNames: const {"anon-a": "Alice"},
          ),
          {"anon-b"},
        );
        expect(
          tracker.nextIDsToSync(
            collectionID: 10,
            comments: comments,
            anonDisplayNames: const {"anon-a": "Alice"},
          ),
          isEmpty,
        );
        expect(
          tracker.nextIDsToSync(
            collectionID: 10,
            comments: [
              ...comments,
              _comment(id: "comment-4", userID: -1, anonUserID: "anon-c"),
            ],
            anonDisplayNames: const {"anon-a": "Alice", "anon-b": "Bob"},
          ),
          {"anon-c"},
        );
      },
    );
  });
}

Comment _comment({
  required String id,
  required int userID,
  String? anonUserID,
}) {
  return Comment(
    id: id,
    collectionID: 10,
    fileID: 20,
    data: "hello",
    userID: userID,
    anonUserID: anonUserID,
    createdAt: 1,
    updatedAt: 1,
  );
}

User _registeredUser(int userID) {
  return User(
    id: userID,
    email: "user-$userID@example.com",
    label: "User $userID",
  );
}
