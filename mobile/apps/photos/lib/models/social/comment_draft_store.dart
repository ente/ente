import "package:photos/core/event_bus.dart";
import "package:photos/events/user_logged_out_event.dart";
import "package:photos/models/social/comment.dart";

typedef CommentDraftFileKey = ({int fileID, int userID});
typedef CommentDraftKey = ({int collectionID, int fileID, int userID});

class CommentDraft {
  const CommentDraft({required this.text, required this.replyingTo});

  final String text;
  final Comment? replyingTo;
}

class CommentDraftStore {
  CommentDraftStore._() {
    Bus.instance.on<UserLoggedOutEvent>().listen((_) => clear());
  }

  static final instance = CommentDraftStore._();

  final Map<CommentDraftKey, CommentDraft> _drafts = {};
  final Map<CommentDraftFileKey, int> _lastSelectedCollectionIDs = {};

  CommentDraft? draftFor(CommentDraftKey key) => _drafts[key];

  int? lastSelectedCollectionID(CommentDraftFileKey key) =>
      _lastSelectedCollectionIDs[key];

  void save(CommentDraftKey key, CommentDraft draft) {
    _lastSelectedCollectionIDs[_fileKey(key)] = key.collectionID;
    _drafts[key] = draft;
  }

  void remove(CommentDraftKey key) {
    _drafts.remove(key);
    final fileKey = _fileKey(key);
    if (_lastSelectedCollectionIDs[fileKey] != key.collectionID) {
      return;
    }
    final nextCollectionID = _firstDraftCollectionID(fileKey);
    if (nextCollectionID == null) {
      _lastSelectedCollectionIDs.remove(fileKey);
    } else {
      _lastSelectedCollectionIDs[fileKey] = nextCollectionID;
    }
  }

  void clear() {
    _drafts.clear();
    _lastSelectedCollectionIDs.clear();
  }

  CommentDraftFileKey _fileKey(CommentDraftKey key) =>
      (userID: key.userID, fileID: key.fileID);

  int? _firstDraftCollectionID(CommentDraftFileKey fileKey) {
    for (final key in _drafts.keys) {
      if (key.userID == fileKey.userID && key.fileID == fileKey.fileID) {
        return key.collectionID;
      }
    }
    return null;
  }
}
