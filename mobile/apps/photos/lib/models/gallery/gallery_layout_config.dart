import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";

// FlagService treats debug builds as internal while still honoring the
// developer setting that disables internal-user features.
bool get isJustifiedLayoutAvailable => flagService.internalUser;

GalleryLayoutType resolveGalleryLayoutType(
  GalleryLayoutType preferredLayoutType, {
  bool? justifiedLayoutAvailable,
}) {
  final isAvailable = justifiedLayoutAvailable ?? isJustifiedLayoutAvailable;
  if (preferredLayoutType == GalleryLayoutType.justified && !isAvailable) {
    return GalleryLayoutType.grid;
  }
  return preferredLayoutType;
}
