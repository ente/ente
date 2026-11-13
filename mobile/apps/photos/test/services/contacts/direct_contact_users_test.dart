import "package:ente_contacts/contacts.dart" as contacts;
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/user_details.dart";
import "package:photos/services/contacts/direct_contact_users.dart";

void main() {
  test("includes only direct contact sources", () {
    final users = buildDirectContactUsers(
      ownerUserId: 1,
      ownerEmail: "me@example.com",
      collections: [
        _collection(
          owner: User(id: 1, email: "me@example.com"),
          sharees: [User(id: 2, email: "shared-by-me@example.com")],
        ),
        _collection(
          owner: User(id: 3, email: "shared-with-me@example.com"),
          sharees: [
            User(id: 1, email: "me@example.com"),
            User(id: 4, email: "unrelated-collaborator@example.com"),
          ],
        ),
      ],
      familyMembers: [
        _familyMember(
          "family@example.com",
          FamilyMemberStatus.accepted,
          userID: 6,
        ),
        _familyMember("pending@example.com", FamilyMemberStatus.invited),
      ],
      savedContacts: [
        _savedContact(id: "contact-1", userID: 5, email: "saved@example.com"),
      ],
    );

    expect(users.map((user) => user.email).toSet(), {
      "shared-by-me@example.com",
      "shared-with-me@example.com",
      "family@example.com",
      "saved@example.com",
    });
    expect(
      users.singleWhere((user) => user.email == "family@example.com").id,
      6,
    );
  });

  test("deduplicates by user id after an email change", () {
    final users = buildDirectContactUsers(
      ownerUserId: 1,
      ownerEmail: "me@example.com",
      collections: [
        _collection(
          owner: User(id: 1, email: "me@example.com"),
          sharees: [User(id: 5, email: "old@example.com")],
        ),
      ],
      familyMembers: const [],
      savedContacts: [
        _savedContact(
          id: "contact-1",
          userID: 5,
          email: "new@example.com",
          name: "Same",
        ),
      ],
    );

    expect(users.single.email, "new@example.com");
  });
}

contacts.ContactRecord _savedContact({
  required String id,
  required int userID,
  required String? email,
  String name = "Saved",
}) {
  return contacts.ContactRecord(
    id: id,
    contactUserId: userID,
    email: email,
    name: name,
    profilePictureAttachmentId: null,
    isDeleted: false,
    createdAt: 1,
    updatedAt: 1,
  );
}

Collection _collection({required User owner, required List<User> sharees}) {
  return Collection(
    1,
    owner,
    "",
    null,
    "Album",
    null,
    null,
    CollectionType.album,
    CollectionAttributes(),
    sharees,
    const [],
    0,
  );
}

FamilyMember _familyMember(
  String email,
  FamilyMemberStatus status, {
  int? userID,
}) {
  return FamilyMember(email, 0, "family-id", userID, false, status, null);
}
