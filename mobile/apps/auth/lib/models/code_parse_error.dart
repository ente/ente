import 'dart:convert';

const Set<String> _supportedOtpHosts = {'totp', 'hotp', 'steam'};

class CodeParseError implements Exception {
  const CodeParseError._(this.message);

  final String message;

  factory CodeParseError.from({
    required Object error,
    required String storedRawData,
  }) {
    return CodeParseError._(_rootCause(error, storedRawData));
  }

  @override
  String toString() => message;
}

String _rootCause(Object error, String storedRawData) {
  final decodedStoredData = _tryDecodeJson(storedRawData);

  if (decodedStoredData is String) {
    return _rootCauseFromOtpUrl(error, decodedStoredData) ??
        'OTP URL could not be parsed';
  }
  if (decodedStoredData is Map) {
    final rawData = decodedStoredData['rawData'];
    if (rawData is! String || rawData.isEmpty) {
      return 'Stored code export is missing rawData';
    }
    final otpUrlRootCause = _rootCauseFromOtpUrl(error, rawData);
    if (otpUrlRootCause != null) {
      return otpUrlRootCause;
    }
    if (decodedStoredData['display'] != null) {
      return 'Code display metadata is invalid';
    }
    return 'Stored code data could not be parsed';
  }

  if (error is FormatException) {
    return 'Stored code data is not valid JSON';
  }
  return 'Stored code data is not a supported format';
}

String? _rootCauseFromOtpUrl(Object error, String rawData) {
  if (!rawData.startsWith('otpauth://')) {
    return 'Stored code data is not an OTP URL';
  }

  final uri = Uri.tryParse(rawData);
  if (uri == null) {
    return 'OTP URL is malformed';
  }
  if (!_supportedOtpHosts.contains(uri.host)) {
    // This message is shown in UI and logged, so keep it limited to Uri.host.
    // The raw path/query can contain labels, issuers, or OTP secrets.
    final host = uri.host.isEmpty ? 'unknown' : uri.host;
    return 'Unsupported OTP type: $host';
  }
  final queryParameters = _tryGetQueryParameters(uri);
  if (queryParameters == null) {
    return 'OTP URL is malformed';
  }
  if ((queryParameters['secret'] ?? '').isEmpty) {
    return 'OTP URL is missing a secret';
  }
  if (_hasInvalidCodeDisplay(queryParameters)) {
    return 'Code display metadata is invalid';
  }
  if (error is FormatException) {
    return 'OTP URL is malformed';
  }
  return null;
}

bool _hasInvalidCodeDisplay(Map<String, String> queryParameters) {
  final codeDisplay = queryParameters['codeDisplay'];
  if (codeDisplay == null) {
    return false;
  }
  try {
    jsonDecode(codeDisplay.replaceAll('%2C', ','));
    return false;
  } catch (_) {
    return true;
  }
}

Map<String, String>? _tryGetQueryParameters(Uri uri) {
  try {
    return uri.queryParameters;
  } catch (_) {
    return null;
  }
}

Object? _tryDecodeJson(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}
