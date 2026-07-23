import 'dart:convert';

import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_network/network.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/files/sync/models/file_magic.dart';
import 'package:logging/logging.dart';

class MetadataUpdaterService {
  MetadataUpdaterService._privateConstructor();

  static final MetadataUpdaterService instance =
      MetadataUpdaterService._privateConstructor();

  Future<void> init() async {}

  final _logger = Logger("MetadataUpdaterService");
  final _enteDio = Network.instance.enteDio;

  Future<bool> editFileCaption(EnteFile file, String caption) async {
    try {
      await _updatePublicMetadata([file], captionKey, caption);
      await CollectionService.instance.sync();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> editFileName(EnteFile file, String name) async {
    try {
      final Map<String, dynamic> updates = {editNameKey: name};
      await _updatePublicMetadataBulk([file], updates);
      await CollectionService.instance.sync();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateFileMetadata(
    EnteFile file,
    Map<String, dynamic> metadata,
  ) async {
    try {
      await _updatePublicMetadataBulk([file], metadata);
      await CollectionService.instance.sync();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _updatePublicMetadata(
    List<EnteFile> files,
    String key,
    dynamic value,
  ) async {
    if (files.isEmpty) {
      return;
    }
    try {
      final Map<String, dynamic> update = {key: value};
      await _updatePublicMagicMetadata(files, update);
    } catch (e, s) {
      _logger.severe(
        "Failed to update public metadata for files: $files",
        e,
        s,
      );
      rethrow;
    }
  }

  Future<void> _updatePublicMetadataBulk(
    List<EnteFile> files,
    Map<String, dynamic> updates,
  ) async {
    if (files.isEmpty) {
      return;
    }
    try {
      await _updatePublicMagicMetadata(files, updates);
    } catch (e, s) {
      _logger.severe(
        "Failed to update public metadata for files: $files",
        e,
        s,
      );
      rethrow;
    }
  }

  Future<void> _updatePublicMagicMetadata(
    List<EnteFile> files,
    Map<String, dynamic>? newMetadataUpdate, {
    Map<int, Map<String, dynamic>>? metadataUpdateMap,
  }) async {
    final params = <String, dynamic>{};
    params['metadataList'] = [];
    final int ownerID = Configuration.instance.getUserID()!;
    try {
      for (final file in files) {
        if (file.uploadedFileID == null) {
          throw AssertionError(
            "operation is only supported on backed up files",
          );
        } else if (file.ownerID != ownerID) {
          throw AssertionError("cannot modify memories not owned by you");
        }
        // read the existing magic metadata and apply new updates to existing data
        // current update is simple replace. This will be enhanced in the future,
        // as required.
        final newUpdates = metadataUpdateMap != null
            ? metadataUpdateMap[file.uploadedFileID]
            : newMetadataUpdate;
        assert(
          newUpdates != null && newUpdates.isNotEmpty,
          "can not apply empty updates",
        );
        final Map<String, dynamic> jsonToUpdate = jsonDecode(
          file.pubMmdEncodedJson ?? '{}',
        );
        newUpdates!.forEach((key, value) {
          jsonToUpdate[key] = value;
        });

        // update the local information so that it's reflected on UI
        file.pubMmdEncodedJson = jsonEncode(jsonToUpdate);
        file.pubMagicMetadata = PubMagicMetadata.fromJson(jsonToUpdate);

        final fileKey = await CollectionService.instance.getFileKey(file);

        final encryptedMMd = await CryptoUtil.encryptData(
          utf8.encode(jsonEncode(jsonToUpdate)),
          fileKey,
        );

        params['metadataList'].add(
          UpdateMagicMetadataRequest(
            id: file.uploadedFileID!,
            magicMetadata: MetadataRequest(
              version: file.pubMmdVersion,
              count: jsonToUpdate.length,
              data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
              header: CryptoUtil.bin2base64(encryptedMMd.header!),
            ),
          ),
        );
        file.pubMmdVersion = file.pubMmdVersion + 1;
      }

      await _enteDio.put("/files/public-magic-metadata", data: params);
    } catch (e, s) {
      _logger.severe("Failed to update public metadata: $e", e, s);
      rethrow;
    }
  }
}

class UpdateMagicMetadataRequest {
  final int id;
  final MetadataRequest? magicMetadata;

  UpdateMagicMetadataRequest({required this.id, required this.magicMetadata});

  factory UpdateMagicMetadataRequest.fromJson(dynamic json) {
    return UpdateMagicMetadataRequest(
      id: json['id'],
      magicMetadata: json['magicMetadata'] != null
          ? MetadataRequest.fromJson(json['magicMetadata'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['id'] = id;
    if (magicMetadata != null) {
      map['magicMetadata'] = magicMetadata!.toJson();
    }
    return map;
  }
}

class MetadataRequest {
  int? version;
  int? count;
  String? data;
  String? header;

  MetadataRequest({
    required this.version,
    required this.count,
    required this.data,
    required this.header,
  });

  MetadataRequest.fromJson(dynamic json) {
    version = json['version'];
    count = json['count'];
    data = json['data'];
    header = json['header'];
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['version'] = version;
    map['count'] = count;
    map['data'] = data;
    map['header'] = header;
    return map;
  }
}
