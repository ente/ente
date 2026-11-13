import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";

bool isRitualAlbumHidden(Ritual ritual) {
  final albumId = ritual.albumId;
  return isHiddenCollectionId(albumId);
}

Ritual? findRitualById(String ritualId) {
  if (ritualId.isEmpty) return null;
  for (final ritual in ritualsService.stateNotifier.value.rituals) {
    if (ritual.id == ritualId) return ritual;
  }
  return null;
}

bool isHiddenCollectionId(int? collectionId) {
  if (collectionId == null || collectionId <= 0) {
    return false;
  }
  final collection = CollectionsService.instance.getCollectionByID(
    collectionId,
  );
  return collection?.isHidden() ?? false;
}

Future<bool> requestHiddenRitualAccess(
  BuildContext context,
  Ritual ritual,
) async {
  if (!isRitualAlbumHidden(ritual)) {
    return true;
  }
  return LocalAuthenticationService.instance.requestLocalAuthentication(
    context,
    context.strings.authToViewYourHiddenFiles,
  );
}

Future<bool> requestHiddenRitualAccessForAlbumId(
  BuildContext context,
  int? albumId,
) async {
  if (!isHiddenCollectionId(albumId)) {
    return true;
  }
  return LocalAuthenticationService.instance.requestLocalAuthentication(
    context,
    context.strings.authToViewYourHiddenFiles,
  );
}
