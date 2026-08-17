import "dart:convert";
import "dart:io";
import 'dart:typed_data';

import "package:computer/computer.dart";
import "package:convert/convert.dart";
import "package:crypto/crypto.dart";
import "package:ente_crypto/src/models/derived_key_result.dart";
import "package:ente_crypto/src/models/encryption_result.dart";
import "package:ente_crypto/src/models/errors.dart";
import "package:flutter/foundation.dart";
import "package:flutter_sodium/flutter_sodium.dart";
import "package:logging/logging.dart";

const int encryptionChunkSize = 4 * 1024 * 1024;
final int decryptionChunkSize =
    encryptionChunkSize + Sodium.cryptoSecretstreamXchacha20poly1305Abytes;
const int hashChunkSize = 4 * 1024 * 1024;
const int loginSubKeyLen = 32;
const int loginSubKeyId = 1;
const String loginSubKeyContext = "loginctx";

Uint8List cryptoSecretboxEasy(Map<String, dynamic> args) {
  return Sodium.cryptoSecretboxEasy(args["source"], args["nonce"], args["key"]);
}

Uint8List cryptoSecretboxOpenEasy(Map<String, dynamic> args) {
  return Sodium.cryptoSecretboxOpenEasy(
    args["cipher"],
    args["nonce"],
    args["key"],
  );
}

Uint8List cryptoPwHash(Map<String, dynamic> args) {
  return Sodium.cryptoPwhash(
    Sodium.cryptoSecretboxKeybytes,
    args["password"],
    args["salt"],
    args["opsLimit"],
    args["memLimit"],
    Sodium.cryptoPwhashAlgArgon2id13,
  );
}

Uint8List cryptoKdfDeriveFromKey(Map<String, dynamic> args) {
  return Sodium.cryptoKdfDeriveFromKey(
    args["subkeyLen"],
    args["subkeyId"],
    args["context"],
    args["key"],
  );
}

Future<Uint8List> cryptoGenericHash(Map<String, dynamic> args) async {
  final file = File(args["sourceFilePath"]);
  final state = Sodium.cryptoGenerichashInit(
    null,
    Sodium.cryptoGenerichashBytesMax,
  );
  await for (final chunk in file.openRead()) {
    if (chunk is Uint8List) {
      Sodium.cryptoGenerichashUpdate(state, chunk);
    } else {
      Sodium.cryptoGenerichashUpdate(state, Uint8List.fromList(chunk));
    }
  }
  return Sodium.cryptoGenerichashFinal(state, Sodium.cryptoGenerichashBytesMax);
}

EncryptionResult chachaEncryptData(Map<String, dynamic> args) {
  final initPushResult = Sodium.cryptoSecretstreamXchacha20poly1305InitPush(
    args["key"],
  );
  final encryptedData = Sodium.cryptoSecretstreamXchacha20poly1305Push(
    initPushResult.state,
    args["source"],
    null,
    Sodium.cryptoSecretstreamXchacha20poly1305TagFinal,
  );
  return EncryptionResult(
    encryptedData: encryptedData,
    header: initPushResult.header,
  );
}

