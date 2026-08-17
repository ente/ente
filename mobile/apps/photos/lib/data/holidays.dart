import "package:flutter/cupertino.dart";

class HolidayData {
  final String name;
  final int month;
  final int day;

  HolidayData(this.name, {required this.month, required this.day});
}

// Returns locale-specific holidays with fixed Gregorian dates.
List<HolidayData> getHolidays(BuildContext context) {
  final locale = Localizations.localeOf(context);
  if (localeToHolidays.containsKey(locale.toLanguageTag())) {
    return localeToHolidays[locale.toLanguageTag()]!;
  } else if (localeToHolidays.containsKey(locale.languageCode)) {
    return localeToHolidays[locale.languageCode]!;
  }
  return _defaultHolidays;
}

List<HolidayData> _defaultHolidays = [
  HolidayData('New Year', month: 1, day: 1),
  HolidayData('Epiphany', month: 1, day: 6),
  HolidayData('Pongal', month: 1, day: 14),
  HolidayData('Makar Sankranthi', month: 1, day: 14),
  HolidayData('Valentine\'s Day', month: 2, day: 14),
  HolidayData('Nowruz', month: 3, day: 21),
  HolidayData('Walpurgis Night', month: 4, day: 30),
  HolidayData('Vappu', month: 4, day: 30),
  HolidayData('May Day', month: 5, day: 1),
  HolidayData('Midsummer\'s Eve', month: 6, day: 24),
  HolidayData('Midsummer Day', month: 6, day: 25),
  HolidayData('Halloween', month: 10, day: 31),
  HolidayData('Christmas Eve', month: 12, day: 24),
  HolidayData('Christmas', month: 12, day: 25),
  HolidayData('Boxing Day', month: 12, day: 26),
  HolidayData('New Year\'s Eve', month: 12, day: 31),
];
Map<String, List<HolidayData>> localeToHolidays = {
  'it': [
    HolidayData('Capodanno', month: 1, day: 1),
    HolidayData('Epifania', month: 1, day: 6),
    HolidayData('San Valentino', month: 2, day: 14),
    HolidayData('Festa della Liberazione', month: 4, day: 25),
    HolidayData('Primo Maggio', month: 5, day: 1),
    HolidayData('Festa della Repubblica', month: 6, day: 2),
    HolidayData('Ferragosto', month: 8, day: 15),
    HolidayData('Halloween', month: 10, day: 31),
    HolidayData('Ognissanti', month: 11, day: 1),
    HolidayData('Immacolata Concezione', month: 12, day: 8),
    HolidayData('Natale', month: 12, day: 25),
    HolidayData('Vigilia di Capodanno', month: 12, day: 31),
  ],
  'fr': [
    HolidayData('Jour de l\'An', month: 1, day: 1),
    HolidayData('Fête du Travail', month: 5, day: 1),
    HolidayData('Fête Nationale', month: 7, day: 14),
    HolidayData('Assomption', month: 8, day: 15),
    HolidayData('Halloween', month: 10, day: 31),
    HolidayData('Toussaint', month: 11, day: 1),
    HolidayData('Jour de l\'Armistice', month: 11, day: 11),
    HolidayData('Noël', month: 12, day: 25),
    HolidayData('Lendemain de Noël', month: 12, day: 26),
    HolidayData('Saint-Sylvestre', month: 12, day: 31),
  ],
  'de': [
    HolidayData('Neujahrstag', month: 1, day: 1),
    HolidayData('Valentinstag', month: 2, day: 14),
    HolidayData('Tag der Arbeit', month: 5, day: 1),
    HolidayData('Tag der Deutschen Einheit', month: 10, day: 3),
    HolidayData('Halloween', month: 10, day: 31),
    HolidayData('Erster Weihnachtstag', month: 12, day: 25),
    HolidayData('Zweiter Weihnachtstag', month: 12, day: 26),
    HolidayData('Silvester', month: 12, day: 31),
  ],
  'nl': [
    HolidayData('Nieuwjaarsdag', month: 1, day: 1),
    HolidayData('Valentijnsdag', month: 2, day: 14),
    HolidayData('Koningsdag', month: 4, day: 27),
    HolidayData('Bevrijdingsdag', month: 5, day: 5),
    HolidayData('Halloween', month: 10, day: 31),
    HolidayData('Sinterklaas', month: 12, day: 5),
    HolidayData('Eerste Kerstdag', month: 12, day: 25),
    HolidayData('Tweede Kerstdag', month: 12, day: 26),
    HolidayData('Oudejaarsdag', month: 12, day: 31),
  ],
  'es': [
    HolidayData('Año Nuevo', month: 1, day: 1),
    HolidayData('San Valentín', month: 2, day: 14),
    HolidayData('Día del Trabajador', month: 5, day: 1),
    HolidayData('Día de la Hispanidad', month: 10, day: 12),
    HolidayData('Halloween', month: 10, day: 31),
    HolidayData('Día de Todos los Santos', month: 11, day: 1),
    HolidayData('Día de la Constitución', month: 12, day: 6),
    HolidayData('La Inmaculada Concepción', month: 12, day: 8),
    HolidayData('Navidad', month: 12, day: 25),
    HolidayData('Nochevieja', month: 12, day: 31),
  ],
};
