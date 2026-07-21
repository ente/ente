import 'package:photos/utils/pending_translation.dart';

abstract final class LibrarySharingStrings {
  static String get sharingWith => pendingTranslation('Sharing with');
  static String get shareWith => pendingTranslation('Share with');

  static String get shareAlbums => pendingTranslation('Share albums');
  static String get internalShareAlbums =>
      pendingTranslation('(i) Share albums');
  static String get librarySharing => pendingTranslation('Library Sharing');
  static String get shareAllYourAlbums =>
      pendingTranslation('Share all your albums');
  static String get enableLibrarySharing =>
      pendingTranslation('Enable library sharing?');
  static String enableLibrarySharingMessage(
    String recipient,
  ) => pendingTranslation(
    'Your existing albums, and the ones you create in the future will be automatically shared with $recipient.',
  );
  static String get hiddenAlbumsNotShared => pendingTranslation(
    'Hidden albums will not be shared. You can stop sharing any album at any time.',
  );
  static String get enable => pendingTranslation('Enable');
  static String get comingSoon => pendingTranslation('Coming soon');

  static String sharedAlbumCount(int count) => switch (count) {
    0 => pendingTranslation('No albums shared'),
    1 => pendingTranslation('1 album shared'),
    _ => pendingTranslation('$count albums shared'),
  };

  static String memberSubtitle(int count, String storageUsage) =>
      pendingTranslation('${sharedAlbumCount(count)} \u2022 $storageUsage');

  static String selectedAlbumCount(int count) => switch (count) {
    1 => pendingTranslation('1 selected'),
    _ => pendingTranslation('$count selected'),
  };

  static String shareAlbumCount(int count) => switch (count) {
    1 => pendingTranslation('Share 1 album'),
    _ => pendingTranslation('Share $count albums'),
  };

  static String stopSharingTitle(int count) => switch (count) {
    1 => pendingTranslation('Stop sharing 1 album?'),
    _ => pendingTranslation('Stop sharing $count albums?'),
  };

  static String stopSharingMessage(int count) => switch (count) {
    1 => pendingTranslation(
      "They'll lose this album, and any photos they added leave with them. You can share again later.",
    ),
    _ => pendingTranslation(
      "They'll lose these albums, and any photos they added leave with them. You can share again later.",
    ),
  };

  static String failedAlbumCount(int count) => switch (count) {
    1 => pendingTranslation('Could not update 1 album.'),
    _ => pendingTranslation('Could not update $count albums.'),
  };

  static String get role => pendingTranslation('Role');
  static String get mixed => pendingTranslation('Mixed');
  static String get roles => pendingTranslation('Roles');
  static String get updateRoles => pendingTranslation('Update roles');
  static String get stopSharing => pendingTranslation('Stop sharing');
  static String get retryFailed => pendingTranslation('Retry failed albums');
  static String get retryLoading => pendingTranslation('Try again');
  static String get noAlbumsToShare =>
      pendingTranslation('No albums to share yet');
  static String get sharingFullLibrary =>
      pendingTranslation('You are sharing your full library!');
  static String get sharingFailed => pendingTranslation('Sharing failed');
  static String get sharingFailedMessage =>
      pendingTranslation('Could not update the selected albums.');
  static String get loadFailed => pendingTranslation('Could not load albums');
}