Future<FileEncryptResult> chachaEncryptFile(Map<String, dynamic> args) async {
  final encryptionStartTime = DateTime.now().millisecondsSinceEpoch;
  final logger = Logger("ChaChaEncryptV1");
  final sourceFile = File(args["sourceFilePath"]);
  final destinationFile = File(args["destinationFilePath"]);
  final sourceFileLength = await sourceFile.length();
  logger.info("Encrypting file of size " + sourceFileLength.toString());

  final inputFile = sourceFile.openSync(mode: FileMode.read);
  final key = args["key"] ?? Sodium.cryptoSecretstreamXchacha20poly1305Keygen();
  final initPushResult = Sodium.cryptoSecretstreamXchacha20poly1305InitPush(
    key,
  );
  var bytesRead = 0;
  var tag = Sodium.cryptoSecretstreamXchacha20poly1305TagMessage;
  while (tag != Sodium.cryptoSecretstreamXchacha20poly1305TagFinal) {
    var chunkSize = encryptionChunkSize;
    if (bytesRead + chunkSize >= sourceFileLength) {
      chunkSize = sourceFileLength - bytesRead;
      tag = Sodium.cryptoSecretstreamXchacha20poly1305TagFinal;
    }
    final buffer = await inputFile.read(chunkSize);
    if (buffer.length != chunkSize) {
      throw Exception(
        "$kPartialReadErrorTag to read $chunkSize bytes, but got ${buffer.length} bytes, sourceFileLength: $sourceFileLength",
      );
    }
    bytesRead += chunkSize;
    final encryptedData = Sodium.cryptoSecretstreamXchacha20poly1305Push(
      initPushResult.state,
      buffer,
      null,
      tag,
    );
    await destinationFile.writeAsBytes(encryptedData, mode: FileMode.append);
  }
  await inputFile.close();

  logger.info(
    "Encryption time: " +
        (DateTime.now().millisecondsSinceEpoch - encryptionStartTime)
            .toString(),
  );

  return FileEncryptResult(key: key, header: initPushResult.header);
}

