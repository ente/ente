import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/db/memory_shares_db.dart';
import 'package:photos/db/ml/db.dart';
import 'package:photos/events/memory_share_updated_event.dart';
import 'package:photos/gateways/entity/models/type.dart';
import 'package:photos/models/api/memory_share/memory_share.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/memories/memory.dart';
import 'package:photos/models/memory_lane/memory_lane_models.dart';
import 'package:photos/models/metadata/file_magic.dart';
import 'package:photos/models/ml/face/face.dart';
import 'package:photos/service_locator.dart' show entityService;
import 'package:photos/utils/face_crop_util.dart';
import 'package:photos/utils/file_key.dart';

class MemoryShareService {
  MemoryShareService._();

  static final MemoryShareService instance = MemoryShareService._();

  final Logger _logger = Logger("MemoryShareService");

  static const int _shortFragmentSecretLength = 12;
  static const int _maxMemoryShareFiles = 100;
  static final RegExp _base62SecretPattern = RegExp(r'^[0-9A-Za-z]{12}$');

  static List<EnteFile> uniqueUploadedFiles(List<EnteFile> files) {
    final seenFileIDs = <int>{};
    final uniqueFiles = <EnteFile>[];
    for (final file in files) {
      final fileID = file.uploadedFileID;
      if (fileID == null || !seenFileIDs.add(fileID)) {
        continue;
      }
      uniqueFiles.add(file);
    }
    return uniqueFiles;
  }

  late final Dio _enteDio;
  late final MemorySharesDB _db;
  final Map<String, MemoryShare> _memoryShareByHashCache = {};

  Future<void> init() async {
    _enteDio = NetworkClient.instance.enteDio;
    _db = MemorySharesDB.instance;
    await _loadMemoryShareHashCache();
  }

  void clearCache() {
    _memoryShareByHashCache.clear();
  }

  Future<(String, int)> _createMemoryLink({
    required List<EnteFile> files,
    required String title,
    String? memoryHash,
  }) async {
    List<EnteFile> uploadedFiles = const [];
    try {
      uploadedFiles = uniqueUploadedFiles(files);

      if (uploadedFiles.isEmpty) {
        throw Exception("No uploaded files to share");
      }
      final resolvedMemoryHash = memoryHash ?? _getMemoryHash(uploadedFiles);

      final secretPayload = await _prepareShareSecret();
      final shareKey = secretPayload.shareKey;

      final metadata = jsonEncode({'name': title});
      final metadataBytes = utf8.encode(metadata);
      final encryptedMetadata = CryptoUtil.encryptSync(
        Uint8List.fromList(metadataBytes),
        shareKey,
      );

      final fileItems = <Map<String, dynamic>>[];
      for (var i = 0; i < uploadedFiles.length; i++) {
        final file = uploadedFiles[i];
        final fileKey = getFileKey(file);
        final reEncryptedKey = CryptoUtil.encryptSync(fileKey, shareKey);
        fileItems.add({
          'fileID': file.uploadedFileID,
          'position': i,
          'encryptedKey': CryptoUtil.bin2base64(reEncryptedKey.encryptedData!),
          'keyDecryptionNonce': CryptoUtil.bin2base64(reEncryptedKey.nonce!),
        });
      }
      final requestData = {
        'type': MemoryShareType.share.name,
        'metadataCipher': CryptoUtil.bin2base64(
          encryptedMetadata.encryptedData!,
        ),
        'metadataNonce': CryptoUtil.bin2base64(encryptedMetadata.nonce!),
        ...secretPayload.metadata(),
        'memoryHash': resolvedMemoryHash,
        'files': fileItems,
      };

      final response = await _enteDio.post('/memory-share', data: requestData);
      final memoryShare = MemoryShare.fromJson(response.data['memoryShare']);

      final shareUrl = "${memoryShare.url}#${secretPayload.secret}";
      final localShare = memoryShare.copyWith(
        url: shareUrl,
        memoryHash: resolvedMemoryHash,
        previewUploadedFileID: uploadedFiles.first.uploadedFileID,
        fileCount: uploadedFiles.length,
      );
      await _db.upsert(localShare);
      _updateMemoryShareCache(localShare);
      Bus.instance.fire(MemoryShareUpdatedEvent("create-memory-share"));

      return (shareUrl, memoryShare.id);
    } catch (e, s) {
      _logger.severe("Failed to create memory share", e, s);

      rethrow;
    }
  }

