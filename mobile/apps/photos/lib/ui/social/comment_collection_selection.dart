int resolveInitialCommentsCollectionID({
  required int requestedCollectionID,
  required int? draftCollectionID,
  required bool preferDraftCollection,
  required bool hasHighlightedComment,
}) {
  return preferDraftCollection &&
          !hasHighlightedComment &&
          draftCollectionID != null
      ? draftCollectionID
      : requestedCollectionID;
}
