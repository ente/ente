String? trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? normalizeContactLinkEmail(String? email) {
  return trimToNull(email)?.toLowerCase();
}

String? knownContactEmailOrNull(String? email) {
  final trimmed = trimToNull(email);
  if (trimmed == null || trimmed.toLowerCase().endsWith("@unknown.com")) {
    return null;
  }
  return trimmed;
}
