double? parseIntOrDoubleAsDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value * 1.0;
  return null;
}

List<double> parseAsDoubleList(List<dynamic> inputList) {
  if (inputList.isEmpty) return const [];

  if (inputList is List<double>) return inputList;
  return List<double>.generate(inputList.length, (index) {
    final value = inputList[index];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    throw FormatException('Invalid type at index $index: ${value.runtimeType}');
  }, growable: false);
}

String baseUrlForLogging(String value) {
  try {
    final uri = Uri.parse(value);
    if (!uri.hasScheme || uri.host.isEmpty) return 'unknown URL';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  } catch (_) {
    return 'unknown URL';
  }
}
