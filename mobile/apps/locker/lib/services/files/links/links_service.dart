import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/configuration.dart";
import "package:locker/services/files/links/links_client.dart";
import "package:locker/services/files/links/models/shareable_link.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:logging/logging.dart";

class LinksService {
  LinksService._();

  static final LinksService instance = LinksService._();

  late final LinksClient _client;
  final Logger _logger = Logger("LinksService");

  Future<void> init() async {
    _client = LinksClient.instance;
  }

  Future<ShareableLink> getOrCreateLink(EnteFile file) async {
    final fileKey = await CollectionService.instance.getFileKey(file);
    final secretPayload = await _prepareLinkSecret(fileKey);

    final link = await _client.getOrCreateLink(
      file.uploadedFileID!,
      metadata: secretPayload.metadata(),
    );
    final fragmentSecret = await _resolveFragmentSecret(link, secretPayload);
    link.fullURL = "${link.url}#$fragmentSecret";
    return link;
  }

  Future<void> deleteLink(int fileID) async {
    await _client.deleteLink(fileID);
  }

  Future<_LinkSecretPayload> _prepareLinkSecret(Uint8List fileKey) async {
    try {
      final secret = _generateBase62Secret(12);
      final secretBytes = Uint8List.fromList(utf8.encode(secret));
      final secretBase64 = CryptoUtil.bin2base64(secretBytes);

      final kdfSalt = CryptoUtil.getSaltToDeriveKey();
      final derivedKey = await CryptoUtil.deriveInteractiveKey(
        Uint8List.fromList(utf8.encode(secret)),
        kdfSalt,
      );
      final encryptedKey = CryptoUtil.encryptSync(fileKey, derivedKey.key);

      final keyAttributes = Configuration.instance.getKeyAttributes();
      final userPublicKey = keyAttributes?.publicKey;
      if (userPublicKey == null) {
        throw StateError(
          "Public key unavailable while generating share secret",
        );
      }
      final encryptedShareKeyBytes = CryptoUtil.sealSync(
        Uint8List.fromList(utf8.encode(secretBase64)),
        CryptoUtil.base642bin(userPublicKey),
      );

      return _LinkSecretPayload(
        secret: secret,
        encryptedFileKey: CryptoUtil.bin2base64(encryptedKey.encryptedData!),
        encryptedFileKeyNonce: CryptoUtil.bin2base64(encryptedKey.nonce!),
        kdfNonce: CryptoUtil.bin2base64(kdfSalt),
        kdfMemLimit: derivedKey.memLimit,
        kdfOpsLimit: derivedKey.opsLimit,
        encryptedShareKey: CryptoUtil.bin2base64(encryptedShareKeyBytes),
      );
    } catch (e, s) {
      _logger.severe("Failed to prepare link secret", e, s);
      rethrow;
    }
  }

  Future<String> _resolveFragmentSecret(
    ShareableLink link,
    _LinkSecretPayload payload,
  ) async {
    final encryptedShareKey = link.encryptedShareKey;
    if (encryptedShareKey == null) {
      return payload.secret;
    }

    final keyAttributes = Configuration.instance.getKeyAttributes();
    final secretKey = Configuration.instance.getSecretKey();
    if (keyAttributes == null || secretKey == null) {
      _logger.severe(
        "Missing key material to decrypt share secret for existing link",
      );
      throw StateError("Unable to decrypt share secret");
    }

    try {
      final decryptedBytes = CryptoUtil.openSealSync(
        CryptoUtil.base642bin(encryptedShareKey),
        CryptoUtil.base642bin(keyAttributes.publicKey),
        secretKey,
      );
      final secretBase64 = utf8.decode(decryptedBytes);
      final secret = utf8.decode(CryptoUtil.base642bin(secretBase64));
      return secret;
    } catch (e, s) {
      _logger.severe("Failed to decrypt share secret", e, s);
      throw StateError("Unable to decrypt share secret");
    }
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
}

class _LinkSecretPayload {
  _LinkSecretPayload({
    required this.secret,
    required this.encryptedFileKey,
    required this.encryptedFileKeyNonce,
    required this.kdfNonce,
    required this.kdfMemLimit,
    required this.kdfOpsLimit,
    required this.encryptedShareKey,
  });

  final String secret;
  final String encryptedFileKey;
  final String encryptedFileKeyNonce;
  final String kdfNonce;
  final int kdfMemLimit;
  final int kdfOpsLimit;
  final String encryptedShareKey;

  Map<String, dynamic> metadata() {
    return {
      'encryptedFileKey': encryptedFileKey,
      'encryptedFileKeyNonce': encryptedFileKeyNonce,
      'kdfNonce': kdfNonce,
      'kdfMemLimit': kdfMemLimit,
      'kdfOpsLimit': kdfOpsLimit,
      'encryptedShareKey': encryptedShareKey,
    };
  }
}
