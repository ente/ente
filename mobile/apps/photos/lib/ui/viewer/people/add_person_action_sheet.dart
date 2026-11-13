import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/people/save_or_edit_person.dart";

Future<dynamic> showAssignPersonAction(
  BuildContext context, {
  required String clusterID,
  EnteFile? file,
  bool showOptionToAddNewPerson = true,
}) async {
  return routeToPage(context, SaveOrEditPerson(clusterID, file: file));
}
