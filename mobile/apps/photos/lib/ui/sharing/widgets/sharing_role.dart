import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";

const shareableCollectionRoles = [
  CollectionParticipantRole.viewer,
  CollectionParticipantRole.collaborator,
  CollectionParticipantRole.admin,
];

List<List<dynamic>> sharingRoleIcon(CollectionParticipantRole role) {
  return switch (role) {
    CollectionParticipantRole.owner ||
    CollectionParticipantRole.admin => HugeIcons.strokeRoundedCrown,
    CollectionParticipantRole.collaborator => HugeIcons.strokeRoundedUserGroup,
    CollectionParticipantRole.viewer ||
    CollectionParticipantRole.unknown => HugeIcons.strokeRoundedView,
  };
}

List<List<dynamic>> albumSharingRoleIcon(CollectionParticipantRole role) {
  return switch (role) {
    CollectionParticipantRole.owner ||
    CollectionParticipantRole.admin => HugeIcons.strokeRoundedCrown03,
    _ => sharingRoleIcon(role),
  };
}

String normalizedSharingEmail(String email) => email.trim().toLowerCase();

bool collectionNeedsShare(Collection collection, String email) {
  final normalized = normalizedSharingEmail(email);
  return normalizedSharingEmail(collection.owner.email) != normalized &&
      !collection.sharees.any(
        (sharee) => normalizedSharingEmail(sharee.email) == normalized,
      );
}

String shareableRoleLabel(
  BuildContext context,
  CollectionParticipantRole role,
) {
  return switch (role) {
    CollectionParticipantRole.viewer => context.strings.viewer,
    CollectionParticipantRole.collaborator => context.strings.collaborator,
    CollectionParticipantRole.admin => context.strings.admin,
    CollectionParticipantRole.owner ||
    CollectionParticipantRole.unknown => context.strings.viewer,
  };
}

String shareableRoleDescription(
  BuildContext context,
  CollectionParticipantRole role,
) {
  return switch (role) {
    CollectionParticipantRole.viewer => context.strings.viewerRoleDescription,
    CollectionParticipantRole.collaborator =>
      context.strings.collaboratorRoleDescription,
    CollectionParticipantRole.admin => context.strings.adminRoleDescription,
    CollectionParticipantRole.owner ||
    CollectionParticipantRole.unknown => context.strings.viewerRoleDescription,
  };
}

int sharingRoleRank(CollectionParticipantRole role) {
  return switch (role) {
    CollectionParticipantRole.owner => -1,
    CollectionParticipantRole.admin => 0,
    CollectionParticipantRole.collaborator => 1,
    CollectionParticipantRole.viewer || CollectionParticipantRole.unknown => 2,
  };
}

List<User> sortedCollectionSharees(Collection collection) {
  final sharees = List<User>.from(collection.sharees);
  sharees.sort((a, b) {
    final rankComparison = sharingRoleRank(
      collection.getRole(a.id),
    ).compareTo(sharingRoleRank(collection.getRole(b.id)));
    return rankComparison != 0
        ? rankComparison
        : a.email.toLowerCase().compareTo(b.email.toLowerCase());
  });
  return sharees;
}