Future<FileEncryptResult> chachaEncryptFileWithVerification(
  Map<String, dynamic> args,
) async {
  final encryptionStartTime = DateTime.now();
  final logger = Logger("ChaChaEncryptWithMD5");
  final sourceFile = File(args["sourceFilePath"]);
  final destinationFile = File(args["destinationFilePath"]);
  final int? multiPartChunkSizeInBytes = args["multiPartChunkSizeInBytes"];
  final sourceFileLength = await sourceFile.length();

  logger.info("Encrypting file of size $sourceFileLength");
  if (multiPartChunkSizeInBytes != null) {
    logger.info("Using multipart chunk size: $multiPartChunkSizeInBytes bytes");
  }

  final inputFile = sourceFile.openSync(mode: FileMode.read);
  final outSink = destinationFile.openWrite(mode: FileMode.writeOnly);

  final key = args["key"] ?? Sodium.cryptoSecretstreamXchacha20poly1305Keygen();
  final initPushResult = Sodium.cryptoSecretstreamXchacha20poly1305InitPush(
    key,
  );

  final verifyPullState = Sodium.cryptoSecretstreamXchacha20poly1305InitPull(
    initPushResult.header,
    key,
  );

  AccumulatorSink<Digest>? fullAccumulator;
  ChunkedConversionSink<List<int>>? fullMd5Sink;
  AccumulatorSink<Digest>? partAccumulator;
  ChunkedConversionSink<List<int>>? partMd5Sink;

  final List<String> partMd5s = [];
  final BytesBuilder partBuffer = BytesBuilder();

  if (multiPartChunkSizeInBytes == null) {
    fullAccumulator = AccumulatorSink<Digest>();
    fullMd5Sink = md5.startChunkedConversion(fullAccumulator);
  } else {
    partAccumulator = AccumulatorSink<Digest>();
    partMd5Sink = md5.startChunkedConversion(partAccumulator);
  }

  var bytesRead = 0;
  var totalEncryptedBytes = 0;
  var tag = Sodium.cryptoSecretstreamXchacha20poly1305TagMessage;
  var chunkIndex = 0;

  try {
    while (tag != Sodium.cryptoSecretstreamXchacha20poly1305TagFinal) {
      chunkIndex++;
      var chunkSize = encryptionChunkSize;
      if (bytesRead + chunkSize >= sourceFileLength) {
        chunkSize = sourceFileLength - bytesRead;
        tag = Sodium.cryptoSecretstreamXchacha20poly1305TagFinal;
      }

      final buffer = await inputFile.read(chunkSize);
      if (buffer.length != chunkSize) {
        throw Exception(
          "$kPartialReadErrorTag to read $chunkSize bytes, but got ${buffer.length} bytes",
        );
      }

      bytesRead += chunkSize;

      final encryptedData = Sodium.cryptoSecretstreamXchacha20poly1305Push(
        initPushResult.state,
        buffer,
        null,
        tag,
      );

      try {
        final pullResult = Sodium.cryptoSecretstreamXchacha20poly1305Pull(
          verifyPullState,
          encryptedData,
          null,
        );

        if (!_uint8listEquals(pullResult.m, buffer)) {
          throw Exception(
            "$kBitFlipErrorTag Data corruption detected at chunk $chunkIndex",
          );
        }

        if (pullResult.tag != tag) {
          throw Exception(
            "$kBitFlipErrorTag Tag mismatch at chunk $chunkIndex",
          );
        }
      } catch (e) {
        await inputFile.close();
        await outSink.close();
        await destinationFile.delete();
        if (e.toString().startsWith(kBitFlipErrorTag)) {
          rethrow;
        }
        throw Exception(
          "$kBitFlipErrorTag Verification failed at chunk $chunkIndex: $e",
        );
      }

      totalEncryptedBytes += encryptedData.length;

      if (multiPartChunkSizeInBytes == null) {
        fullMd5Sink!.add(encryptedData);
        outSink.add(encryptedData);
      } else {
        partBuffer.add(encryptedData);

        final bool isLastChunk =
            tag == Sodium.cryptoSecretstreamXchacha20poly1305TagFinal;

        while (partBuffer.length >= multiPartChunkSizeInBytes) {
          final partBytes = partBuffer.toBytes().sublist(
            0,
            multiPartChunkSizeInBytes,
          );

          partMd5Sink!.add(partBytes);
          partMd5Sink.close();
          final digest = partAccumulator!.events.single;
          partMd5s.add(base64.encode(digest.bytes));

          logger.info(
            "Part ${partMd5s.length}: $multiPartChunkSizeInBytes bytes",
          );

          outSink.add(partBytes);

          final remaining = partBuffer.toBytes().sublist(
            multiPartChunkSizeInBytes,
          );
          partBuffer.clear();
          partBuffer.add(remaining);

          if (!isLastChunk || partBuffer.isNotEmpty) {
            partAccumulator = AccumulatorSink<Digest>();
            partMd5Sink = md5.startChunkedConversion(partAccumulator);
          }
        }

        if (isLastChunk && partBuffer.isNotEmpty) {
          final lastPartBytes = partBuffer.toBytes();

          partMd5Sink!.add(lastPartBytes);
          partMd5Sink.close();
          final digest = partAccumulator!.events.single;
          partMd5s.add(base64.encode(digest.bytes));

          outSink.add(lastPartBytes);
          partBuffer.clear();
        }
      }
    }

    await inputFile.close();

    String? finalFileMd5;
    if (multiPartChunkSizeInBytes == null && fullMd5Sink != null) {
      fullMd5Sink.close();
      final digest = fullAccumulator!.events.single;
      finalFileMd5 = base64.encode(digest.bytes);
      logger.info("File MD5: $finalFileMd5");
    }

    await outSink.flush();
    await outSink.close();

    final encryptionTimeSeconds =
        (DateTime.now().millisecondsSinceEpoch -
            encryptionStartTime.millisecondsSinceEpoch) /
        1000;
    final partsInfo = multiPartChunkSizeInBytes != null
        ? " Parts: ${partMd5s.length}"
        : "";
    debugPrint(
      "FileEncryption: Time: ${encryptionTimeSeconds}s "
      "Total encrypted: $totalEncryptedBytes bytes$partsInfo",
    );

    return FileEncryptResult(
      key: key,
      header: initPushResult.header,
      fileMd5: finalFileMd5,
      partMd5s: multiPartChunkSizeInBytes != null && partMd5s.isNotEmpty
          ? partMd5s
          : null,
      partSize: multiPartChunkSizeInBytes,
    );
  } catch (e) {
    try {
      await inputFile.close();
    } catch (_) {}
    try {
      await outSink.close();
    } catch (_) {}
    if (await destinationFile.exists()) {
      try {
        await destinationFile.delete();
      } catch (_) {}
    }
    rethrow;
  }
}

