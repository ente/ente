import "dart:convert";

import "package:photos/models/file/file.dart";
import "package:photos/services/search_service.dart";

class SimilarFiles {
  final List<EnteFile> files;
  final Set<int> fileIds;
  double furthestDistance;

  SimilarFiles(this.files, this.furthestDistance)
    : fileIds = files.map((file) => file.uploadedFileID!).toSet();

  int get totalSize => files.fold(0, (sum, file) => sum + (file.fileSize ?? 0));

  bool get isEmpty => files.isEmpty;

  int get length => files.length;

  @override
  String toString() =>
      'SimilarFiles(files: $files, size: $totalSize, distance: $furthestDistance)';

  void removeFile(EnteFile file) {
    files.remove(file);
    fileIds.remove(file.uploadedFileID);
  }

  void addFile(EnteFile file) {
    files.add(file);
    fileIds.add(file.uploadedFileID!);
  }

  bool containsFile(EnteFile file) {
    return fileIds.contains(file.uploadedFileID);
  }

  Map<String, dynamic> toJson() {
    return {'fileIDs': fileIds.toList(), 'distance': furthestDistance};
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  factory SimilarFiles.fromJson(
    Map<String, dynamic> json,
    Map<int, EnteFile> fileMap,
  ) {
    final fileIds = List<int>.from(json['fileIDs']);
    final furthestDistance = (json['distance'] as num).toDouble();

    final files = <EnteFile>[];
    for (final fileId in fileIds) {
      final file = fileMap[fileId];
      if (file == null) continue;
      files.add(file);
    }

    return SimilarFiles(files, furthestDistance);
  }

  static SimilarFiles fromJsonString(
    String jsonString,
    Map<int, EnteFile> fileMap,
  ) {
    return SimilarFiles.fromJson(jsonDecode(jsonString), fileMap);
  }
}

class SimilarFilesCache {
  final List<String> similarFilesJsonStringList;
  final Set<int> allCheckedFileIDs;
  final double distanceThreshold;
  final bool exact;

  List<SimilarFiles>? _similarFilesList;

  /// Milliseconds since epoch
  final int cachedTime;

  SimilarFilesCache({
    required this.similarFilesJsonStringList,
    required this.allCheckedFileIDs,
    required this.distanceThreshold,
    required this.exact,
    required this.cachedTime,
  });

  Future<List<SimilarFiles>> similarFilesList() async {
    final allFiles = await SearchService.instance.getAllFilesForSearch();
    final fileMap = <int, EnteFile>{};
    for (final file in allFiles) {
      if (file.uploadedFileID == null) continue;
      fileMap[file.uploadedFileID!] = file;
    }
    _similarFilesList ??= similarFilesJsonStringList.map((jsonString) {
      return SimilarFiles.fromJson(jsonDecode(jsonString), fileMap);
    }).toList();
    return _similarFilesList!;
  }

  Future<Set<int>> getGroupedFileIDs() async {
    final similarFiles = await similarFilesList();
    final groupedFileIDs = <int>{};
    for (final files in similarFiles) {
      groupedFileIDs.addAll(files.fileIds);
    }
    return groupedFileIDs;
  }

  factory SimilarFilesCache.fromJson(Map<String, dynamic> json) {
    return SimilarFilesCache(
      similarFilesJsonStringList: List<String>.from(
        json['similarFilesJsonStringList'],
      ),
      allCheckedFileIDs: Set<int>.from(json['allCheckedFileIDs']),
      distanceThreshold: (json['distanceThreshold'] as num).toDouble(),
      exact: json['exact'] as bool,
      cachedTime: json['cachedTime'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'similarFilesJsonStringList': similarFilesJsonStringList,
      'allCheckedFileIDs': allCheckedFileIDs.toList(),
      'distanceThreshold': distanceThreshold,
      'exact': exact,
      'cachedTime': cachedTime,
    };
  }

  static String encodeToJsonString(SimilarFilesCache cache) {
    return jsonEncode(cache.toJson());
  }

  static SimilarFilesCache decodeFromJsonString(String jsonString) {
    return SimilarFilesCache.fromJson(jsonDecode(jsonString));
  }
}
