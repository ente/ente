import 'package:photos/services/date_parse_service.dart';
import 'package:test/test.dart';

void main() {
  final DateParseService dateParseService = DateParseService.instance;

  group('Natural Language Date Parsing', () {
    test('should parse "today" correctly', () {
      final DateTime now = DateTime.now();
      final PartialDate expectedDate = PartialDate(
        day: now.day,
        month: now.month,
        year: now.year,
      );
      final PartialDate parsedDate = dateParseService.parse('today');

      expect(
        parsedDate.day,
        expectedDate.day,
        reason: 'Day mismatch for today',
      );
      expect(
        parsedDate.month,
        expectedDate.month,
        reason: 'Month mismatch for today',
      );
      expect(
        parsedDate.year,
        expectedDate.year,
        reason: 'Year mismatch for today',
      );
    });

    test('should parse "tomorrow" correctly', () {
      final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
      final PartialDate expectedDate = PartialDate(
        day: tomorrow.day,
        month: tomorrow.month,
        year: tomorrow.year,
      );
      final PartialDate parsedDate = dateParseService.parse('tomorrow');

      expect(
        parsedDate.day,
        expectedDate.day,
        reason: 'Day mismatch for tomorrow',
      );
      expect(
        parsedDate.month,
        expectedDate.month,
        reason: 'Month mismatch for tomorrow',
      );
      expect(
        parsedDate.year,
        expectedDate.year,
        reason: 'Year mismatch for tomorrow',
      );
    });

    test('should parse "yesterday" correctly', () {
      final DateTime yesterday = DateTime.now().subtract(
        const Duration(days: 1),
      );
      final PartialDate expectedDate = PartialDate(
        day: yesterday.day,
        month: yesterday.month,
        year: yesterday.year,
      );
      final PartialDate parsedDate = dateParseService.parse('yesterday');

      expect(
        parsedDate.day,
        expectedDate.day,
        reason: 'Day mismatch for yesterday',
      );
      expect(
        parsedDate.month,
        expectedDate.month,
        reason: 'Month mismatch for yesterday',
      );
      expect(
        parsedDate.year,
        expectedDate.year,
        reason: 'Year mismatch for yesterday',
      );
    });

    test('should parse full month name "February 2025"', () {
      final PartialDate parsedDate = dateParseService.parse('February 2025');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse abbreviated month name "Feb 2025"', () {
      final PartialDate parsedDate = dateParseService.parse('Feb 2025');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse partial month-year "03-2024"', () {
      final PartialDate parsedDate = dateParseService.parse('03-2024');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, 3);
      expect(parsedDate.year, 2024);
    });

    test('should parse partial month/year "03/2025"', () {
      final PartialDate parsedDate = dateParseService.parse('03/2025');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, 3);
      expect(parsedDate.year, 2025);
    });

    test('should parse partial month name "Febr 2025"', () {
      final PartialDate parsedDate = dateParseService.parse('Febr 2025');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse ordinal number "25th Jan 2024"', () {
      final PartialDate parsedDate = dateParseService.parse('25th Jan 2024');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 2024);
    });

    test('should parse ordinal number "22nd Feb"', () {
      final PartialDate parsedDate = dateParseService.parse('22nd Feb');
      expect(parsedDate.day, 22);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, isNull);
    });

    test('should parse ordinal number dd mm format "23 03"', () {
      final PartialDate parsedDate = dateParseService.parse('23 03');
      expect(parsedDate.day, 23);
      expect(parsedDate.month, 3);
      expect(parsedDate.year, isNull);
    });

    test('should parse ordinal number "24 04 2024"', () {
      final PartialDate parsedDate = dateParseService.parse('24 04 2024');
      expect(parsedDate.day, 24);
      expect(parsedDate.month, 4);
      expect(parsedDate.year, 2024);
    });

    test('should parse ordinal number "3rd March"', () {
      final PartialDate parsedDate = dateParseService.parse('3rd March');
      expect(parsedDate.day, 3);
      expect(parsedDate.month, 3);
      expect(parsedDate.year, isNull);
    });

    test('should parse "25th Feb" (generic date)', () {
      final PartialDate parsedDate = dateParseService.parse('25th Feb');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, isNull);
    });

    test('should parse "February 2025" (month-year query)', () {
      final PartialDate parsedDate = dateParseService.parse('February 2025');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse "25th of February 2025"', () {
      final PartialDate parsedDate = dateParseService.parse(
        '25th of February 2025',
      );
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });
  });

  group('Structured Date Format Support', () {
    test('should parse ISO format "2025-02-25"', () {
      final PartialDate parsedDate = dateParseService.parse('2025-02-25');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse ISO format "2025/02/25"', () {
      final PartialDate parsedDate = dateParseService.parse('2025/02/25');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse standard MM/DD/YYYY format "02/25/2025"', () {
      final PartialDate parsedDate = dateParseService.parse('02/25/2025');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse standard DD/MM/YYYY format "25/02/2025"', () {
      final PartialDate parsedDate = dateParseService.parse('25/02/2025');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse ambiguous "01/02/2024" as DD/MM/YYYY (Feb 1)', () {
      final PartialDate parsedDate = dateParseService.parse('01/02/2024');
      expect(parsedDate.day, 1);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2024);
    });

    test('should parse dot notation "25.02.2025"', () {
      final PartialDate parsedDate = dateParseService.parse('25.02.2025');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse dot notation with two-digit year "25.02.25"', () {
      final PartialDate parsedDate = dateParseService.parse('25.02.25');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse compact format "20250225"', () {
      final PartialDate parsedDate = dateParseService.parse('20250225');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test(
      'should parse short MM/DD format "02/25" (no year, handled by tokenized)',
      () {
        final PartialDate parsedDate = dateParseService.parse('02/25');
        expect(parsedDate.day, 25);
        expect(parsedDate.month, 2);
        expect(parsedDate.year, isNull);
      },
    );

    test(
      'should parse short DD/MM format "25/02" (no year, handled by tokenized)',
      () {
        final PartialDate parsedDate = dateParseService.parse('25/02');
        expect(parsedDate.day, 25);
        expect(parsedDate.month, 2);
        expect(parsedDate.year, isNull);
      },
    );

    test('should parse two-digit year "25/02/25"', () {
      final PartialDate parsedDate = dateParseService.parse('25/02/25');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse two-digit year "01/01/01" as 2001', () {
      final PartialDate parsedDate = dateParseService.parse('01/01/01');
      expect(parsedDate.day, 1);
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 2001);
    });

    test('should parse two-digit year "01/01/99" as 1999', () {
      final PartialDate parsedDate = dateParseService.parse('01/01/99');
      expect(parsedDate.day, 1);
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 1999);
    });
  });

  group('Smart Query Types', () {
    test('should parse year-only query "2025"', () {
      final PartialDate parsedDate = dateParseService.parse('2025');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, isNull);
      expect(parsedDate.year, 2025);
    });

    test('should parse month-year query "February 2025"', () {
      final PartialDate parsedDate = dateParseService.parse('February 2025');
      expect(parsedDate.day, isNull);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse generic date query "25th Feb" (year is null)', () {
      final PartialDate parsedDate = dateParseService.parse('25th Feb');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, isNull);
    });

    test('should parse specific date query "25/02/2025"', () {
      final PartialDate parsedDate = dateParseService.parse('25/02/2025');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });
  });

  group('Invalid Date Queries', () {
    test(
      'should parse "February 30000" as month-only (invalid year ignored)',
      () {
        final PartialDate parsedDate = dateParseService.parse('February 30000');
        expect(parsedDate.day, isNull);
        expect(parsedDate.month, 2);
        expect(
          parsedDate.year,
          isNull,
          reason: 'Year 30000 is out of range and should be ignored',
        );
      },
    );

    test('should return null for invalid day/month in tokenized parsing', () {
      final PartialDate parsedDate = dateParseService.parse('32 Jan 2024');
      expect(parsedDate.day, isNull, reason: 'Day should be null for 32');
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 2024);

      final PartialDate parsedDate2 = dateParseService.parse('Jan 13 2024');
      expect(parsedDate2.day, 13);
      expect(parsedDate2.month, 1);
      expect(parsedDate2.year, 2024);

      final PartialDate parsedDate3 = dateParseService.parse('Feb 0 2024');
      expect(parsedDate3.day, isNull, reason: 'Day should be null for 0');
      expect(parsedDate3.month, 2);
      expect(parsedDate3.year, 2024);
    });

    test('should handle invalid day/month in tokenized parsing gracefully', () {
      final PartialDate parsedDate = dateParseService.parse('32 Jan 2024');
      expect(parsedDate.day, isNull, reason: 'Day should be null for 32');
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 2024);
    });
  });
}
