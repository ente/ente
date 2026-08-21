import 'package:photos/services/date_parse_service.dart';
import 'package:test/test.dart';

void main() {
  final parse = DateParseService.instance.parse;

  group('relative dates', () {
    for (final (query, offset) in [
      ('today', 0),
      ('tomorrow', 1),
      ('yesterday', -1),
    ]) {
      test(query, () {
        final date = DateTime.now().add(Duration(days: offset));
        expect(
          parse(query),
          PartialDate(day: date.day, month: date.month, year: date.year),
        );
      });
    }
  });

  group('fixed dates', () {
    for (final (query, expected) in const [
      ('February 2025', PartialDate(month: 2, year: 2025)),
      ('Feb 2025', PartialDate(month: 2, year: 2025)),
      ('03-2024', PartialDate(month: 3, year: 2024)),
      ('03/2025', PartialDate(month: 3, year: 2025)),
      ('Febr 2025', PartialDate(month: 2, year: 2025)),
      ('25th Jan 2024', PartialDate(day: 25, month: 1, year: 2024)),
      ('22nd Feb', PartialDate(day: 22, month: 2)),
      ('23 03', PartialDate(day: 23, month: 3)),
      ('24 04 2024', PartialDate(day: 24, month: 4, year: 2024)),
      ('3rd March', PartialDate(day: 3, month: 3)),
      ('25th of February 2025', PartialDate(day: 25, month: 2, year: 2025)),
      ('2025-02-25', PartialDate(day: 25, month: 2, year: 2025)),
      ('2025/02/25', PartialDate(day: 25, month: 2, year: 2025)),
      ('02/25/2025', PartialDate(day: 25, month: 2, year: 2025)),
      ('25/02/2025', PartialDate(day: 25, month: 2, year: 2025)),
      ('01/02/2024', PartialDate(day: 1, month: 2, year: 2024)),
      ('25.02.2025', PartialDate(day: 25, month: 2, year: 2025)),
      ('25.02.25', PartialDate(day: 25, month: 2, year: 2025)),
      ('20250225', PartialDate(day: 25, month: 2, year: 2025)),
      ('02/25', PartialDate(day: 25, month: 2)),
      ('25/02', PartialDate(day: 25, month: 2)),
      ('25/02/25', PartialDate(day: 25, month: 2, year: 2025)),
      ('01/01/01', PartialDate(day: 1, month: 1, year: 2001)),
      ('01/01/99', PartialDate(day: 1, month: 1, year: 1999)),
      ('2025', PartialDate(year: 2025)),
      ('February 30000', PartialDate(month: 2)),
      ('32 Jan 2024', PartialDate(month: 1, year: 2024)),
      ('Jan 13 2024', PartialDate(day: 13, month: 1, year: 2024)),
      ('Feb 0 2024', PartialDate(month: 2, year: 2024)),
    ]) {
      test(query, () => expect(parse(query), expected));
    }
  });
}
