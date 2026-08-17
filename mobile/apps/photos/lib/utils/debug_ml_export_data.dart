import "dart:convert";
import "dart:developer" show log;
import "dart:io";

import "package:path_provider/path_provider.dart";

Future<void> encodeAndSaveData(
  dynamic nestedData,
  String fileName, [
  String? service,
]) async {
  final dataToEncode = nestedData is Map
      ? nestedData.map((key, value) => MapEntry(key.toString(), value))
      : nestedData;
  final String jsonData = jsonEncode(dataToEncode);

  try {
    final File file = await _writeStringToFile(jsonData, fileName);
    log('[$service]: File saved at ${file.path}');
  } catch (e) {
    log('[$service]: Error saving file: $e');
  }
}

Future<File> _writeStringToFile(String dataString, String fileName) async {
  final directory = await getExternalStorageDirectory();
  final file = File('${directory!.path}/$fileName.json');
  return file.writeAsString(dataString);
}
