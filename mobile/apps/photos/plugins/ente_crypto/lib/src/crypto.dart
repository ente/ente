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
// 17 bytes of overhead per chunk
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

// Returns the hash for a given file
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

// chachaEncryptFileV2 does chucked encryption similar to chachaEncryptFile.
// This implementation is refactored to simplify the logic to make it easier to
// maintain and reason about.
// Rolling out this version 2 in phases to ensure stability
Future<FileEncryptResult> chachaEncryptFileV2(Map<String, dynamic> args) async {
  final encryptionStartTime = DateTime.now().millisecondsSinceEpoch;
  final logger = Logger("chachaEncryptFileV2");
  final sourceFile = File(args["sourceFilePath"]);
  final destinationFile = File(args["destinationFilePath"]);
  if (destinationFile.existsSync() && (destinationFile.lengthSync() > 0)) {
    logger.warning("Destination file already exists and is not empty");
    throw Exception("Destination file already exists and is not empty");
  }
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
    final bool isLastChunk =
        bytesRead + encryptionChunkSize >= sourceFileLength;
    final int chunkSize = isLastChunk
        ? (sourceFileLength - bytesRead)
        : encryptionChunkSize;

    // Read until we have the full chunk size (or reach EOF)
    final buffer = BytesBuilder();
    while (buffer.length < chunkSize) {
      final remainingBytes = chunkSize - buffer.length;
      final readBytes = await inputFile.read(remainingBytes);
      if (readBytes.isEmpty) break; // EOF reached unexpectedly
      buffer.add(readBytes);
    }

    final bufferBytes = buffer.toBytes();
    bytesRead += bufferBytes.length;
    if (bufferBytes.length != chunkSize) {
      throw Exception(
        "V2 $kPartialReadErrorTag $chunkSize bytes, but got ${bufferBytes.length} bytes, sourceFileLength: $sourceFileLength",
      );
    }
    // Set final tag only after confirming we've read all expected data
    if (isLastChunk) {
      if (bytesRead == sourceFileLength) {
        tag = Sodium.cryptoSecretstreamXchacha20poly1305TagFinal;
      } else {
        throw Exception(
          "Expected $sourceFileLength bytes, but read $bytesRead bytes",
        );
      }
    }
    final encryptedData = Sodium.cryptoSecretstreamXchacha20poly1305Push(
      initPushResult.state,
      bufferBytes,
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

// Encrypts a given file, in chunks of encryptionChunkSize
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

// Encrypts a file with MD5 calculation and real-time verification
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

  // Use openSync for simpler, predictable chunk reading
  final inputFile = sourceFile.openSync(mode: FileMode.read);

  // Use streaming write
  final outSink = destinationFile.openWrite(mode: FileMode.writeOnly);

  final key = args["key"] ?? Sodium.cryptoSecretstreamXchacha20poly1305Keygen();
  final initPushResult = Sodium.cryptoSecretstreamXchacha20poly1305InitPush(
    key,
  );

  // Initialize verification state
  final verifyPullState = Sodium.cryptoSecretstreamXchacha20poly1305InitPull(
    initPushResult.header,
    key,
  );

  // MD5 setup
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

      // Encrypt
      final encryptedData = Sodium.cryptoSecretstreamXchacha20poly1305Push(
        initPushResult.state,
        buffer,
        null,
        tag,
      );

      // Verify with optimized comparison
      try {
        final pullResult = Sodium.cryptoSecretstreamXchacha20poly1305Pull(
          verifyPullState,
          encryptedData,
          null,
        );

        // Use fast comparison
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

      // Handle MD5 calculation and disk writes
      totalEncryptedBytes += encryptedData.length;

      if (multiPartChunkSizeInBytes == null) {
        // Single-part: stream MD5 and write directly
        fullMd5Sink!.add(encryptedData);
        outSink.add(encryptedData);
      } else {
        // Multi-part: buffer data and flush at exact part boundaries
        partBuffer.add(encryptedData);

        final bool isLastChunk =
            tag == Sodium.cryptoSecretstreamXchacha20poly1305TagFinal;

        // Flush complete parts from buffer
        while (partBuffer.length >= multiPartChunkSizeInBytes) {
          final partBytes = partBuffer.toBytes().sublist(
            0,
            multiPartChunkSizeInBytes,
          );

          // Calculate MD5 for this part
          partMd5Sink!.add(partBytes);
          partMd5Sink.close();
          final digest = partAccumulator!.events.single;
          partMd5s.add(base64.encode(digest.bytes));

          logger.info(
            "Part ${partMd5s.length}: $multiPartChunkSizeInBytes bytes",
          );

          // Write to disk
          outSink.add(partBytes);

          // Keep remaining bytes for next part
          final remaining = partBuffer.toBytes().sublist(
            multiPartChunkSizeInBytes,
          );
          partBuffer.clear();
          partBuffer.add(remaining);

          // Start new MD5 for next part (if not last)
          if (!isLastChunk || partBuffer.isNotEmpty) {
            partAccumulator = AccumulatorSink<Digest>();
            partMd5Sink = md5.startChunkedConversion(partAccumulator);
          }
        }

        // Handle last chunk (remaining data < partSize)
        if (isLastChunk && partBuffer.isNotEmpty) {
          final lastPartBytes = partBuffer.toBytes();

          // Calculate MD5 for last part
          partMd5Sink!.add(lastPartBytes);
          partMd5Sink.close();
          final digest = partAccumulator!.events.single;
          partMd5s.add(base64.encode(digest.bytes));

          // Write to disk
          outSink.add(lastPartBytes);
          partBuffer.clear();
        }
      }
    }

    await inputFile.close();

    // Finalize MD5
    String? finalFileMd5;
    if (multiPartChunkSizeInBytes == null && fullMd5Sink != null) {
      fullMd5Sink.close();
      final digest = fullAccumulator!.events.single;
      finalFileMd5 = base64.encode(digest.bytes);
      logger.info("File MD5: $finalFileMd5");
    }

    // Ensure all data is written
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

// Fast equality check for Uint8List
bool _uint8listEquals(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  final len = a.length;
  int i = 0;

  // Compare 8 bytes at a time for speed
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

  // Remaining bytes
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
    // Step 1: Decrypt the file key using collection key
    final encryptedKey = Sodium.base642bin(args["encFileKey"]);
    final nonce = Sodium.base642bin(args["encFileNonce"]);
    final fileKey = Sodium.cryptoSecretboxOpenEasy(
      encryptedKey,
      nonce,
      args["parentCollectionKey"],
    );

    // Step 2: Verify file can be decrypted
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
      // Initialize decryption
      final pullState = Sodium.cryptoSecretstreamXchacha20poly1305InitPull(
        header,
        fileKey,
      );

      // Determine number of chunks to verify
      // -1 means verify entire file
      final int chunkLimit = args["chunkLimit"] ?? 1;
      final bool verifyEntireFile = chunkLimit == -1;
      final chunksToVerify = verifyEntireFile
          ? 999999999
          : chunkLimit; // Large number for entire file

      var bytesRead = 0;
      var chunksVerified = 0;

      while (chunksVerified < chunksToVerify) {
        // Calculate chunk size
        final remainingBytes = encFileLength - bytesRead;
        if (remainingBytes <= 0) {
          break; // No more data to verify
        }

        final chunkSize = remainingBytes < decryptionChunkSize
            ? remainingBytes
            : decryptionChunkSize;

        // Read chunk
        final buffer = await inputFile.read(chunkSize);
        if (buffer.isEmpty) {
          break; // End of file
        }

        bytesRead += buffer.length;
        chunksVerified++;

        // Attempt to decrypt - this will throw if decryption fails
        try {
          final pullResult = Sodium.cryptoSecretstreamXchacha20poly1305Pull(
            pullState,
            buffer,
            null,
          );

          // If this was the final tag, we've verified the entire file
          if (pullResult.tag ==
              Sodium.cryptoSecretstreamXchacha20poly1305TagFinal) {
            break;
          }
        } catch (e) {
          // Crypto error during pull operation
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
    // If it's already tagged, just rethrow
    if (e.toString().contains(kVerificationErrorTag)) {
      rethrow;
    }
    // For key decryption errors
    if (e.toString().contains("crypto_secretbox_open_easy")) {
      throw Exception(
        "$kVerificationErrorTag: Failed to decrypt file key. Invalid collection key or corrupted key data.",
      );
    }
    // For other unexpected errors
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

  // Encrypts the given source, with the given key and a randomly generated
  // nonce, using XSalsa20 (w Poly1305 MAC).
  // This function runs on the same thread as the caller, so should be used only
  // for small amounts of data where thread switching can result in a degraded
  // user experience
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

  // Decrypts the given cipher, with the given key and nonce using XSalsa20
  // (w Poly1305 MAC).
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

  // Decrypts the given cipher, with the given key and nonce using XSalsa20
  // (w Poly1305 MAC).
  // This function runs on the same thread as the caller, so should be used only
  // for small amounts of data where thread switching can result in a degraded
  // user experience
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

  // Encrypts the given source, with the given key and a randomly generated
  // nonce, using XChaCha20 (w Poly1305 MAC).
  // This function runs on the isolate pool held by `_computer`.
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

  // Decrypts the given source, with the given key and header using XChaCha20
  // (w Poly1305 MAC).
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

  // Encrypts the file at sourceFilePath, with the key (if provided) and a
  // randomly generated nonce using XChaCha20 (w Poly1305 MAC), and writes it
  // to the destinationFilePath.
  // If a key is not provided, one is generated and returned.
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

  // Encrypts the file at sourceFilePath, with the key (if provided) and a
  // randomly generated nonce using XChaCha20 (w Poly1305 MAC), and writes it
  // to the destinationFilePath.
  // If a key is not provided, one is generated and returned.
  static Future<FileEncryptResult> encryptFileV2(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
  }) {
    final args = <String, dynamic>{};
    args["sourceFilePath"] = sourceFilePath;
    args["destinationFilePath"] = destinationFilePath;
    args["key"] = key;
    return _computer.compute(
      chachaEncryptFileV2,
      param: args,
      taskName: "encryptFileV2",
    );
  }

  // Encrypts the file with MD5 calculation and real-time verification
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

  // Decrypts the file at sourceFilePath, with the given key and header using
  // XChaCha20 (w Poly1305 MAC), and writes it to the destinationFilePath.
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

  // Generates and returns a 256-bit key.
  static Uint8List generateKey() {
    return Sodium.cryptoSecretboxKeygen();
  }

  // Generates and returns a random byte buffer of length
  // crypto_pwhash_SALTBYTES (16)
  static Uint8List getSaltToDeriveKey() {
    return Sodium.randombytesBuf(Sodium.cryptoPwhashSaltbytes);
  }

  // Generates and returns a secret key and the corresponding public key.
  static Future<KeyPair> generateKeyPair() async {
    return Sodium.cryptoBoxKeypair();
  }

  // Decrypts the input using the given publicKey-secretKey pair
  static Uint8List openSealSync(
    Uint8List input,
    Uint8List publicKey,
    Uint8List secretKey,
  ) {
    return Sodium.cryptoBoxSealOpen(input, publicKey, secretKey);
  }

  // Encrypts the input using the given publicKey
  static Uint8List sealSync(Uint8List input, Uint8List publicKey) {
    return Sodium.cryptoBoxSeal(input, publicKey);
  }

  // Derives a key for a given password and salt using Argon2id, v1.3.
  // The function first attempts to derive a key with both memLimit and opsLimit
  // set to their Sensitive variants.
  // If this fails, say on a device with insufficient RAM, we retry by halving
  // the memLimit and doubling the opsLimit, while ensuring that we stay within
  // the min and max limits for both parameters.
  // At all points, we ensure that the product of these two variables (the area
  // under the graph that determines the amount of work required) is a constant.
  static Future<DerivedKeyResult> deriveSensitiveKey(
    Uint8List password,
    Uint8List salt,
  ) async {
    final logger = Logger("pwhash");
    final int desiredStrength =
        Sodium.cryptoPwhashMemlimitSensitive *
        Sodium.cryptoPwhashOpslimitSensitive;
    // When sensitive memLimit (1 GB) is used, on low spec device the OS might
    // kill the app with OOM. To avoid that, start with 256 MB and
    // corresponding ops limit (16).
    // This ensures that the product of these two variables
    // (the area under the graph that determines the amount of work required)
    // stays the same
    // SODIUM_CRYPTO_PWHASH_MEMLIMIT_SENSITIVE: 1073741824
    // SODIUM_CRYPTO_PWHASH_MEMLIMIT_MODERATE: 268435456
    // SODIUM_CRYPTO_PWHASH_OPSLIMIT_SENSITIVE: 4
    int memLimit = Sodium.cryptoPwhashMemlimitModerate;
    final factor =
        Sodium.cryptoPwhashMemlimitSensitive ~/
        Sodium.cryptoPwhashMemlimitModerate; // = 4
    int opsLimit = Sodium.cryptoPwhashOpslimitSensitive * factor; // = 16
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

  // Derives a key for the given password and salt, using Argon2id, v1.3
  // with memory and ops limit hardcoded to their Interactive variants
  // NOTE: This is only used while setting passwords for shared links, as an
  // extra layer of authentication (atop the access token and collection key).
  // More details @ https://ente.com/blog/building-shareable-links/
  static Future<DerivedKeyResult> deriveInteractiveKey(
    Uint8List password,
    Uint8List salt,
  ) async {
    final int memLimit = Sodium.cryptoPwhashMemlimitInteractive;
    final int opsLimit = Sodium.cryptoPwhashOpslimitInteractive;
    final key = await deriveKey(password, salt, memLimit, opsLimit);
    return DerivedKeyResult(key, memLimit, opsLimit);
  }

  // Derives a key for a given password, salt, memLimit and opsLimit using
  // Argon2id, v1.3.
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

  // derives a Login key as subKey from the given key by applying KDF
  // (Key Derivation Function) with the `loginSubKeyId` and
  // `loginSubKeyLen` and `loginSubKeyContext` as context
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
      // return the first 16 bytes of the derived key
      return derivedKey.sublist(0, 16);
    } catch (e, s) {
      Logger("deriveLoginKey").severe("loginKeyDerivation failed", e, s);
      throw LoginKeyDerivationError();
    }
  }

  // Computes and returns the hash of the source file
  static Future<Uint8List> getHash(File source) {
    return _computer.compute(
      cryptoGenericHash,
      param: {"sourceFilePath": source.path},
      taskName: "fileHash",
    );
  }

  /// Estimates the encrypted size for a given plaintext size.
  /// Takes into account the ChaCha20-Poly1305 overhead per chunk.
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

  /// Validates that the plaintext and ciphertext sizes match for streaming encryption.
  /// Returns true if the sizes are valid for chunked ChaCha20-Poly1305 encryption.
  ///
  /// Each chunk adds 17 bytes (Sodium.cryptoSecretstreamXchacha20poly1305Abytes) overhead.
  /// For a 4MB chunk size, the encrypted size is 4MB + 17 bytes per chunk.
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
