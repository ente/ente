import "package:flutter/material.dart";

/// Standard Locker illustrations shown at the top of bottom sheets.
class LockerBottomSheetIllustration extends StatelessWidget {
  const LockerBottomSheetIllustration._(this.assetPath);

  static const warningGrey = LockerBottomSheetIllustration._(
    "assets/warning-grey.png",
  );
  static const warningBlue = LockerBottomSheetIllustration._(
    "assets/warning-blue.png",
  );
  static const warningRed = LockerBottomSheetIllustration._(
    "assets/warning-red.png",
  );
  static const fileDelete = LockerBottomSheetIllustration._(
    "assets/file_delete_icon.png",
  );
  static const collectionDelete = LockerBottomSheetIllustration._(
    "assets/collection_delete_icon.png",
  );

  final String assetPath;

  @override
  Widget build(BuildContext context) => Image.asset(assetPath);
}
