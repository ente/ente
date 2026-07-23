import "dart:convert" show utf8;
import "dart:developer" show log;
import "dart:io";

import "package:computer/computer.dart";
import "package:logging/logging.dart";

final _computer = Computer.shared();

final _logger = Logger("CacheUtil");

/// Writes data to a JSON file at the specified path using the provided method, inside computer.
/// The method should convert the data to a JSON string.
/// The JSON string is then UTF-8 encoded and written to the file.
Future<void> writeToJsonFile<P>(
  String filePath,
  P data,
  String Function(P) toJsonString,
) async {
  final args = {
    "filePath": filePath,
    "data": data,
    "toJsonString": toJsonString,
  };
  await _computer.compute<Map<String, dynamic>, void>(
    _writeToJsonFile<P>,
    param: args,
    taskName: "writeToJsonFile",
  );
}

Future<void> _writeToJsonFile<P>(Map<String, dynamic> args) async {
  try {
    final file = File(args["filePath"] as String);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    final toJsonStringMethod = args["toJsonString"] as String Function(P);
    final jsonString = toJsonStringMethod(args["data"] as P);
    final encodedData = utf8.encode(jsonString);
    await file.writeAsBytes(encodedData);
  } catch (e, s) {
    log("Error writing to JSON file with UTF-8 encoding, $e, \n $s");
  }
}

/// Reads a JSON file from the specified path using the provided method, inside computer.
/// The method should decode the JSON string into an object.
/// The JSON string is expected to be UTF-8 encoded.
Future<P?> decodeJsonFile<P>(
  String filePath,
  P Function(String) jsonDecodeMethod,
) async {
  final args = {"filePath": filePath, "jsonDecode": jsonDecodeMethod};
  final cache = await _computer.compute<Map<String, dynamic>, P?>(
    _decodeJsonFile<P>,
    param: args,
    taskName: "decodeJsonFile",
  );
  if (cache == null) {
    _logger.warning("Failed to decode JSON file at $filePath");
  } else {
    _logger.info("Successfully decoded JSON file at $filePath");
  }
  return cache;
}

Future<P?> _decodeJsonFile<P>(Map<String, dynamic> args) async {
  final file = File(args["filePath"] as String);
  if (!file.existsSync()) {
    log("File does not exist: ${args["filePath"]}");
    return null;
  }
  try {
    final bytes = await file.readAsBytes();
    final jsonDecodeMethod = args["jsonDecode"] as P Function(String);
    P decodedData;
    try {
      final jsonString = utf8.decode(bytes);
      decodedData = jsonDecodeMethod(jsonString);
      log("Successfully decoded JSON file as UTF-8");
    } catch (e, s) {
      log("Failed to decode bytes as UTF-8, trying UTF-16 $e \n $s");
      final jsonString = String.fromCharCodes(
        bytes,
      ); // Fallback to UTF-16 decoding
      decodedData = jsonDecodeMethod(jsonString);
      log("Successfully decoded JSON file as UTF-16");
    }
    return decodedData;
  } catch (e, s) {
    log("Error decoding JSON file, deleting this cache $e, \n $s");
    await file.delete();
    return null;
  }
}