bool _uint8listEquals(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  final len = a.length;
  int i = 0;

  while (i + 7 < len) {
    final va = a.buffer.asByteData().getUint64(
      a.offsetInBytes + i,
      Endian.little,
    );
    final vb = b.buffer.asByteData().getUint64(
      b.offsetInBytes + i,
      Endian.little,
    );
    if (va != vb) return false;
    i += 8;
  }

  while (i < len) {
    if (a[i] != b[i]) return false;
    i++;
  }

  return true;
}

Future<void> chachaDecryptFile(Map<String, dynamic> args) async {
  final logger = Logger("ChaChaDecrypt");
  final decryptionStartTime = DateTime.now().millisecondsSinceEpoch;
  final sourceFile = File(args["sourceFilePath"]);
  final destinationFile = File(args["destinationFilePath"]);
  final sourceFileLength = await sourceFile.length();
  logger.info("Decrypting file of size " + sourceFileLength.toString());

  final inputFile = sourceFile.openSync(mode: FileMode.read);
  int chunckIndex = 0;
  try {
    final pullState = Sodium.cryptoSecretstreamXchacha20poly1305InitPull(
      args["header"],
      args["key"],
    );

    var bytesRead = 0;
    var tag = Sodium.cryptoSecretstreamXchacha20poly1305TagMessage;
    while (tag != Sodium.cryptoSecretstreamXchacha20poly1305TagFinal) {
      chunckIndex++;
      var chunkSize = decryptionChunkSize;
      if (bytesRead + chunkSize >= sourceFileLength) {
        chunkSize = sourceFileLength - bytesRead;
      }
      final buffer = await inputFile.read(chunkSize);
      bytesRead += chunkSize;
      final pullResult = Sodium.cryptoSecretstreamXchacha20poly1305Pull(
        pullState,
        buffer,
        null,
      );
      await destinationFile.writeAsBytes(pullResult.m, mode: FileMode.append);
      tag = pullResult.tag;
    }
    inputFile.closeSync();

    logger.info(
      "ChaCha20 Decryption time: " +
          (DateTime.now().millisecondsSinceEpoch - decryptionStartTime)
              .toString(),
    );
  } catch (e) {
    throw Exception(
      "at chunk $chunckIndex for $sourceFileLength bytes with err $e",
    );
  }
}

Uint8List chachaDecryptData(Map<String, dynamic> args) {
  final pullState = Sodium.cryptoSecretstreamXchacha20poly1305InitPull(
    args["header"],
    args["key"],
  );
  final pullResult = Sodium.cryptoSecretstreamXchacha20poly1305Pull(
    pullState,
    args["source"],
    null,
  );
  return pullResult.m;
}

Future<void> chachaVerifyFile(Map<String, dynamic> args) async {
  try {
    final encryptedKey = Sodium.base642bin(args["encFileKey"]);
    final nonce = Sodium.base642bin(args["encFileNonce"]);
    final fileKey = Sodium.cryptoSecretboxOpenEasy(
      encryptedKey,
      nonce,
      args["parentCollectionKey"],
    );

    final header = Sodium.base642bin(args["encFileHeaders"]);
    final encFile = File(args["encFilePath"]);

    if (!await encFile.exists()) {
      throw Exception(
        "$kVerificationErrorTag: Encrypted file does not exist at path: ${args["encFilePath"]}",
      );
    }

    final encFileLength = await encFile.length();
    if (encFileLength == 0) {
      throw Exception("$kVerificationErrorTag: Encrypted file is empty");
    }

    final inputFile = encFile.openSync(mode: FileMode.read);

    try {
      final pullState = Sodium.cryptoSecretstreamXchacha20poly1305InitPull(
        header,
        fileKey,
      );

      final int chunkLimit = args["chunkLimit"] ?? 1;
      final bool verifyEntireFile = chunkLimit == -1;
      final chunksToVerify = verifyEntireFile ? 999999999 : chunkLimit;

      var bytesRead = 0;
      var chunksVerified = 0;

      while (chunksVerified < chunksToVerify) {
        final remainingBytes = encFileLength - bytesRead;
        if (remainingBytes <= 0) {
          break;
        }

        final chunkSize = remainingBytes < decryptionChunkSize
            ? remainingBytes
            : decryptionChunkSize;

        final buffer = await inputFile.read(chunkSize);
        if (buffer.isEmpty) {
          break;
        }

        bytesRead += buffer.length;
        chunksVerified++;

        try {
          final pullResult = Sodium.cryptoSecretstreamXchacha20poly1305Pull(
            pullState,
            buffer,
            null,
          );

          if (pullResult.tag ==
              Sodium.cryptoSecretstreamXchacha20poly1305TagFinal) {
            break;
          }
        } catch (e) {
          throw Exception(
            "$kVerificationErrorTag: Decryption verification failed at chunk $chunksVerified. "
            "File cannot be decrypted with the provided keys. "
            "This may indicate corruption during encryption or incorrect keys.",
          );
        }
      }
    } finally {
      inputFile.closeSync();
    }
  } catch (e) {
    if (e.toString().contains(kVerificationErrorTag)) {
      rethrow;
    }
    if (e.toString().contains("crypto_secretbox_open_easy")) {
      throw Exception(
        "$kVerificationErrorTag: Failed to decrypt file key. Invalid collection key or corrupted key data.",
      );
    }
    throw Exception("$kVerificationErrorTag: Verification failed: $e");
  }
}