  Future<(String, int)> _createMemoryLaneLink({
    required List<_MemoryLaneShareItem> laneItems,
    required Map<String, dynamic> metadata,
    String? memoryHash,
  }) async {
    List<EnteFile> uploadedFiles = const [];
    try {
      uploadedFiles = uniqueUploadedFiles(
        laneItems.map((item) => item.file).toList(),
      );
      final resolvedMemoryHash = memoryHash ?? _getMemoryLaneHash(metadata);
      final secretPayload = await _prepareShareSecret();
      final shareKey = secretPayload.shareKey;
      final metadataBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(metadata)),
      );
      final compressedMetadataBytes = Uint8List.fromList(
        GZipCodec().encode(metadataBytes),
      );
      final encryptedMetadata = CryptoUtil.encryptSync(
        compressedMetadataBytes,
        shareKey,
      );

      final fileItems = <Map<String, dynamic>>[];
      for (var i = 0; i < uploadedFiles.length; i++) {
        final file = uploadedFiles[i];
        final fileKey = getFileKey(file);
        final reEncryptedKey = CryptoUtil.encryptSync(fileKey, shareKey);
        fileItems.add({
          'fileID': file.uploadedFileID,
          'position': i,
          'encryptedKey': CryptoUtil.bin2base64(reEncryptedKey.encryptedData!),
          'keyDecryptionNonce': CryptoUtil.bin2base64(reEncryptedKey.nonce!),
        });
      }
      final requestData = {
        'type': MemoryShareType.lane.name,
        'metadataCipher': CryptoUtil.bin2base64(
          encryptedMetadata.encryptedData!,
        ),
        'metadataNonce': CryptoUtil.bin2base64(encryptedMetadata.nonce!),
        ...secretPayload.metadata(),
        'memoryHash': resolvedMemoryHash,
        'files': fileItems,
      };

      final response = await _enteDio.post('/memory-share', data: requestData);
      final memoryShare = MemoryShare.fromJson(response.data['memoryShare']);

      final shareUrl = "${memoryShare.url}#${secretPayload.secret}";
      final localShare = memoryShare.copyWith(
        url: shareUrl,
        memoryHash: resolvedMemoryHash,
        previewUploadedFileID: uploadedFiles.first.uploadedFileID,
        fileCount: uploadedFiles.length,
      );
      await _db.upsert(localShare);
      _updateMemoryShareCache(localShare);
      Bus.instance.fire(MemoryShareUpdatedEvent("create-memory-lane-link"));

