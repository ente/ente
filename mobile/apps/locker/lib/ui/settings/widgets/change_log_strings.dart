import "dart:ui";

class ChangeLogStrings {
  final List<ChangeLogEntryStrings> entries;

  const ChangeLogStrings({required this.entries});

  static ChangeLogStrings forLocale(Locale locale) {
    final key = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? "${locale.languageCode}_${locale.countryCode}"
        : locale.languageCode;

    return _translations[key] ??
        _translations[locale.languageCode] ??
        _translations["en"]!;
  }

  static const Map<String, ChangeLogStrings> _translations = {
    "en": ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Image viewer",
          description:
              "Open images right in Locker. Pinch or double-tap to zoom.",
        ),
        ChangeLogEntryStrings(
          title: "New upload screen",
          description: "A fresh look for adding files to Locker.",
        ),
        ChangeLogEntryStrings(
          title: "Now in Korean",
          description: "You can now use Locker in Korean.",
        ),
      ],
    ),
  };
}

class ChangeLogEntryStrings {
  final String title;
  final String description;

  const ChangeLogEntryStrings({required this.title, required this.description});
}
