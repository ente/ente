import "package:photos/extensions/user_extension.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/utils/contact_string_util.dart";

typedef ResolvedUserIdentity = ({
  String displayName,
  bool isResolved,
  String? knownEmail,
});

// Precedence: saved contact name → linked person name or local label → known
// email → "Someone".
ResolvedUserIdentity resolveSuggestionIdentity(UserSuggestion suggestion) {
  final contact = PhotosContactsService.instance.getCachedContact(
    contactUserId: suggestion.userID,
    email: suggestion.email,
  );
  final knownEmail =
      knownContactEmailOrNull(contact?.email) ??
      knownContactEmailOrNull(suggestion.email);
  final resolvedDisplayName =
      trimToNull(contact?.name) ??
      trimToNull(suggestion.displayName) ??
      knownEmail;
  return (
    displayName: resolvedDisplayName ?? "Someone",
    isResolved: resolvedDisplayName != null,
    knownEmail: knownEmail,
  );
}

String resolveSuggestionDisplayName(UserSuggestion suggestion) =>
    resolveSuggestionIdentity(suggestion).displayName;

String resolveDisplayName(User user) =>
    resolveSuggestionDisplayName(UserSuggestion.fromUser(user));

String? resolveKnownSuggestionEmail(UserSuggestion suggestion) =>
    resolveSuggestionIdentity(suggestion).knownEmail;

String? resolveKnownEmail(User user) =>
    resolveKnownSuggestionEmail(UserSuggestion.fromUser(user));

bool matchesResolvedSuggestionQuery(
  UserSuggestion suggestion,
  String lowerCaseQuery,
) {
  if (lowerCaseQuery.isEmpty) {
    return true;
  }
  final identity = resolveSuggestionIdentity(suggestion);
  return identity.displayName.toLowerCase().contains(lowerCaseQuery) ||
      (identity.knownEmail ?? suggestion.email).toLowerCase().contains(
        lowerCaseQuery,
      );
}

bool matchesResolvedContactQuery(User user, String lowerCaseQuery) =>
    matchesResolvedSuggestionQuery(
      UserSuggestion.fromUser(user),
      lowerCaseQuery,
    );
