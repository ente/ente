import 'dart:convert';

import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/models/all_icon_data.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:logging/logging.dart';

class IconUtils {
  IconUtils._privateConstructor();

  static final IconUtils instance = IconUtils._privateConstructor();

  // Map of icon-title to the color code in HEX
  final Map<String, SimpleIconData> _simpleIcons = {};
  final Map<String, CustomIconData> _customIcons = {};
  // Map of icon-color to its luminance
  final Map<Color, double> _colorLuminance = {};
  final List<String> _titleSplitCharacters = ['(', '.'];

  Future<void> init() async {
    await _loadJson();
  }

  Map<String, AllIconData> getAllIcons() {
    try {
      Set<String> processedIconPaths = {};
      final allIcons = <String, AllIconData>{};

      final simpleIterator = _simpleIcons.entries.iterator;
      final customIterator = _customIcons.entries.iterator;

      var simpleEntry = simpleIterator.moveNext()
          ? simpleIterator.current
          : null;
      var customEntry = customIterator.moveNext()
          ? customIterator.current
          : null;

      String simpleIconPath, customIconPath;

      while (simpleEntry != null && customEntry != null) {
        if (simpleEntry.key.compareTo(customEntry.key) <= 0) {
          simpleIconPath =
              "assets/simple-icons/icons/${simpleIconAssetStem(simpleEntry.key, simpleEntry.value.slug)}.svg";
          if (!processedIconPaths.contains(simpleIconPath)) {
            allIcons[simpleEntry.key] = AllIconData(
              title: simpleEntry.key,
              type: IconType.simpleIcon,
              color: simpleEntry.value.color,
              slug: simpleEntry.value.slug,
            );
            processedIconPaths.add(simpleIconPath);
          }
          simpleEntry = simpleIterator.moveNext()
              ? simpleIterator.current
              : null;
        } else {
          customIconPath =
              "assets/custom-icons/icons/${customEntry.value.slug ?? customEntry.key}.svg";

          if (!processedIconPaths.contains(customIconPath)) {
            allIcons[customEntry.key] = AllIconData(
              title: customEntry.key,
              type: IconType.customIcon,
              color: customEntry.value.color,
              slug: customEntry.value.slug,
            );
            processedIconPaths.add(customIconPath);
          }
          customEntry = customIterator.moveNext()
              ? customIterator.current
              : null;
        }
      }

      while (simpleEntry != null) {
        simpleIconPath =
            "assets/simple-icons/icons/${simpleIconAssetStem(simpleEntry.key, simpleEntry.value.slug)}.svg";

        if (!processedIconPaths.contains(simpleIconPath)) {
          allIcons[simpleEntry.key] = AllIconData(
            title: simpleEntry.key,
            type: IconType.simpleIcon,
            color: simpleEntry.value.color,
            slug: simpleEntry.value.slug,
          );
          processedIconPaths.add(simpleIconPath);
        }
        simpleEntry = simpleIterator.moveNext() ? simpleIterator.current : null;
      }

      while (customEntry != null) {
        customIconPath =
            "assets/custom-icons/icons/${customEntry.value.slug ?? customEntry.key}.svg";

        if (!processedIconPaths.contains(customIconPath)) {
          allIcons[customEntry.key] = AllIconData(
            title: customEntry.key,
            type: IconType.customIcon,
            color: customEntry.value.color,
            slug: customEntry.value.slug,
          );
          processedIconPaths.add(customIconPath);
        }
        customEntry = customIterator.moveNext() ? customIterator.current : null;
      }

      return allIcons;
    } catch (e, s) {
      Logger("IconUtils").severe("Failed to get all icons", e, s);
      return {};
    }
  }

  Widget getIcon(BuildContext context, String provider, {double width = 24}) {
    try {
      final providerTitle = _getProviderTitle(provider);
      final List<String> titlesList = [providerTitle];
      titlesList.addAll(
        _titleSplitCharacters
            .where((char) => providerTitle.contains(char))
            .map((char) => providerTitle.split(char)[0]),
      );
      for (final title in titlesList) {
        if (_customIcons.containsKey(title)) {
          return getSVGIcon(
            "assets/custom-icons/icons/${_customIcons[title]!.slug ?? title}.svg",
            title,
            _customIcons[title]!.color,
            width,
            context,
          );
        } else if (_simpleIcons.containsKey(title)) {
          final simpleIconPath = simpleIconAssetStem(
            title,
            _simpleIcons[title]!.slug,
          );
          return getSVGIcon(
            "assets/simple-icons/icons/$simpleIconPath.svg",
            title,
            _simpleIcons[title]!.color,
            width,
            context,
          );
        }
      }
      if (providerTitle.isNotEmpty) {
        return _fallbackAvatar(provider, width, context);
      } else {
        return const SizedBox.shrink();
      }
    } catch (e, s) {
      Logger(
        "IconUtils",
      ).warning("Failed to get icon for provider '$provider'", e, s);
      return _fallbackAvatar(provider, width, context);
    }
  }

