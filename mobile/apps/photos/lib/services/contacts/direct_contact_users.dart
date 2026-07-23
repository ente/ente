import "package:ente_contacts/contacts.dart" as contacts;
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/user_details.dart";
import "package:photos/utils/contact_string_util.dart";

/// Builds entries shown in Contacts.
///
/// Each user has a positive ID and a known, non-placeholder email address.
List<User> buildDirectContactUsers({
  required int ownerUserId,
  required String ownerEmail,
  required Iterable<Collection> collections,
  required Iterable<FamilyMember> familyMembers,
  required Iterable<contacts.ContactRecord> savedContacts,
}) {
  final ownerNormalizedEmail = normalizeContactLinkEmail(
    knownContactEmailOrNull(ownerEmail),
  );
  final usersById = <int, User>{};

  void addUser(User user) {
    final userId = user.id;
    if (userId == null || userId <= 0 || userId == ownerUserId) {
      return;
    }
    final normalizedEmail = normalizeContactLinkEmail(
      knownContactEmailOrNull(user.email),
    );
    if (normalizedEmail == null || normalizedEmail == ownerNormalizedEmail) {
      return;
    }

    usersById[userId] = user;
  }

  for (final collection in collections) {
    if (collection.isOwner(ownerUserId)) {
      for (final sharee in collection.sharees) {
        addUser(sharee);
      }
    } else {
      addUser(collection.owner);
    }
  }

  for (final member in familyMembers) {
    if (member.isActive) {
      addUser(User(id: member.userID, email: member.email));
    }
  }

  for (final contact in savedContacts) {
    final email = knownContactEmailOrNull(contact.email);
    if (email == null) {
      continue;
    }
    addUser(User(id: contact.contactUserId, email: email));
  }

  return usersById.values.toList(growable: false);
}