      return (shareUrl, memoryShare.id);
    } catch (e, s) {
      _logger.severe("Failed to create memory lane link", e, s);
      rethrow;
    }
  }

  Future<List<MemoryShare>> listMemoryShares() async {
    try {
      final response = await _enteDio.get('/memory-share');
      final List<dynamic> shares = response.data['memoryShares'] ?? [];
      final localSharesByID = {
        for (final share in await _db.getAll()) share.id: share,
      };
      if (shares.isEmpty) {
        _memoryShareByHashCache.clear();
        for (final localShare in localSharesByID.values) {
          await _db.delete(localShare.id);
        }
        return [];
      }
      Uint8List? memoryEntityKey;
      try {
        memoryEntityKey = await entityService.getOrCreateEntityKey(
          EntityType.memory,
        );
      } catch (e, s) {
        _logger.severe(
          "Failed to get memory entity key while listing memory shares",
          e,
          s,
        );
        memoryEntityKey = null;
      }
      final result = shares.map((s) {
        var share = MemoryShare.fromJson(s as Map<String, dynamic>);
        final entityKey = memoryEntityKey;
        if (entityKey != null) {
          final fragment = Uri.parse(share.url).fragment;
          if (fragment.isEmpty) {
            final resolvedFragment = _resolveFragmentSecret(share, entityKey);
            if (resolvedFragment != null && resolvedFragment.isNotEmpty) {
              share = share.copyWith(url: "${share.url}#$resolvedFragment");
            }
          }
        }
        return share;
      }).toList();
      _memoryShareByHashCache.clear();
      final activeRemoteShareIDs = <int>{};
      final activeShares = <MemoryShare>[];
      for (final share in result) {
        if (share.isDeleted) {
          await _db.delete(share.id);
          _removeMemoryShareFromCache(share.id);
          continue;
        }
        activeRemoteShareIDs.add(share.id);
        final localShare = localSharesByID[share.id];
        final mergedShare = share.copyWith(
          memoryHash: share.memoryHash ?? localShare?.memoryHash,
          previewUploadedFileID: localShare?.previewUploadedFileID,
          fileCount: localShare?.fileCount,
        );
        await _db.upsert(mergedShare);
        _updateMemoryShareCache(mergedShare);
        activeShares.add(mergedShare);
      }
      for (final localShare in localSharesByID.values) {
        if (!activeRemoteShareIDs.contains(localShare.id)) {
          await _db.delete(localShare.id);
        }
      }

      return activeShares;
    } catch (e, s) {
      _logger.severe("Failed to list memory shares", e, s);
      rethrow;
    }
  }

  Future<List<MemoryShare>> getLocalMemoryShares() async {
    return _db.getAll();
  }

  Future<List<EnteFile>> getPublicMemoryFiles(String shareUrl) async {
    try {
      final uri = Uri.parse(shareUrl);
      final accessToken = _extractAccessToken(uri);
      final shareKey = _resolveShareKeyFromUrlFragment(uri.fragment);
      final response = await _enteDio.get(
        '/public-memory/files',
        options: Options(headers: {'X-Auth-Access-Token': accessToken}),
      );
      final rawFiles = response.data['files'] as List<dynamic>? ?? const [];
      final files = <EnteFile>[];
      for (final rawFile in rawFiles) {
        final localFile = await _resolveLocalFileFromShareItem(rawFile);
        if (localFile != null) {
          files.add(localFile);
          continue;
        }
        final file = await _parsePublicMemoryFile(rawFile, shareKey);
        if (file != null) {
          files.add(file);
        }
      }
      return files;
    } catch (e, s) {
      _logger.severe("Failed to fetch public memory files", e, s);
      rethrow;
    }
  }

  Future<EnteFile?> _resolveLocalFileFromShareItem(dynamic rawFile) async {
    final item = _toMap(rawFile);
    final remoteFile = _toMap(item?['file']);
    if (remoteFile == null) {
      return null;
    }
    final fileID = _toInt(remoteFile['id']);
    if (fileID == null) {
      return null;
    }
    return FilesDB.instance.getAnyUploadedFile(fileID);
  }

  String? getMemoryShareTitle(MemoryShare share) {
    try {
      final metadataCipher = share.metadataCipher;
      final metadataNonce = share.metadataNonce;
      if (metadataCipher == null || metadataNonce == null) {
        return null;
      }
      final fragment = Uri.parse(share.url).fragment;
      if (fragment.isEmpty) {
        return null;
      }
      final shareKey = _resolveShareKeyFromUrlFragment(fragment);
      final decryptedMetadata = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(metadataCipher),
        shareKey,
        CryptoUtil.base642bin(metadataNonce),
      );
      final parsed = _decodeMemoryShareMetadata(decryptedMetadata, share.type);
      if (parsed is! Map<String, dynamic>) {
        return null;
      }
      final name = parsed["name"];
      if (name is String && name.trim().isNotEmpty) {
        return name;
      }
      return null;
    } catch (e, s) {
      _logger.severe(
        "Failed to read memory share title for share ${share.id}",
        e,
        s,
      );
      return null;
    }
  }

  Future<void> deleteMemoryShare(int shareID) async {
    try {
      await _enteDio.delete('/memory-share/$shareID');
      await _db.delete(shareID);
      _removeMemoryShareFromCache(shareID);
      Bus.instance.fire(MemoryShareUpdatedEvent("delete-memory-share"));
    } catch (e, s) {
      _logger.severe("Failed to delete memory share $shareID", e, s);
      rethrow;
    }
  }

  Future<EnteFile?> _parsePublicMemoryFile(
    dynamic rawFile,
    Uint8List shareKey,
  ) async {
    final item = _toMap(rawFile);
    final remoteFile = _toMap(item?['file']);
    if (item == null || remoteFile == null) {
      return null;
    }
    try {
      final file = EnteFile();
      file.uploadedFileID = _toInt(remoteFile['id']);
      file.ownerID = _toInt(remoteFile['ownerID']);
      // /public-memory/files returns per-share re-encrypted key material at the
      // top level. Fall back to nested fields for compatibility.
      file.encryptedKey =
          item['encryptedKey'] as String? ??
          remoteFile['encryptedKey'] as String?;
      file.keyDecryptionNonce =
          item['keyDecryptionNonce'] as String? ??
          remoteFile['keyDecryptionNonce'] as String?;
      final collectionAddedAt = _toInt(remoteFile['collectionAddedAt']);
      if (collectionAddedAt != null) {
        file.addedTime = collectionAddedAt;
      }

      final fileData = _toMap(remoteFile['file']);
      final thumbnailData = _toMap(remoteFile['thumbnail']);
      final metadataData = _toMap(remoteFile['metadata']);
      if (fileData == null || thumbnailData == null || metadataData == null) {
        return null;
      }

      file.fileDecryptionHeader = fileData['decryptionHeader'] as String?;
      file.thumbnailDecryptionHeader =
          thumbnailData['decryptionHeader'] as String?;
      file.metadataDecryptionHeader =
          metadataData['decryptionHeader'] as String?;

      final info = _toMap(remoteFile['info']);
      if (info != null) {
        file.fileSize = _toInt(info['fileSize']);
      }

      if (file.encryptedKey == null ||
          file.keyDecryptionNonce == null ||
          file.metadataDecryptionHeader == null) {
        return null;
      }

      final encryptedMetadata = metadataData['encryptedData'] as String?;
      if (encryptedMetadata == null) {
        return null;
      }

      final fileKey = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(file.encryptedKey!),
        shareKey,
        CryptoUtil.base642bin(file.keyDecryptionNonce!),
      );
      final encodedMetadata = await CryptoUtil.decryptChaCha(
        CryptoUtil.base642bin(encryptedMetadata),
        fileKey,
        CryptoUtil.base642bin(file.metadataDecryptionHeader!),
      );
      final decodedMetadata = jsonDecode(utf8.decode(encodedMetadata));
      if (decodedMetadata is! Map) {
        return null;
      }
      file.applyMetadata(Map<String, dynamic>.from(decodedMetadata));

      final pubMagicMetadata = _toMap(remoteFile['pubMagicMetadata']);
      if (pubMagicMetadata != null) {
        final data = pubMagicMetadata['data'] as String?;
        final header = pubMagicMetadata['header'] as String?;
        if (data != null && header != null) {
          final utfEncodedMmd = await CryptoUtil.decryptChaCha(
            CryptoUtil.base642bin(data),
            fileKey,
            CryptoUtil.base642bin(header),
          );
          file.pubMmdEncodedJson = utf8.decode(utfEncodedMmd);
          file.pubMmdVersion = _toInt(pubMagicMetadata['version']) ?? 0;
          file.pubMagicMetadata = PubMagicMetadata.fromEncodedJson(
            file.pubMmdEncodedJson!,
          );
        }
      }

      file.localID = null;
      return file;
    } catch (e, s) {
      _logger.warning("Failed to parse public memory file", e, s);
      return null;
    }
  }

  Future<_MemoryShareSecretPayload> _prepareShareSecret() async {
    try {
      final memoryEntityKey = await entityService.getOrCreateEntityKey(
        EntityType.memory,
      );
      final secret = _generateBase62Secret(_shortFragmentSecretLength);
      final shareKey = _deriveShareKeyFromSecret(secret);
      final encryptedSecret = CryptoUtil.encryptSync(
        Uint8List.fromList(utf8.encode(secret)),
        memoryEntityKey,
      );
      return _MemoryShareSecretPayload(
        secret: secret,
        shareKey: shareKey,
        encryptedShareSecret: CryptoUtil.bin2base64(
          encryptedSecret.encryptedData!,
        ),
        encryptedShareSecretNonce: CryptoUtil.bin2base64(
          encryptedSecret.nonce!,
        ),
      );
    } catch (e, s) {
      _logger.severe("Failed to prepare memory share secret", e, s);
      rethrow;
    }
  }

  String? _resolveFragmentSecret(MemoryShare share, Uint8List memoryEntityKey) {
    try {
      final decrypted = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(share.encryptedKey),
        memoryEntityKey,
        CryptoUtil.base642bin(share.keyDecryptionNonce),
      );
      return _tryDecodeShortFragmentSecret(decrypted);
    } catch (e, s) {
      _logger.severe(
        "Failed to resolve memory share fragment secret for share ${share.id}",
        e,
        s,
      );
      return null;
    }
  }

  String? _tryDecodeShortFragmentSecret(Uint8List value) {
    if (value.length != _shortFragmentSecretLength) {
      return null;
    }
    try {
      final secret = utf8.decode(value);
      if (_base62SecretPattern.hasMatch(secret)) {
        return secret;
      }
    } catch (e, s) {
      _logger.severe("Failed to decode memory share fragment secret", e, s);
      return null;
    }
    return null;
  }

  Uint8List _resolveShareKeyFromUrlFragment(String fragment) {
    if (!_base62SecretPattern.hasMatch(fragment)) {
      throw const FormatException("Invalid memory share fragment");
    }
    return _deriveShareKeyFromSecret(fragment);
  }

  Uint8List _deriveShareKeyFromSecret(String secret) {
    final digest = sha256.convert(utf8.encode(secret));
    return Uint8List.fromList(digest.bytes);
  }

  String _generateBase62Secret(int length) {
    const charset =
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(charset[random.nextInt(charset.length)]);
    }
    return buffer.toString();
  }

  String _extractAccessToken(Uri uri) {
    final tokenFromQuery = uri.queryParameters["t"];
    if (tokenFromQuery != null && tokenFromQuery.isNotEmpty) {
      return tokenFromQuery;
    }
    const routePrefixes = {"memories"};
    final pathSegments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    for (var i = pathSegments.length - 1; i >= 0; i--) {
      final segment = pathSegments[i];
      if (!routePrefixes.contains(segment.toLowerCase())) {
        return segment;
      }
    }
    throw const FormatException("Invalid memory share URL");
  }

  Map<String, dynamic>? _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  Future<(String, int)> getOrCreateMemoryLink({
    required List<Memory> memories,
    required String title,
  }) async {
    try {
      final files = uniqueUploadedFiles(Memory.filesFromMemories(memories));
      final filesForShare = files.take(_maxMemoryShareFiles).toList();
      final memoryHash = _getMemoryHash(filesForShare);
      final existingShare = await _findMemoryShareByHash(memoryHash);
      if (existingShare != null &&
          Uri.parse(existingShare.url).fragment.isNotEmpty) {
        return (existingShare.url, existingShare.id);
      }
      return _createMemoryLink(
        files: filesForShare,
        title: title,
        memoryHash: memoryHash,
      );
    } catch (e, s) {
      _logger.severe("Failed to create memory share link data", e, s);
      rethrow;
    }
  }

  Future<(String, int)> getOrCreateMemoryLaneLink({
    required List<MemoryLaneEntry> entries,
    required String title,
    String? personId,
    String? personName,
    String? birthDate,
  }) async {
    try {
      if (entries.isEmpty) {
        throw Exception("No uploaded files to share");
      }
      final uniqueFileIDs = entries
          .map((entry) => entry.fileId)
          .toSet()
          .toList();
      final filesByID = await FilesDB.instance.getFileIDToFileFromIDs(
        uniqueFileIDs,
      );
      final laneItems = <_MemoryLaneShareItem>[];
      final seenUploadedFileIDs = <int>{};
      for (final entry in entries) {
        final file = filesByID[entry.fileId];
        final uploadedFileID = file?.uploadedFileID;
        if (file == null ||
            uploadedFileID == null ||
            !seenUploadedFileIDs.add(uploadedFileID)) {
          continue;
        }
        laneItems.add(_MemoryLaneShareItem(file: file, entry: entry));
      }
      if (laneItems.isEmpty) {
        throw Exception("No uploaded files to share");
      }
      final facesByFileID = await _loadLaneFacesByFileID(laneItems);
      final metadata = _buildMemoryLaneMetadata(
        laneItems,
        title: title,
        personId: personId,
        personName: personName,
        birthDate: birthDate,
        facesByFileID: facesByFileID,
      );
      final memoryHash = _getMemoryLaneHash(metadata);
      final existingShare = await _findMemoryShareByHash(memoryHash);
      if (existingShare != null &&
          existingShare.type == MemoryShareType.lane &&
          Uri.parse(existingShare.url).fragment.isNotEmpty) {
        return (existingShare.url, existingShare.id);
      }
      return _createMemoryLaneLink(
        laneItems: laneItems,
        metadata: metadata,
        memoryHash: memoryHash,
      );
    } catch (e, s) {
      _logger.severe("Failed to create memory lane share link data", e, s);
      rethrow;
    }
  }

  Future<MemoryShare?> _findMemoryShareByHash(String memoryHash) async {
    final cachedShare = _memoryShareByHashCache[memoryHash];
    if (cachedShare != null && !cachedShare.isDeleted) {
      return cachedShare;
    }

    try {
      final remoteShares = await listMemoryShares();
      for (final share in remoteShares) {
        if (!share.isDeleted && share.memoryHash == memoryHash) {
          _updateMemoryShareCache(share);
          return share;
        }
      }
    } catch (e, s) {
      _logger.warning(
        "Failed to refresh memory-share hash cache while resolving memory hash",
        e,
        s,
      );
    }

    return null;
  }

  Future<void> _loadMemoryShareHashCache() async {
    _memoryShareByHashCache.clear();
    final shares = await _db.getAll();
    for (final share in shares) {
      _updateMemoryShareCache(share);
    }
  }

  void _updateMemoryShareCache(MemoryShare share) {
    final hash = share.memoryHash;
    if (hash == null || hash.isEmpty) {
      return;
    }
    if (share.isDeleted) {
      final existing = _memoryShareByHashCache[hash];
      if (existing != null && existing.id == share.id) {
        _memoryShareByHashCache.remove(hash);
      }
      return;
    }
    final existing = _memoryShareByHashCache[hash];
    if (existing == null || share.createdAt >= existing.createdAt) {
      _memoryShareByHashCache[hash] = share;
    }
  }

  void _removeMemoryShareFromCache(int shareID) {
    _memoryShareByHashCache.removeWhere((_, share) => share.id == shareID);
  }

  String _getMemoryHash(List<EnteFile> files) {
    final uploadedFileIDs = files
        .map((file) => file.uploadedFileID)
        .whereType<int>()
        .toList();
    if (uploadedFileIDs.isEmpty) {
      throw Exception("No uploaded files to share");
    }
    final hashInput = "${uploadedFileIDs.length}:${uploadedFileIDs.join(',')}";
    return sha256.convert(utf8.encode(hashInput)).toString();
  }

  String _getMemoryLaneHash(Map<String, dynamic> metadata) {
    final frames = metadata['frames'];
    final stableFrames = <Map<String, dynamic>>[];
    if (frames is List) {
      for (final frame in frames) {
        stableFrames.add({
          'fileID': frame['fileID'],
          'position': frame['position'],
          'faceID': frame['faceID'],
        });
      }
    }

    final hashMetadata = <String, dynamic>{
      if (metadata['personID'] != null) 'personID': metadata['personID'],
      if (metadata['personName'] != null) 'personName': metadata['personName'],
      if (metadata['birthDate'] != null) 'birthDate': metadata['birthDate'],
      'frames': stableFrames,
    };
    final hashInput = jsonEncode(hashMetadata);
    return sha256.convert(utf8.encode(hashInput)).toString();
  }

  Map<String, dynamic> _buildMemoryLaneMetadata(
    List<_MemoryLaneShareItem> laneItems, {
    required String title,
    String? personId,
    String? personName,
    String? birthDate,
    Map<int, List<Face>>? facesByFileID,
  }) {
    if (laneItems.isEmpty) {
      throw Exception("No uploaded files to share");
    }
    final normalizedPersonId = personId?.trim();
    final normalizedPersonName = personName?.trim();
    final normalizedBirthDate = birthDate?.trim();
    final captionType =
        (normalizedBirthDate != null && normalizedBirthDate.isNotEmpty)
        ? 'age'
        : 'yearsAgo';

    return {
      'name': title,
      'kind': MemoryShareType.lane.name,
      'captionType': captionType,
      if (normalizedPersonId != null && normalizedPersonId.isNotEmpty)
        'personID': normalizedPersonId,
      if (normalizedPersonName != null && normalizedPersonName.isNotEmpty)
        'personName': normalizedPersonName,
      if (normalizedBirthDate != null && normalizedBirthDate.isNotEmpty)
        'birthDate': normalizedBirthDate,
      'frames': [
        for (var i = 0; i < laneItems.length; i++)
          {
            'fileID': laneItems[i].file.uploadedFileID,
            'position': i,
            ..._buildLaneFaceMetadata(
              laneItems[i].entry,
              faces: facesByFileID?[laneItems[i].entry.fileId],
            ),
          },
      ],
    };
  }

  Future<Map<int, List<Face>>> _loadLaneFacesByFileID(
    List<_MemoryLaneShareItem> laneItems,
  ) async {
    final uniqueFileIDs = laneItems.map((item) => item.entry.fileId).toSet();
    final faceEntries = await Future.wait(
      uniqueFileIDs.map((fileID) async {
        try {
          final faces = await MLDataDB.instance.getFacesForGivenFileID(fileID);
          return MapEntry(fileID, faces ?? const <Face>[]);
        } catch (e, s) {
          _logger.warning(
            "Failed to load lane faces for fileID=$fileID, falling back to faceID parsing",
            e,
            s,
          );
          return MapEntry(fileID, const <Face>[]);
        }
      }),
    );
    return Map<int, List<Face>>.fromEntries(faceEntries);
  }

  Map<String, dynamic> _buildLaneFaceMetadata(
    MemoryLaneEntry entry, {
    List<Face>? faces,
  }) {
    final faceBox = resolveLaneFaceBox(entry.faceId, faces: faces);
    final crop = computePaddedFaceCropBox(faceBox);
    return {
      'faceID': entry.faceId,
      'faceBox': faceBox.toJson(),
      'crop': crop.toJson(),
      'creationTime': entry.creationTimeMicros,
      'year': entry.year,
    };
  }

  dynamic _decodeMemoryShareMetadata(
    Uint8List decryptedMetadata,
    MemoryShareType shareType,
  ) {
    if (shareType == MemoryShareType.lane) {
      final decompressed = GZipCodec().decode(decryptedMetadata);
      return jsonDecode(utf8.decode(decompressed));
    }
    return jsonDecode(utf8.decode(decryptedMetadata));
  }
}

class _MemoryLaneShareItem {
  final EnteFile file;
  final MemoryLaneEntry entry;

  const _MemoryLaneShareItem({required this.file, required this.entry});
}

class _MemoryShareSecretPayload {
  final String secret;
  final Uint8List shareKey;
  final String encryptedShareSecret;
  final String encryptedShareSecretNonce;

  const _MemoryShareSecretPayload({
    required this.secret,
    required this.shareKey,
    required this.encryptedShareSecret,
    required this.encryptedShareSecretNonce,
  });

  Map<String, dynamic> metadata() {
    return {
      'encryptedKey': encryptedShareSecret,
      'keyDecryptionNonce': encryptedShareSecretNonce,
    };
  }
}
