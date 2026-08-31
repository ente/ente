import 'package:flutter/services.dart';

class CountryNames {
  const CountryNames({
    required this.region,
    required this.names,
    required this.nativeNames,
  });

  final String? region;
  final Map<String, String> names;
  final Map<String, List<String>> nativeNames;

  Set<String> matchingCodes(String query) {
    final normalizedQuery = query.toLowerCase();
    return names.entries
        .where(
          (entry) =>
              entry.value.toLowerCase().contains(normalizedQuery) ||
              (nativeNames[entry.key]?.any(
                    (name) => name.toLowerCase().contains(normalizedQuery),
                  ) ??
                  false),
        )
        .map((entry) => entry.key)
        .toSet();
  }
}

class CountryNamesClient {
  static const _channel = MethodChannel(
    'io.ente.photos.platform/country_names',
  );

  static Future<CountryNames> get(
    String locale, {
    required Map<String, List<String>> nativeLocales,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('get', {
      'locale': locale,
      'nativeLocales': nativeLocales,
    });
    return CountryNames(
      region: result!['region'] as String?,
      names: (result['names'] as Map).cast<String, String>(),
      nativeNames: (result['nativeNames'] as Map).map(
        (code, names) =>
            MapEntry(code as String, (names as List).cast<String>()),
      ),
    );
  }
}
