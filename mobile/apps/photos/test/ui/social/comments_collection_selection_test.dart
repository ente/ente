import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/social/comment_collection_selection.dart";

void main() {
  group("initial comments collection", () {
    test("prefers a collection containing an unsent draft", () {
      expect(
        resolveInitialCommentsCollectionID(
          requestedCollectionID: 10,
          draftCollectionID: 20,
          preferDraftCollection: true,
          hasHighlightedComment: false,
        ),
        20,
      );
    });

    test("keeps the requested collection for an explicit comment tap", () {
      expect(
        resolveInitialCommentsCollectionID(
          requestedCollectionID: 10,
          draftCollectionID: 20,
          preferDraftCollection: false,
          hasHighlightedComment: false,
        ),
        10,
      );
    });

    test("keeps the requested collection for a highlighted comment", () {
      expect(
        resolveInitialCommentsCollectionID(
          requestedCollectionID: 10,
          draftCollectionID: 20,
          preferDraftCollection: true,
          hasHighlightedComment: true,
        ),
        10,
      );
    });
  });
}
