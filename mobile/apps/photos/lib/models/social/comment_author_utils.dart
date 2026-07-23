import "package:photos/models/api/collection/user.dart";
import "package:photos/models/social/comment.dart";

class CommentAuthorResolver {
  final Map<int, User> _registeredUserCache = {};

  User resolve({
    required Comment comment,
    required Map<String, String> anonDisplayNames,
    required User Function(int userID) registeredUserResolver,
  }) {
    if (comment.isAnonymous) {
      return _anonymousUserForComment(comment, anonDisplayNames);
    }

    return _registeredUserCache.putIfAbsent(
      comment.userID,
      () => registeredUserResolver(comment.userID),
    );
  }

  void clear() {
    _registeredUserCache.clear();
  }
}

User _anonymousUserForComment(
  Comment comment,
  Map<String, String> anonDisplayNames,
) {
  final anonID = _normalizedAnonID(comment);
  final displayName = anonID != null
      ? (anonDisplayNames[anonID] ?? anonID)
      : "Anonymous";
  return User(
    id: comment.userID,
    email: "${anonID ?? "anonymous"}@unknown.com",
    name: displayName,
  );
}

class MissingAnonProfileSyncTracker {
  final Map<int, Set<String>> _attemptedIDsByCollection = {};

  Set<String> nextIDsToSync({
    required int collectionID,
    required Iterable<Comment> comments,
    required Map<String, String> anonDisplayNames,
  }) {
    final missingIDs = _missingAnonDisplayNameIDs(comments, anonDisplayNames);
    if (missingIDs.isEmpty) {
      return const <String>{};
    }

    final attemptedIDs = _attemptedIDsByCollection.putIfAbsent(
      collectionID,
      () => <String>{},
    );
    final nextIDs = missingIDs.difference(attemptedIDs);
    attemptedIDs.addAll(nextIDs);
    return nextIDs;
  }
}

Set<String> _missingAnonDisplayNameIDs(
  Iterable<Comment> comments,
  Map<String, String> anonDisplayNames,
) {
  final missing = <String>{};
  for (final comment in comments) {
    final anonID = _normalizedAnonID(comment);
    if (anonID != null && !anonDisplayNames.containsKey(anonID)) {
      missing.add(anonID);
    }
  }
  return missing;
}

String? _normalizedAnonID(Comment comment) {
  if (!comment.isAnonymous) {
    return null;
  }
  final anonID = comment.anonUserID?.trim();
  return anonID == null || anonID.isEmpty ? null : anonID;
}
