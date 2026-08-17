import "package:locker/services/collections/models/collection.dart";

extension CollectionDisplayExtension on Collection {
  String? get displayName {
    if (type == CollectionType.favorites) {
      return "Important";
    }
    return name;
  }
}
