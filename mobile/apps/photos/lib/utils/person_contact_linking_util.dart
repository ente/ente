import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/widgets.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/ui/viewer/people/people_page.dart";
import "package:photos/utils/dialog_util.dart";

Future<bool> checkIfEmailAlreadyAssignedToAPerson(String email) async {
  final persons = await PersonService.instance.getPersons();
  for (var person in persons) {
    if (person.data.email == email) {
      return true;
    }
  }
  return false;
}

Future<void> showAlreadyLinkedEmailDialog(
  BuildContext context,
  String email,
) async {
  final persons = await PersonService.instance.getPersons();
  final PersonEntity? person = persons.firstWhereOrNull(
    (person) => person.data.email == email,
  );
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
