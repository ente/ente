import "dart:typed_data";

import "package:computer/computer.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/collections_service.dart";

Uint8List getFileKey(EnteFile file) {
  final collectionKey = CollectionsService.instance.getCollectionKey(
    file.collectionID!,
  );
  return getFileKeyWithCollectionKey(file, collectionKey);
}

Uint8List getPublicFileKey(EnteFile file) {
  final collectionKey = CollectionsService.instance.getPublicCollectionKey(
    file.collectionID!,
  );
  return getFileKeyWithCollectionKey(file, collectionKey);
}

Uint8List getFileKeyWithCollectionKey(EnteFile file, Uint8List collectionKey) {
  final encryptedKey = CryptoUtil.base642bin(file.encryptedKey!);
  final nonce = CryptoUtil.base642bin(file.keyDecryptionNonce!);
  return CryptoUtil.decryptSync(encryptedKey, collectionKey, nonce);
}

Future<Uint8List> getFileKeyUsingBgWorker(EnteFile file) async {
  final collectionKey = CollectionsService.instance.getCollectionKey(
    file.collectionID!,
  );
  return getFileKeyWithCollectionKeyUsingBgWorker(file, collectionKey);
}

Future<Uint8List> getPublicFileKeyUsingBgWorker(EnteFile file) async {
  final collectionKey = CollectionsService.instance.getPublicCollectionKey(
    file.collectionID!,
  );
  return getFileKeyWithCollectionKeyUsingBgWorker(file, collectionKey);
}

Future<Uint8List> getFileKeyWithCollectionKeyUsingBgWorker(
  EnteFile file,
  Uint8List collectionKey,
) async {
  return await Computer.shared().compute(
    _decryptFileKey,
    param: <String, dynamic>{
      "encryptedKey": file.encryptedKey,
      "keyDecryptionNonce": file.keyDecryptionNonce,
      "collectionKey": collectionKey,
    },
  );
}

Uint8List _decryptFileKey(Map<String, dynamic> args) {
  final encryptedKey = CryptoUtil.base642bin(args["encryptedKey"]);
  final nonce = CryptoUtil.base642bin(args["keyDecryptionNonce"]);
  return CryptoUtil.decryptSync(encryptedKey, args["collectionKey"], nonce);
}
