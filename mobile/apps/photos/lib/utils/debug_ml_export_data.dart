import "dart:convert";
import "dart:developer" show log;
import "dart:io";

import "package:path_provider/path_provider.dart";

Future<void> encodeAndSaveData(
  dynamic nestedData,
  String fileName, [
  String? service,
]) async {
  // Convert map keys to strings if nestedData is a map
  final dataToEncode = nestedData is Map
      ? nestedData.map((key, value) => MapEntry(key.toString(), value))
      : nestedData;
  // Step 1: Serialize Your Data
  final String jsonData = jsonEncode(dataToEncode);

  // Step 2: Encode the JSON String to Base64
  // final String base64String = base64Encode(utf8.encode(jsonData));

  // Step 3 & 4: Write the Base64 String to a File and Execute the Function
  try {
    final File file = await _writeStringToFile(jsonData, fileName);
    // Success, handle the file, e.g., print the file path
    log('[$service]: File saved at ${file.path}');
  } catch (e) {
    // If an error occurs, handle it.
    log('[$service]: Error saving file: $e');
  }
}

Future<File> _writeStringToFile(String dataString, String fileName) async {
  final directory = await getExternalStorageDirectory();
  final file = File('${directory!.path}/$fileName.json');
  return file.writeAsString(dataString);
}
