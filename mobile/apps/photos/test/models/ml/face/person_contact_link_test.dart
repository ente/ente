import "dart:convert";

import "package:ente_contacts/contacts.dart" as contacts;
import "package:flutter_test/flutter_test.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/gateways/entity/models/type.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/entity_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/utils/person_contact_linking_util.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  group("PersonData contact link", () {
    test("copyWith preserves link fields when omitted", () {
      final data = PersonData(
        name: "Alex",
        email: "alex@example.com",
        userID: 7,
      );

      final updated = data.copyWith(name: "Alex R");

      expect(updated.name, "Alex R");
      expect(updated.email, "alex@example.com");
      expect(updated.userID, 7);
    });

    test("copyWith clears email and userID", () {
      final data = PersonData(
        name: "Alex",
        email: "alex@example.com",
        userID: 7,
      );

      final updated = data.copyWith(email: null, userID: null);

      expect(updated.email, isNull);
      expect(updated.userID, isNull);
    });
  });

  group("PersonService contact link", () {
    late _FakeEntityService entityService;
    late _FakePhotosContactsService contactsService;
    late PersonService personService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      entityService = _FakeEntityService()
        ..seed(
          PersonEntity(
            "person-1",
            PersonData(name: "Alex", email: "old@example.com", userID: 3),
          ),
        );
      contactsService = _FakePhotosContactsService()
        ..seed(
          const contacts.ContactRecord(
            id: "contact-1",
            contactUserId: 3,
            email: "old@example.com",
            data: contacts.ContactData(contactUserId: 3, name: "Old Contact"),
            profilePictureAttachmentId: null,
            isDeleted: false,
            createdAt: 1,
            updatedAt: 2,
          ),
        );
      personService = _TestPersonService(
        entityService,
        _FakeMLDataDB(),
        await SharedPreferences.getInstance(),
        contactsService: contactsService,
      );
    });

    test("sets and clears contact link fields", () async {
      final linked = await personService.updateAttributes(
        "person-1",
        userID: 7,
        email: "alex@example.com",
        syncLinkedContactName: false,
      );

      expect(linked.data.userID, 7);
      expect(linked.data.email, "alex@example.com");

      final cleared = await personService.updateAttributes(
        "person-1",
        userID: null,
        email: null,
        syncLinkedContactName: false,
      );

      expect(cleared.data.userID, isNull);
      expect(cleared.data.email, isNull);

      final stored = await entityService.getEntity(
        EntityType.cgroup,
        "person-1",
      );
      final storedJson = jsonDecode(stored!.data) as Map<String, dynamic>;
      expect(storedJson["userID"], isNull);
      expect(storedJson["email"], isNull);
    });

    test("updateAttributes syncs changed name to linked contact", () async {
      final updated = await personService.updateAttributes(
        "person-1",
        name: "Alex R",
      );

      expect(updated.data.name, "Alex R");
      expect(updated.data.userID, 3);
      expect(updated.data.email, "old@example.com");
      expect(contactsService.createOrUpdateCalls, 1);
      expect(contactsService.lastUpdatedContactUserId, 3);
      expect(contactsService.lastUpdatedName, "Alex R");
    });

    test("updateAttributes does not sync unchanged person name", () async {
      final updated = await personService.updateAttributes(
        "person-1",
        name: "Alex",
      );

      expect(updated.data.name, "Alex");
      expect(contactsService.createOrUpdateCalls, 0);
      expect(contactsService.lastUpdatedName, isNull);
    });

    test("updateAttributes can skip linked contact name sync", () async {
      final updated = await personService.updateAttributes(
        "person-1",
        name: "Alex R",
        syncLinkedContactName: false,
      );

      expect(updated.data.name, "Alex R");
      expect(contactsService.createOrUpdateCalls, 0);
      expect(contactsService.lastUpdatedName, isNull);
    });
  });

  group("contact link conflict rules", () {
    test("prefers userID and allows the same contact", () {
      final person = PersonEntity(
        "person-1",
        PersonData(name: "Alex", userID: 7, email: "other@example.com"),
      );

      expect(
        isLinkedToDifferentContact(
          person,
          contactUserId: 7,
          email: "alex@example.com",
        ),
        isFalse,
      );
    });

    test("blocks a person linked to another userID", () {
      final person = PersonEntity(
        "person-1",
        PersonData(name: "Alex", userID: 8),
      );

      expect(
        isLinkedToDifferentContact(
          person,
          contactUserId: 7,
          email: "alex@example.com",
        ),
        isTrue,
      );
    });

    test("uses normalized email for legacy email-only links", () {
      final samePerson = PersonEntity(
        "person-1",
        PersonData(name: "Alex", email: "Alex@Example.com"),
      );
      final otherPerson = PersonEntity(
        "person-2",
        PersonData(name: "Sam", email: "sam@example.com"),
      );

      expect(
        isLinkedToDifferentContact(
          samePerson,
          contactUserId: 7,
          email: " alex@example.com ",
        ),
        isFalse,
      );
      expect(
        isLinkedToDifferentContact(
          otherPerson,
          contactUserId: 7,
          email: "alex@example.com",
        ),
        isTrue,
      );
    });
  });
}

