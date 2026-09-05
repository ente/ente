import 'package:photos/models/file/file.dart';
import 'package:photos/models/upload_strategy.dart';

class DeviceCollection {
  final String id;
  final String name;
  final int count;
  final bool shouldBackup;
  final int modifiedAt;
  UploadStrategy uploadStrategy;
  final String? coverId;
  int? collectionID;
  EnteFile? thumbnail;

  bool hasCollectionID() {
    return collectionID != null && collectionID! != -1;
  }

  DeviceCollection(
    this.id,
    this.name, {
    this.coverId,
    this.count = 0,
    this.collectionID,
    this.modifiedAt = 0,
    this.thumbnail,
    this.uploadStrategy = UploadStrategy.ifMissing,
    this.shouldBackup = false,
  });

  DeviceCollection copyWith({bool? shouldBackup}) => DeviceCollection(
    id,
    name,
    coverId: coverId,
    count: count,
    collectionID: collectionID,
    modifiedAt: modifiedAt,
    thumbnail: thumbnail,
    uploadStrategy: uploadStrategy,
    shouldBackup: shouldBackup ?? this.shouldBackup,
  );
}
