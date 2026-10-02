enum FileSortOrder {
  newestFirst,
  oldestFirst,
  filenameAscending,
  filenameDescending;

  bool get ascending => this == oldestFirst || this == filenameAscending;

  bool get isFilename =>
      this == filenameAscending || this == filenameDescending;

  Map<String, dynamic> get metadata => {
    "asc": ascending,
    "sortBy": isFilename ? "fileName" : null,
  };

  static FileSortOrder fromMetadata({bool? asc, String? sortBy}) {
    if (sortBy == "fileName") {
      return asc == true ? filenameAscending : filenameDescending;
    }
    return asc == true ? oldestFirst : newestFirst;
  }
}
