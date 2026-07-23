import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/ui/utils/icon_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('simple icon registry entries resolve to bundled SVG assets', () {
    final missingAssets = <String>[];
    final registry =
        json.decode(
              File(
                'assets/simple-icons/_data/simple-icons.json',
              ).readAsStringSync(),
            )
            as List<dynamic>;

    for (final icon in registry.cast<Map<String, dynamic>>()) {
      final title = icon['title'].toString().replaceAll(' ', '').toLowerCase();
      final slug = icon['slug']?.toString();
      final assetPath =
          'assets/simple-icons/icons/${simpleIconAssetStem(title, slug)}.svg';
      final asset = File(assetPath);
      if (!asset.existsSync()) {
        missingAssets.add(assetPath);
      } else if (asset.lengthSync() == 0) {
        missingAssets.add('$assetPath is empty');
      }
    }

    expect(missingAssets, isEmpty);
  });

  test('custom icon registry entries resolve to bundled SVG assets', () {
    final missingAssets = <String>[];
    final registry =
        json.decode(
              File(
                'assets/custom-icons/_data/custom-icons.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    for (final icon in (registry['icons'] as List<dynamic>).cast<Map>()) {
      final title = icon['title'].toString();
      final titleKey = title.replaceAll(' ', '').toLowerCase();
      final slug = icon['slug']?.toString();
      final canonicalPath = 'assets/custom-icons/icons/${slug ?? titleKey}.svg';
      _expectAssetExists(canonicalPath, missingAssets);

      for (final altName
          in (icon['altNames'] as List<dynamic>? ?? const <dynamic>[])) {
        final altPath = 'assets/custom-icons/icons/${slug ?? titleKey}.svg';
        _expectAssetExists('$altPath for alias $altName', missingAssets);
      }
    }

    expect(missingAssets, isEmpty);
  });
}

void _expectAssetExists(String assetPath, List<String> missingAssets) {
  final actualPath = assetPath.split(' for alias ').first;
  final asset = File(actualPath);
  if (!asset.existsSync()) {
    missingAssets.add(assetPath);
  } else if (asset.lengthSync() == 0) {
    missingAssets.add('$assetPath is empty');
  }
}
