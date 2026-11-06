import 'package:photos/models/api/collection/user.dart';

class CollectionInvitation {
  const CollectionInvitation({
    required this.collectionID,
    required this.inviter,
    required this.albumName,
    required this.sharedAt,
  });

  final int collectionID;
  final User inviter;
  final String albumName;
  final int sharedAt;

  String get occurrenceKey => '$collectionID:$sharedAt';
}