class CryptoUtil {
  // Note: workers are turned on during app startup.
  static final Computer _computer = Computer.shared();

  static void init() {
    Sodium.init();
  }

  static Uint8List base642bin(
    String b64, {
    String? ignore,
    int variant = Sodium.base64VariantOriginal,
  }) {
    return Sodium.base642bin(b64, ignore: ignore, variant: variant);
  }

  static String bin2base64(Uint8List bin, {bool urlSafe = false}) {
    return Sodium.bin2base64(
      bin,
      variant: urlSafe
          ? Sodium.base64VariantUrlsafe
          : Sodium.base64VariantOriginal,
    );
  }

  static String bin2hex(Uint8List bin) {
    return Sodium.bin2hex(bin);
  }

  static Uint8List hex2bin(String hex) {
    return Sodium.hex2bin(hex);
  }

  // Runs on the caller thread; use only for small inputs.
  static EncryptionResult encryptSync(Uint8List source, Uint8List key) {
    final nonce = Sodium.randombytesBuf(Sodium.cryptoSecretboxNoncebytes);

    final args = <String, dynamic>{};
    args["source"] = source;
    args["nonce"] = nonce;
    args["key"] = key;
    final encryptedData = cryptoSecretboxEasy(args);
    return EncryptionResult(
      key: key,
      nonce: nonce,
      encryptedData: encryptedData,
    );
  }

  static Future<Uint8List> decrypt(
    Uint8List cipher,
    Uint8List key,
    Uint8List nonce,
  ) async {
    final args = <String, dynamic>{};
    args["cipher"] = cipher;
    args["nonce"] = nonce;
    args["key"] = key;
    return _computer.compute(
      cryptoSecretboxOpenEasy,
      param: args,
      taskName: "decrypt",
    );
  }

  // Runs on the caller thread; use only for small inputs.
  static Uint8List decryptSync(
    Uint8List cipher,
    Uint8List key,
    Uint8List nonce,
  ) {
    final args = <String, dynamic>{};
    args["cipher"] = cipher;
    args["nonce"] = nonce;
    args["key"] = key;
    return cryptoSecretboxOpenEasy(args);
  }

  // TODO: Remove "ChaCha", an implementation detail from the function name
  static Future<EncryptionResult> encryptChaCha(
    Uint8List source,
    Uint8List key,
  ) async {
    final args = <String, dynamic>{};
    args["source"] = source;
    args["key"] = key;
    return _computer.compute(
      chachaEncryptData,
      param: args,
      taskName: "encryptChaCha",
    );
  }