  Widget getSVGIcon(
    String path,
    String title,
    String? color,
    double width,
    BuildContext context,
  ) {
    final iconColor = _getAdaptiveColor(color, context);
    try {
      return SvgPicture.asset(
        path,
        width: width,
        semanticsLabel: title,
        colorFilter: iconColor != null
            ? ColorFilter.mode(iconColor, BlendMode.srcIn)
            : null,
        errorBuilder: (context, error, stackTrace) {
          Logger(
            "IconUtils",
          ).warning("Failed to load icon $path", error, stackTrace);
          return _fallbackAvatar(title, width, context);
        },
      );
    } catch (e, s) {
      Logger(
        "IconUtils",
      ).warning("Failed to create SVG icon for '$title' at path '$path'", e, s);
      return _fallbackAvatar(title, width, context);
    }
  }

  Widget _fallbackAvatar(String provider, double width, BuildContext context) {
    final providerTitle = _getProviderTitle(provider);
    if (providerTitle.isEmpty) return const SizedBox.shrink();
    final bool showLargeIcon = width > 24;
    return CircleAvatar(
      radius: width / 2,
      backgroundColor:
          getEnteColorScheme(context).avatarColors[providerTitle.hashCode %
              getEnteColorScheme(context).avatarColors.length],
      child: Text(
        providerTitle.toUpperCase()[0],
        style: showLargeIcon
            ? getEnteTextTheme(
                context,
              ).h3Bold.copyWith(color: Colors.white, fontSize: width * 0.6)
            : getEnteTextTheme(
                context,
              ).body.copyWith(color: Colors.white, fontSize: width * 0.6),
      ),
    );
  }

  Color? _getAdaptiveColor(String? hexColor, BuildContext context) {
    if (hexColor == null) return null;
    final theme = Theme.of(context).brightness;
    final color = Color(int.parse("0xFF$hexColor"));
    // Color is close to neutral-grey and it's too light or dark for theme
    if (_isCloseToNeutralGrey(color) &&
        ((theme == Brightness.light && _getColorLuminance(color) > 0.70) ||
            (theme == Brightness.dark && _getColorLuminance(color) < 0.05))) {
      return Theme.of(context).colorScheme.iconColor;
    }
    return color;
  }

  double _getColorLuminance(Color color) {
    return _colorLuminance.putIfAbsent(color, () => color.computeLuminance());
  }

  bool _isCloseToNeutralGrey(Color color, {double tolerance = 3}) {
    final red = (color.r * 255.0).round() & 0xff;
    final green = (color.g * 255.0).round() & 0xff;
    final blue = (color.b * 255.0).round() & 0xff;
    return (red - green).abs() <= tolerance &&
        (green - blue).abs() <= tolerance &&
        (blue - red).abs() <= tolerance;
  }

  Future<void> _loadJson() async {
    try {
      final simpleIconData = await rootBundle.loadString(
        'assets/simple-icons/_data/simple-icons.json',
      );
      final simpleIcons = json.decode(simpleIconData);
      for (final icon in simpleIcons) {
        _simpleIcons[icon["title"]
            .toString()
            .replaceAll(' ', '')
            .toLowerCase()] = SimpleIconData(
          icon["slug"],
          icon["hex"],
        );
      }
      final customIconData = await rootBundle.loadString(
        'assets/custom-icons/_data/custom-icons.json',
      );
      final customIcons = json.decode(customIconData);
      for (final icon in customIcons["icons"]) {
        final titleKey = _getProviderTitle(icon["title"].toString());
        _customIcons[titleKey] = CustomIconData(icon["slug"], icon["hex"]);
        if (icon["altNames"] != null) {
          for (final name in icon["altNames"]) {
            _customIcons[name.toString().replaceAll(' ', '').toLowerCase()] =
                CustomIconData(icon["slug"] ?? titleKey, icon["hex"]);
          }
        }
      }
    } catch (e, s) {
      Logger("IconUtils").severe("Error loading icons", e, s);
      if (kDebugMode) {
        rethrow;
      }
    }
  }

  String _getProviderTitle(String provider) {
    return provider.replaceAll(' ', '').toLowerCase();
  }
}

class CustomIconData {
  final String? slug;
  final String? color;

  CustomIconData(this.slug, this.color);
}

class SimpleIconData {
  final String? slug;
  final String? color;

  SimpleIconData(this.slug, this.color);
}

final charMap = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
  'ř': 'r',
  'š': 's',
  'ż': 'z',
  '.': 'dot',
  '-': '',
  '&': 'and',
  '+': 'plus',
  ':': '',
  "'": '',
  '/': '',
  '!': '',
  '_': '',
  '°': '',
};
String normalizeSimpleIconName(String input) {
  final buffer = StringBuffer();
  for (var char in input.characters) {
    buffer.write(charMap[char] ?? char);
  }
  return buffer.toString().trim();
}

String simpleIconAssetStem(String title, String? slug) {
  return slug ?? normalizeSimpleIconName(title);
}
