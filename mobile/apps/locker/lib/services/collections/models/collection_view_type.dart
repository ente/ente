import "package:flutter/material.dart";
import "package:locker/services/collections/models/collection.dart";

enum CollectionViewType {
  ownedCollection,
  sharedCollectionViewer,
  sharedCollectionCollaborator,
  hiddenOwnedCollection,
  hiddenSection,
  quickLink,
  uncategorized,
  favorite,
}

extension CollectionViewTypeActions on CollectionViewType {
  bool get isIncomingShare =>
      this == CollectionViewType.sharedCollectionViewer ||
      this == CollectionViewType.sharedCollectionCollaborator;

  bool get showDownloadOption => true;

  bool get showEditOption => !isIncomingShare;

  bool get showDeleteOption => !isIncomingShare;

  bool get showShareOption => !isIncomingShare;

  bool get showAddToCollectionOption => !isIncomingShare;

  bool get showOfflineOption => !isIncomingShare;

  bool get showMarkImportantOption => !isIncomingShare;
}

CollectionViewType getCollectionViewType(Collection c, int userID) {
  if (!c.isOwner(userID)) {
    final role = c.getRole(userID);
    if (role == CollectionParticipantRole.collaborator) {
      return CollectionViewType.sharedCollectionCollaborator;
    }
    return CollectionViewType.sharedCollectionViewer;
  }
  if (c.isDefaultHidden()) {
    return CollectionViewType.hiddenSection;
  } else if (c.type == CollectionType.uncategorized) {
    return CollectionViewType.uncategorized;
  } else if (c.type == CollectionType.favorites) {
    return CollectionViewType.favorite;
  } else if (c.isQuickLinkCollection()) {
    return CollectionViewType.quickLink;
  } else if (c.isHidden()) {
    return CollectionViewType.hiddenOwnedCollection;
  }
  debugPrint(
    "Unknown collection type for collection ${c.id}, falling back to default",
  );
  return CollectionViewType.ownedCollection;
}
