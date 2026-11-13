enum EntityType {
  location,
  person,
  cgroup,
  unknown,
  smartAlbum,
  memory,
  libraryShare;

  bool get isZipped {
    switch (this) {
      case EntityType.location:
      case EntityType.person:
        return false;
      default:
        return true;
    }
  }

  String get name {
    switch (this) {
      case EntityType.location:
        return "location";
      case EntityType.person:
        return "person";
      case EntityType.cgroup:
        return "cgroup";
      case EntityType.smartAlbum:
        return "smart_album";
      case EntityType.memory:
        return "memory";
      case EntityType.libraryShare:
        return "library_share";
      case EntityType.unknown:
        return "unknown";
    }
  }
}

EntityType entityTypeFromString(String type) {
  return EntityType.values.firstWhere(
    (e) => e.name == type,
    orElse: () => EntityType.unknown,
  );
}
