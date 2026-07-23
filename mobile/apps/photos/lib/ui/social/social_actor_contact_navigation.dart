import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/search/result/contact_result_page.dart";
import "package:photos/ui/viewer/search/result/edit_contact_page.dart";

final _logger = Logger("SocialActorContactNavigation");

bool canOpenSocialActorContactDestination(
  User user, {
  required int currentUserID,
}) {
  final userId = user.id;
  if (userId == null || userId <= 0 || userId == currentUserID) {
    return false;
  }
  return resolveKnownEmail(user) != null;
}

Future<void> openSocialActorContactDestination(
  BuildContext context,
  User user, {
  required int currentUserID,
  BuildContext? navigationContext,
  bool dismissCurrentRoute = false,
}) async {
  if (!canOpenSocialActorContactDestination(
    user,
    currentUserID: currentUserID,
  )) {
    return;
  }

  final userId = user.id!;
  final email = resolveKnownEmail(user);
  if (email == null) {
    return;
  }

  final destination = await _buildDestination(
    user,
    userId: userId,
    email: email,
  );
  if (destination == null) {
    return;
  }

  final targetContext = navigationContext ?? context;
  if (dismissCurrentRoute && context.mounted) {
    Navigator.of(context).pop();
  }
  if (!targetContext.mounted) {
    return;
  }
  await routeToPage(targetContext, destination);
}

Future<Widget?> _buildDestination(
  User user, {
  required int userId,
  required String email,
}) async {
  final contactsService = PhotosContactsService.instance;
  final cachedContact = contactsService.getCachedContact(contactUserId: userId);
  if (cachedContact != null) {
    return _contactResultPageForUser(user);
  }

  if (contactsService.needsWarmup) {
    try {
      await contactsService.ensureReady();
    } catch (e, s) {
      _logger.warning(
        "Failed to initialize contacts before opening social actor destination",
        e,
        s,
      );
    }
  }

  final savedContact = contactsService.getCachedContact(contactUserId: userId);
  if (savedContact != null) {
    return _contactResultPageForUser(user);
  }

  return EditContactPage(
    contactUserId: userId,
    email: email,
    existingContact: null,
  );
}

Future<Widget?> _contactResultPageForUser(User user) async {
  final GenericSearchResult? searchResult = await SearchService.instance
      .buildContactSearchResultForUser(user);
  if (searchResult == null) {
    return null;
  }
  return ContactResultPage(searchResult);
}
