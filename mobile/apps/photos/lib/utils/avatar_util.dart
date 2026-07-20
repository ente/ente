import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

enum AvatarIdentityRole {
  standard,

  /// Kept black across themes to preserve the established "me" treatment.
  currentUser,

  /// A non-user uploading through a public Collect link.
  publicUploader,
}

class AvatarIdentity {
  AvatarIdentity._({
    required this.label,
    required this.key,
    required this.role,
  });

  factory AvatarIdentity.account({
    required String label,
    required String? email,
    required int? userID,
    required String? currentUserEmail,
    String? personID,
  }) {
    final normalizedEmail = normalizeAvatarEmail(email);
    final role =
        normalizedEmail != null &&
            normalizedEmail == normalizeAvatarEmail(currentUserEmail)
        ? AvatarIdentityRole.currentUser
        : AvatarIdentityRole.standard;
    return AvatarIdentity._(
      label: label,
      key: avatarIdentityKey(
        email: normalizedEmail,
        userID: userID,
        personID: personID,
        anonymousID: _anonymousIDFromPlaceholderEmail(email),
        name: label,
      ),
      role: role,
    );
  }

  factory AvatarIdentity.publicUploader({required String label}) {
    return AvatarIdentity._(
      label: label,
      key: avatarIdentityKey(name: label),
      role: AvatarIdentityRole.publicUploader,
    );
  }

  final String label;
  final String key;
  final AvatarIdentityRole role;

  String get initial {
    final trimmed = label.trim();
    return trimmed.isEmpty ? " " : trimmed.characters.first.toUpperCase();
  }
}

String avatarIdentityKey({
  String? email,
  int? userID,
  String? personID,
  String? anonymousID,
  String? name,
}) {
  final normalizedEmail = normalizeAvatarEmail(email);
  if (normalizedEmail != null) {
    return "email:$normalizedEmail";
  }
  if (userID != null && userID > 0) {
    return "user:$userID";
  }
  final normalizedPersonID = personID?.trim();
  if (normalizedPersonID != null && normalizedPersonID.isNotEmpty) {
    return "person:$normalizedPersonID";
  }
  final normalizedAnonymousID = anonymousID?.trim().toLowerCase();
  if (normalizedAnonymousID != null && normalizedAnonymousID.isNotEmpty) {
    return "anonymous:$normalizedAnonymousID";
  }
  final normalizedName = name?.trim().toLowerCase().replaceAll(
    RegExp(r"\s+"),
    " ",
  );
  if (normalizedName != null && normalizedName.isNotEmpty) {
    return "name:$normalizedName";
  }
  return "unknown";
}

String? normalizeAvatarEmail(String? email) {
  final normalized = email?.trim().toLowerCase();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized.endsWith("@unknown.com")) {
    return null;
  }
  return normalized;
}

String? _anonymousIDFromPlaceholderEmail(String? email) {
  const suffix = "@unknown.com";
  final normalized = email?.trim().toLowerCase();
  if (normalized == null || !normalized.endsWith(suffix)) return null;
  final anonymousID = normalized.substring(
    0,
    normalized.length - suffix.length,
  );
  return anonymousID.isEmpty ? null : anonymousID;
}

Color avatarBackgroundColor(BuildContext context, AvatarIdentity identity) {
  return avatarComponentColorValue(
    context,
    avatarComponentColorForAvatarIdentity(identity),
  );
}

AvatarComponentColor avatarComponentColorForAvatarIdentity(
  AvatarIdentity identity,
) {
  return identity.role == AvatarIdentityRole.standard
      ? avatarComponentColorForIdentity(identity.key)
      : AvatarComponentColor.black;
}
