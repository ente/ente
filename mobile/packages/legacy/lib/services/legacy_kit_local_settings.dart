import "package:shared_preferences/shared_preferences.dart";

class LegacyKitLocalSettings {
  LegacyKitLocalSettings._();

  static const _shareProgressPrefix = "legacy_kit_share_progress";

  static Future<Set<int>> getSharedPartIndexes(String kitId) async {
    final preferences = await SharedPreferences.getInstance();
    return _readSharedPartIndexes(preferences, kitId);
  }

  static Future<void> markPartShared(String kitId, int partIndex) async {
    final preferences = await SharedPreferences.getInstance();
    final sharedPartIndexes = _readSharedPartIndexes(preferences, kitId)
      ..add(partIndex);
    final sortedIndexes = sharedPartIndexes.toList()..sort();
    await preferences.setStringList(
      _key(kitId),
      sortedIndexes.map((index) => index.toString()).toList(growable: false),
    );
  }

  static Future<void> clearShareProgress(String kitId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(kitId));
  }

  static Set<int> _readSharedPartIndexes(
    SharedPreferences preferences,
    String kitId,
  ) {
    final values = preferences.getStringList(_key(kitId)) ?? const [];
    return values
        .map(int.tryParse)
        .whereType<int>()
        .where((index) => index > 0)
        .toSet();
  }

  static String _key(String kitId) => "$_shareProgressPrefix.$kitId";
}