  // TODO: Remove "ChaCha", an implementation detail from the function name
  static Future<Uint8List> decryptChaCha(
    Uint8List source,
    Uint8List key,
    Uint8List header,
  ) async {
    final args = <String, dynamic>{};
    args["source"] = source;
    args["key"] = key;
    args["header"] = header;
    return _computer.compute(
      chachaDecryptData,
      param: args,
      taskName: "decryptChaCha",
    );
  }

  static Future<FileEncryptResult> encryptFile(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
  }) {
    final args = <String, dynamic>{};
    args["sourceFilePath"] = sourceFilePath;
    args["destinationFilePath"] = destinationFilePath;
    args["key"] = key;
    return _computer
        .compute<Map<String, dynamic>, FileEncryptResult>(
          chachaEncryptFile,
          param: args,
          taskName: "encryptFile",
        )
        .unwrapExceptionInComputer();
  }

  static Future<FileEncryptResult> encryptFileWithMD5(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
    int? multiPartChunkSizeInBytes,
  }) {
    final args = <String, dynamic>{};
    args["sourceFilePath"] = sourceFilePath;
    args["destinationFilePath"] = destinationFilePath;
    args["key"] = key;
    if (multiPartChunkSizeInBytes != null) {
      args["multiPartChunkSizeInBytes"] = multiPartChunkSizeInBytes;
    }
    return _computer
        .compute<Map<String, dynamic>, FileEncryptResult>(
          chachaEncryptFileWithVerification,
          param: args,
          taskName: "encryptFileWithMD5",
        )
        .unwrapExceptionInComputer();
  }

  static Future<void> decryptFile(
    String sourceFilePath,
    String destinationFilePath,
    Uint8List header,
    Uint8List key,
  ) {
    final args = <String, dynamic>{};
    args["sourceFilePath"] = sourceFilePath;
    args["destinationFilePath"] = destinationFilePath;
    args["header"] = header;
    args["key"] = key;
    return _computer
        .compute(chachaDecryptFile, param: args, taskName: "decryptFile")
        .catchError((e) {
          if (e.toString().contains(kStreamPullError)) {
            throw StreamPullErr("decryptFile", e);
          } else {
            throw e;
          }
        });
  }

  static Future<void> decryptVerify(
    String encFilePath,
    String encFileHeaders,
    String encFileKey,
    String encFileNonce,
    Uint8List parentCollectionKey, {
    int chunkLimit = -1,
  }) {
    final args = <String, dynamic>{
      "encFilePath": encFilePath,
      "encFileHeaders": encFileHeaders,
      "encFileKey": encFileKey,
      "encFileNonce": encFileNonce,
      "parentCollectionKey": parentCollectionKey,
      "chunkLimit": chunkLimit,
    };
    return _computer
        .compute(chachaVerifyFile, param: args, taskName: "decryptVerify")
        .unwrapExceptionInComputer();
  }

  static Uint8List generateKey() {
    return Sodium.cryptoSecretboxKeygen();
  }

  static Uint8List getSaltToDeriveKey() {
    return Sodium.randombytesBuf(Sodium.cryptoPwhashSaltbytes);
  }

  static Future<KeyPair> generateKeyPair() async {
    return Sodium.cryptoBoxKeypair();
  }

  static Uint8List openSealSync(
    Uint8List input,
    Uint8List publicKey,
    Uint8List secretKey,
  ) {
    return Sodium.cryptoBoxSealOpen(input, publicKey, secretKey);
  }

  static Uint8List sealSync(Uint8List input, Uint8List publicKey) {
    return Sodium.cryptoBoxSeal(input, publicKey);
  }

  static Future<DerivedKeyResult> deriveSensitiveKey(
    Uint8List password,
    Uint8List salt,
  ) async {
    final logger = Logger("pwhash");
    final int desiredStrength =
        Sodium.cryptoPwhashMemlimitSensitive *
        Sodium.cryptoPwhashOpslimitSensitive;
    // Start at 256 MiB to avoid OOM kills, then trade memory for operations
    // while keeping their product constant.
    int memLimit = Sodium.cryptoPwhashMemlimitModerate;
    final factor =
        Sodium.cryptoPwhashMemlimitSensitive ~/
        Sodium.cryptoPwhashMemlimitModerate;
    int opsLimit = Sodium.cryptoPwhashOpslimitSensitive * factor;
    if (memLimit * opsLimit != desiredStrength) {
      throw UnsupportedError(
        "unexpcted values for memLimit $memLimit and opsLimit: $opsLimit",
      );
    }

    // Keep the adaptive floor aligned with the server-side minimum accepted
    // account KDF memory limit (128 MiB), not libsodium's absolute minimum.
    const int minMemLimit = 128 * 1024 * 1024;
    Uint8List key;
    while (memLimit >= minMemLimit &&
        opsLimit <= Sodium.cryptoPwhashOpslimitMax) {
      try {
        key = await deriveKey(password, salt, memLimit, opsLimit);
        return DerivedKeyResult(key, memLimit, opsLimit);
      } catch (e, s) {
        logger.warning(
          "failed to deriveKey mem: $memLimit, ops: $opsLimit",
          e,
          s,
        );
      }
      memLimit = (memLimit / 2).round();
      opsLimit = opsLimit * 2;
    }
    throw UnsupportedError("Cannot perform this operation on this device");
  }

  // Shared-link passwords add a layer over the access token and collection key.
  static Future<DerivedKeyResult> deriveInteractiveKey(
    Uint8List password,
    Uint8List salt,
  ) async {
    final int memLimit = Sodium.cryptoPwhashMemlimitInteractive;
    final int opsLimit = Sodium.cryptoPwhashOpslimitInteractive;
    final key = await deriveKey(password, salt, memLimit, opsLimit);
    return DerivedKeyResult(key, memLimit, opsLimit);
  }

  static Future<Uint8List> deriveKey(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  ) async {
    try {
      return await _computer.compute(
        cryptoPwHash,
        param: {
          "password": password,
          "salt": salt,
          "memLimit": memLimit,
          "opsLimit": opsLimit,
        },
        taskName: "deriveKey",
      );
    } catch (e, s) {
      final String errMessage =
          'failed to deriveKey memLimit: $memLimit and '
          'opsLimit: $opsLimit';
      Logger("CryptoUtilDeriveKey").warning(errMessage, e, s);
      throw KeyDerivationError();
    }
  }

  static Future<Uint8List> deriveLoginKey(Uint8List key) async {
    try {
      final Uint8List derivedKey = await _computer.compute(
        cryptoKdfDeriveFromKey,
        param: {
          "key": key,
          "subkeyId": loginSubKeyId,
          "subkeyLen": loginSubKeyLen,
          "context": utf8.encode(loginSubKeyContext),
        },
        taskName: "deriveLoginKey",
      );
      return derivedKey.sublist(0, 16);
    } catch (e, s) {
      Logger("deriveLoginKey").severe("loginKeyDerivation failed", e, s);
      throw LoginKeyDerivationError();
    }
  }

  static Future<Uint8List> getHash(File source) {
    return _computer.compute(
      cryptoGenericHash,
      param: {"sourceFilePath": source.path},
      taskName: "fileHash",
    );
  }

  static int estimateEncryptedSize(int plainTextSize) {
    if (plainTextSize <= 0) {
      return 0;
    }

    final int chunkOverhead = Sodium.cryptoSecretstreamXchacha20poly1305Abytes;
    final int fullChunks = plainTextSize ~/ encryptionChunkSize;
    final int lastChunkSize = plainTextSize % encryptionChunkSize;

    int estimatedSize = fullChunks * (encryptionChunkSize + chunkOverhead);
    if (lastChunkSize > 0) {
      estimatedSize += lastChunkSize + chunkOverhead;
    }

    return estimatedSize;
  }

  static bool validateStreamEncryptionSizes(
    int plainTextSize,
    int cipherTextSize,
  ) {
    if (plainTextSize <= 0 || cipherTextSize <= 0) {
      return false;
    }

    final int expectedCipherTextSize = estimateEncryptedSize(plainTextSize);
    return expectedCipherTextSize == cipherTextSize;
  }
}