class _TestPersonService extends PersonService {
  _TestPersonService(
    super.entityService,
    super.faceMLDataDB,
    super.prefs, {
    super.contactsService,
  });

  @override
  Future<void> refreshPersonCache({
    bool notifyListeners = false,
    String source = "",
  }) async {}
}

class _FakePhotosContactsService implements PhotosContactsService {
  contacts.ContactRecord? contact;
  int createOrUpdateCalls = 0;
  int? lastUpdatedContactUserId;
  String? lastUpdatedName;

  void seed(contacts.ContactRecord value) {
    contact = value;
  }

  @override
  Future<contacts.ContactRecord?> getContact({
    int? contactUserId,
    String? email,
  }) async {
    final saved = contact;
    if (saved == null || saved.isDeleted) {
      return null;
    }
    if (contactUserId != null) {
      return saved.contactUserId == contactUserId ? saved : null;
    }
    final normalizedEmail = email?.trim().toLowerCase();
    if (normalizedEmail == null || normalizedEmail.isEmpty) {
      return null;
    }
    return saved.email?.trim().toLowerCase() == normalizedEmail ? saved : null;
  }

  @override
  Future<contacts.ContactRecord> createOrUpdateContact({
    required int contactUserId,
    required String name,
  }) async {
    createOrUpdateCalls += 1;
    lastUpdatedContactUserId = contactUserId;
    lastUpdatedName = name.trim();
    final saved = contact;
    return contacts.ContactRecord(
      id: saved?.id ?? "contact-$contactUserId",
      contactUserId: contactUserId,
      email: saved?.email,
      data: contacts.ContactData(
        contactUserId: contactUserId,
        name: name.trim(),
      ),
      profilePictureAttachmentId: saved?.profilePictureAttachmentId,
      isDeleted: false,
      createdAt: saved?.createdAt ?? 1,
      updatedAt: (saved?.updatedAt ?? 1) + 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEntityService implements EntityService {
  final Map<String, LocalEntityData> _entities = {};
  int _updatedAt = 1;

  void seed(PersonEntity person) {
    _entities[person.remoteID] = LocalEntityData(
      id: person.remoteID,
      type: EntityType.cgroup,
      data: jsonEncode(person.data.toJson()),
      ownerID: 1,
      updatedAt: _updatedAt,
    );
  }

  @override
  Future<List<LocalEntityData>> getEntities(EntityType type) async {
    return _entities.values.where((entity) => entity.type == type).toList();
  }

  @override
  Future<LocalEntityData?> getEntity(EntityType type, String id) async {
    final entity = _entities[id];
    return entity?.type == type ? entity : null;
  }

  @override
  Future<LocalEntityData> addOrUpdate(
    EntityType type,
    Map<String, dynamic> jsonMap, {
    String? id,
    bool addWithCustomID = false,
  }) async {
    final entityID = id ?? "person-${_entities.length + 1}";
    final entity = LocalEntityData(
      id: entityID,
      type: type,
      data: jsonEncode(jsonMap),
      ownerID: 1,
      updatedAt: ++_updatedAt,
    );
    _entities[entityID] = entity;
    return entity;
  }

  @override
  int lastSyncTime(EntityType type) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMLDataDB implements MLDataDB {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
