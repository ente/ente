import 'dart:io';
import 'dart:typed_data';

import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_crypto_dart/ente_crypto_dart.dart' as dart_impl;

class EnteCryptoDartAdapter implements CryptoApi {
  const EnteCryptoDartAdapter();

  @override
  Future<void> init() => dart_impl.CryptoUtil.init();

  @override
  Uint8List base642bin(String b64) => dart_impl.CryptoUtil.base642bin(b64);

  @override
  String bin2base64(Uint8List bin, {bool urlSafe = false}) =>
      dart_impl.CryptoUtil.bin2base64(bin, urlSafe: urlSafe);

  @override
  String bin2hex(Uint8List bin) => dart_impl.CryptoUtil.bin2hex(bin);

  @override
  Uint8List hex2bin(String hex) => dart_impl.CryptoUtil.hex2bin(hex);

  @override
  Uint8List strToBin(String str) => dart_impl.CryptoUtil.strToBin(str);

  @override
  EncryptionResult encryptSync(Uint8List source, Uint8List key) =>
      _mapEncryptionResult(dart_impl.CryptoUtil.encryptSync(source, key));

  @override
  Future<Uint8List> decrypt(Uint8List cipher, Uint8List key, Uint8List nonce) =>
      dart_impl.CryptoUtil.decrypt(cipher, key, nonce);

  @override
  Uint8List decryptSync(Uint8List cipher, Uint8List key, Uint8List nonce) =>
      dart_impl.CryptoUtil.decryptSync(cipher, key, nonce);

  @override
  Future<EncryptionResult> encryptData(Uint8List source, Uint8List key) async {
    final result = await dart_impl.CryptoUtil.encryptData(source, key);
    return _mapEncryptionResult(result);
  }

  @override
  Future<Uint8List> decryptData(
    Uint8List source,
    Uint8List key,
    Uint8List header,
  ) => dart_impl.CryptoUtil.decryptData(source, key, header);

  @override
  Future<EncryptionResult> encryptFile(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
  }) async {
    final result = await dart_impl.CryptoUtil.encryptFile(
      sourceFilePath,
      destinationFilePath,
      key: key,
    );
    return _mapEncryptionResult(result);
  }

  @override
  Future<FileEncryptResult> encryptFileWithMd5(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
    int? multiPartChunkSizeInBytes,
  }) async {
    final result = await dart_impl.CryptoUtil.encryptFileWithMD5(
      sourceFilePath,
      destinationFilePath,
      key: key,
      multiPartChunkSizeInBytes: multiPartChunkSizeInBytes,
    );
    return _mapFileEncryptionResult(result);
  }

  @override
  Future<void> decryptFile(
    String sourceFilePath,
    String destinationFilePath,
    Uint8List header,
    Uint8List key,
  ) => dart_impl.CryptoUtil.decryptFile(
    sourceFilePath,
    destinationFilePath,
    header,
    key,
  );

  @override
  Uint8List generateKey() => dart_impl.CryptoUtil.generateKey();

  @override
  CryptoKeyPair generateKeyPair() {
    final pair = dart_impl.CryptoUtil.generateKeyPair();
    return CryptoKeyPair(
      publicKey: pair.publicKey,
      secretKey: pair.secretKey.extractBytes(),
    );
  }

  @override
  Uint8List openSealSync(
    Uint8List input,
    Uint8List publicKey,
    Uint8List secretKey,
  ) => dart_impl.CryptoUtil.openSealSync(input, publicKey, secretKey);

  @override
  Uint8List sealSync(Uint8List input, Uint8List publicKey) =>
      dart_impl.CryptoUtil.sealSync(input, publicKey);

  @override
  Future<DerivedKeyResult> deriveSensitiveKey(
    Uint8List password,
    Uint8List salt,
  ) async {
    final result = await dart_impl.CryptoUtil.deriveSensitiveKey(
      password,
      salt,
    );
    return DerivedKeyResult(result.key, result.memLimit, result.opsLimit);
  }

  @override
  Future<DerivedKeyResult> deriveInteractiveKey(
    Uint8List password,
    Uint8List salt,
  ) async {
    final result = await dart_impl.CryptoUtil.deriveInteractiveKey(
      password,
      salt,
    );
    return DerivedKeyResult(result.key, result.memLimit, result.opsLimit);
  }

  @override
  Future<Uint8List> deriveKey(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  ) => dart_impl.CryptoUtil.deriveKey(password, salt, memLimit, opsLimit);

  @override
  Future<Uint8List> deriveLoginKey(Uint8List key) =>
      dart_impl.CryptoUtil.deriveLoginKey(key);

  @override
  Uint8List getSaltToDeriveKey() => dart_impl.CryptoUtil.getSaltToDeriveKey();

  @override
  Uint8List cryptoPwHash(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  ) => dart_impl.cryptoPwHash(
    password,
    salt,
    memLimit,
    opsLimit,
    dart_impl.sodium,
  );

  @override
  int get pwhashMemLimitInteractive =>
      dart_impl.sodium.crypto.pwhash.memLimitInteractive;

  @override
  int get pwhashMemLimitSensitive =>
      dart_impl.sodium.crypto.pwhash.memLimitSensitive;

  @override
  int get pwhashOpsLimitInteractive =>
      dart_impl.sodium.crypto.pwhash.opsLimitInteractive;

  @override
  int get pwhashOpsLimitSensitive =>
      dart_impl.sodium.crypto.pwhash.opsLimitSensitive;

  @override
  Future<Uint8List> getHash(File source) => dart_impl.getHash(source);

  EncryptionResult _mapEncryptionResult(dart_impl.EncryptionResult result) {
    return EncryptionResult(
      encryptedData: result.encryptedData,
      key: result.key,
      header: result.header,
      nonce: result.nonce,
    );
  }

  FileEncryptResult _mapFileEncryptionResult(
    dart_impl.FileEncryptResult result,
  ) {
    return FileEncryptResult(
      key: result.key,
      header: result.header,
      fileMd5: result.fileMd5,
      partMd5s: result.partMd5s,
      partSize: result.partSize,
    );
  }
}
