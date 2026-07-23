import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

final storageUnits = ["bytes", "KB", "MB", "GB", "TB"];

String convertBytesToReadableFormat(int bytes) {
  int storageUnitIndex = 0;
  while (bytes >= 1024 && storageUnitIndex < storageUnits.length - 1) {
    storageUnitIndex++;
    bytes = (bytes / 1024).round();
  }
  return "$bytes ${storageUnits[storageUnitIndex]}";
}

(int, String) convertBytesToNumberAndUnit(int bytes) {
  int storageUnitIndex = 0;
  while (bytes >= 1024 && storageUnitIndex < storageUnits.length - 1) {
    storageUnitIndex++;
    bytes = (bytes / 1024).round();
  }
  return (bytes, storageUnits[storageUnitIndex]);
}

String formatBytes(int bytes, [int decimals = 2]) {
  if (bytes == 0) return '0 bytes';
  const k = 1024;
  final int dm = decimals < 0 ? 0 : decimals;
  final int i = (log(bytes) / log(k)).floor();
  return '${(bytes / pow(k, i)).toStringAsFixed(dm)} ${storageUnits[i]}';
}

//shows 1st decimal only if less than 10GB & omits decimal if decimal is 0
num roundBytesUsedToGBs(int usedBytes, int freeSpace) {
  const tenGBinBytes = 10737418240;
  num bytesInGB = convertBytesToGBs(usedBytes);
  if ((usedBytes >= tenGBinBytes && freeSpace >= tenGBinBytes) ||
      bytesInGB % 1 == 0) {
    bytesInGB = bytesInGB.truncate();
  }
  return bytesInGB;
}

//Eg: 0.3 GB, 11.0 GB, 532.3 GB
num convertBytesToGBs(int bytes) {
  return num.parse((bytes / (pow(1024, 3))).toStringAsFixed(1));
}

int convertBytesToAbsoluteGBs(int bytes) {
  return (bytes / pow(1024, 3)).round();
}

int convertBytesToMBs(int bytes) {
  return (bytes / pow(1024, 2)).round();
}

//Eg: 1TB, 1.3TB, 4.9TB, 3TB
num roundGBsToTBs(num sizeInGBs) {
  final num sizeInTBs = num.parse((sizeInGBs / 1000).toStringAsFixed(1));
  if (sizeInTBs % 1 == 0) {
    return sizeInTBs.truncate();
  } else {
    return sizeInTBs;
  }
}

/// Computes the MD5 hash of a file or a portion of it.
///
/// [filePath] - Path to the file
/// [start] - Optional starting byte position for partial hash computation
/// [end] - Optional ending byte position for partial hash computation
///
/// Returns base64-encoded MD5 hash suitable for HTTP Content-MD5 header.
Future<String> computeMd5(String filePath, {int? start, int? end}) async {
  final file = File(filePath);
  final output = AccumulatorSink<Digest>();
  final input = md5.startChunkedConversion(output);
  await file.openRead(start, end).forEach(input.add);
  input.close();
  return base64Encode(output.events.single.bytes);
}
