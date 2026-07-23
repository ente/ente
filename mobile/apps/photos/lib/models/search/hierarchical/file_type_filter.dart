import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";

extension FileTypeExtension on FileType {
  SearchFilterIcon get icon {
    switch (this) {
      case FileType.image:
        return HugeIcons.strokeRoundedImage01;
      case FileType.video:
        return HugeIcons.strokeRoundedVideo02;
      case FileType.livePhoto:
        return HugeIcons.strokeRoundedAlbum02;
      default:
        return HugeIcons.strokeRoundedFile01;
    }
  }
}

class FileTypeFilter extends HierarchicalSearchFilter {
  final FileType fileType;
  final String typeName;
  final int occurrence;

  FileTypeFilter({
    required this.fileType,
    required this.typeName,
    required this.occurrence,
    super.filterTypeName = "fileTypeFilter",
    super.matchedUploadedIDs,
  });

  @override
  String name() {
    return typeName;
  }

  @override
  SearchFilterIcon icon() {
    return fileType.icon;
  }

  @override
  int relevance() {
    return occurrence;
  }

  @override
  bool isMatch(EnteFile file) {
    return file.fileType == fileType;
  }

  @override
  bool isSameFilter(HierarchicalSearchFilter other) {
    if (other is FileTypeFilter) {
      return other.fileType == fileType;
    }
    return false;
  }
}
