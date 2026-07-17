import "package:photos/extensions/user_extension.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/utils/contact_string_util.dart";

String resolveDisplayName(User user) {
  final savedName = _savedContactName(user);
  if (savedName != null) {
    return savedName;
  }

  final personName = user.displayName?.trim();
  if (personName != null && personName.isNotEmpty) {
    return personName;
  }

  return resolveKnownEmail(user) ?? "Someone";
}

String? resolveKnownEmail(User user) {
  final contactUserId = _validContactUserId(user);
  final savedEmail = knownContactEmailOrNull(
    PhotosContactsService.instance.getCachedResolvedEmail(
      contactUserId: contactUserId,
      email: contactUserId == null ? user.email : null,
    ),
  );
  if (savedEmail != null) {
    return savedEmail;
  }

  return knownContactEmailOrNull(user.email);
}

bool matchesResolvedContactQuery(User user, String lowerCaseQuery) {
  if (lowerCaseQuery.isEmpty) {
    return true;
  }

  final resolvedName = resolveDisplayName(user).toLowerCase();
  final resolvedEmail = (resolveKnownEmail(user) ?? user.email).toLowerCase();
  return resolvedName.contains(lowerCaseQuery) ||
      resolvedEmail.contains(lowerCaseQuery);
}

String? _savedContactName(User user) {
  final contactUserId = _validContactUserId(user);
  return PhotosContactsService.instance.getCachedSavedName(
    contactUserId: contactUserId,
    email: contactUserId == null ? user.email : null,
  );
}

int? _validContactUserId(User user) {
  final userId = user.id;
  return userId != null && userId > 0 ? userId : null;
}
