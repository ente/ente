import 'package:ente_contacts/contacts.dart';
import "package:ente_sharing/models/user.dart";

typedef ResolvedUserIdentity = ({String displayName, String email});

extension UserExtension on User {
  String get resolvedDisplayName => resolveUserIdentity(id, email).displayName;

  bool matchesResolvedNameOrEmail(String query) =>
      _matchesResolvedNameOrEmail(id, email, query);
}

extension UserSuggestionExtension on UserSuggestion {
  String get resolvedDisplayName =>
      resolveUserIdentity(userID, email).displayName;

  bool matchesResolvedNameOrEmail(String query) =>
      _matchesResolvedNameOrEmail(userID, email, query);
}

ResolvedUserIdentity resolveUserIdentity(int? userID, String email) {
  final contact = ContactsDisplayService.instance.getCachedContact(
    contactUserId: userID,
    email: email,
  );
  final resolvedEmail = _trimToNull(contact?.email) ?? email;
  return (
    displayName: _trimToNull(contact?.name) ?? resolvedEmail,
    email: resolvedEmail,
  );
}

bool _matchesResolvedNameOrEmail(int? userID, String email, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;
  final identity = resolveUserIdentity(userID, email);
  return identity.displayName.toLowerCase().contains(normalizedQuery) ||
      identity.email.toLowerCase().contains(normalizedQuery) ||
      email.toLowerCase().contains(normalizedQuery);
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
