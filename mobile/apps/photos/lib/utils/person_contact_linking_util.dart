import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/widgets.dart";
import "package:photos/core/configuration.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/ui/viewer/people/people_page.dart";
import "package:photos/utils/contact_string_util.dart";
import "package:photos/utils/dialog_util.dart";

bool contactLinkEmailMatches(String? first, String? second) {
  final normalizedFirst = normalizeContactLinkEmail(first);
  final normalizedSecond = normalizeContactLinkEmail(second);
  return normalizedFirst != null && normalizedFirst == normalizedSecond;
}

bool isCurrentUserContactLinkEmail(String? email) {
  return contactLinkEmailMatches(email, Configuration.instance.getEmail());
}

int? currentUserIDForContactLinkEmail(String? email) {
  return isCurrentUserContactLinkEmail(email)
      ? Configuration.instance.getUserID()
      : null;
}

bool isCurrentUserContactLink({String? email, int? userID}) {
  final currentUserID = Configuration.instance.getUserID();
  return (currentUserID != null && userID == currentUserID) ||
      isCurrentUserContactLinkEmail(email);
}

Future<PersonEntity?> findPersonLinkedToContact({
  required int contactUserId,
  required String? email,
}) async {
  final persons = await PersonService.instance.getPersons();
  final PersonEntity? userIdMatch = persons.firstWhereOrNull(
    (person) => person.data.userID == contactUserId,
  );
  if (userIdMatch != null) {
    return userIdMatch;
  }

  final normalizedEmail = normalizeContactLinkEmail(email);
  if (normalizedEmail == null) {
    return null;
  }
  return persons.firstWhereOrNull(
    (person) => contactLinkEmailMatches(person.data.email, normalizedEmail),
  );
}

Future<PersonEntity?> findPersonLinkedToEmail(
  String? email, {
  String? excludedPersonId,
}) async {
  final normalizedEmail = normalizeContactLinkEmail(email);
  if (normalizedEmail == null) {
    return null;
  }
  final persons = await PersonService.instance.getPersons();
  bool includePerson(PersonEntity person) =>
      person.remoteID != excludedPersonId;
  if (isCurrentUserContactLinkEmail(normalizedEmail)) {
    final currentUserMatch = persons.firstWhereOrNull(
      (person) =>
          includePerson(person) &&
          isCurrentUserContactLink(
            email: person.data.email,
            userID: person.data.userID,
          ),
    );
    if (currentUserMatch != null) {
      return currentUserMatch;
    }
  }
  return persons.firstWhereOrNull(
    (person) =>
        includePerson(person) &&
        contactLinkEmailMatches(person.data.email, normalizedEmail),
  );
}

bool isLinkedToDifferentContact(
  PersonEntity person, {
  required int contactUserId,
  required String? email,
}) {
  final linkedUserId = person.data.userID;
  if (linkedUserId != null && linkedUserId != contactUserId) {
    return true;
  }
  if (linkedUserId == contactUserId) {
    return false;
  }

  final linkedEmail = normalizeContactLinkEmail(person.data.email);
  return linkedEmail != null && linkedEmail != normalizeContactLinkEmail(email);
}

Future<void> showAlreadyLinkedEmailDialog(
  BuildContext context,
  String email, {
  PersonEntity? linkedPerson,
}) async {
  final person = linkedPerson ?? await findPersonLinkedToEmail(email);
  if (person == null) {
    return;
  }

  if (!context.mounted) return;
  await showChoiceActionSheet(
    context,
    title: context.l10n.error,
    body: context.l10n.editEmailAlreadyLinked(name: person.data.name),
    firstButtonLabel: context.l10n.viewPersonToUnlink(name: person.data.name),
    firstButtonOnTap: () async {
      await routeToPage(
        context,
        PeoplePage(person: person, searchResult: null),
      );
    },
    isCritical: false,
  );
}
