import 'package:photos/services/date_parse_service.dart';
import 'package:test/test.dart';

void main() {
  // Get an instance of the service
  final DateParseService dateParseService = DateParseService.instance;

  // --- Natural Language Date Parsing ---
  group('Natural Language Date Parsing', () {
    // Relative dates: today, tomorrow, yesterday
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

    // Month names: Full (February), abbreviated (Feb), and partial (Febr)
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

    // Ordinal numbers: 25th, 22nd, 3rd, 1st
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

    // Flexible combinations
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

  // --- Structured Date Format Support ---
  group('Structured Date Format Support', () {
    // ISO format: 2025-02-25, 2025/02/25
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

    // Standard formats: 02/25/2025, 25/02/2025 (with MM/DD vs DD/MM detection)
    test('should parse standard MM/DD/YYYY format "02/25/2025"', () {
      // Your parser assumes MM/DD if ambiguous (e.g., both parts <= 12)
      // but for 02/25/2025, 25 > 12, so it correctly interprets 02 as month and 25 as day.
      final PartialDate parsedDate = dateParseService.parse('02/25/2025');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse standard DD/MM/YYYY format "25/02/2025"', () {
      // Your parser handles DD/MM explicitly when day part > 12
      final PartialDate parsedDate = dateParseService.parse('25/02/2025');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse ambiguous "01/02/2024" as DD/MM/YYYY (Feb 1)', () {
      // The parser prefers DD/MM when both day and month are plausible.
      final PartialDate parsedDate = dateParseService.parse('01/02/2024');
      expect(parsedDate.day, 1);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2024);
    });

    // Dot notation: 25.02.2025, 25.02.25
    test('should parse dot notation "25.02.2025"', () {
      final PartialDate parsedDate = dateParseService.parse('25.02.2025');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    test('should parse dot notation with two-digit year "25.02.25"', () {
      // Assumes century detection (e.g., 25 -> 2025)
      final PartialDate parsedDate = dateParseService.parse('25.02.25');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    // Compact format: 20250225
    test('should parse compact format "20250225"', () {
      final PartialDate parsedDate = dateParseService.parse('20250225');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025);
    });

    // Short formats: 02/25, 25/02 (your parser doesn't explicitly handle short yearless formats)
    // Based on your _standardFormatRegex: RegExp(r'^(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})$');
    // and _parseTokenizedDate, "02/25" would be processed by _parseTokenizedDate.
    // Let's test how your current parser handles these.
    test(
      'should parse short MM/DD format "02/25" (no year, handled by tokenized)',
      () {
        final PartialDate parsedDate = dateParseService.parse('02/25');
        expect(parsedDate.day, 25); // value 25 is assigned to day first
        expect(parsedDate.month, 2); // value 02 is assigned to month
        expect(parsedDate.year, isNull);
      },
    );

    test(
      'should parse short DD/MM format "25/02" (no year, handled by tokenized)',
      () {
        // This will be parsed by _parseTokenizedDate
        final PartialDate parsedDate = dateParseService.parse('25/02');
        expect(parsedDate.day, 25);
        expect(parsedDate.month, 2);
        expect(parsedDate.year, isNull);
      },
    );

    // Two-digit years: 25/02/25 (with century detection)
    test('should parse two-digit year "25/02/25"', () {
      final PartialDate parsedDate = dateParseService.parse('25/02/25');
      expect(parsedDate.day, 25);
      expect(parsedDate.month, 2);
      expect(parsedDate.year, 2025); // Based on _convertTwoDigitYear pivot
    });

    test('should parse two-digit year "01/01/01" as 2001', () {
      final PartialDate parsedDate = dateParseService.parse('01/01/01');
      expect(parsedDate.day, 1);
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 2001); // 01 < _TWO_DIGIT_YEAR_PIVOT
    });

    test('should parse two-digit year "01/01/99" as 1999', () {
      final PartialDate parsedDate = dateParseService.parse('01/01/99');
      expect(parsedDate.day, 1);
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 1999); // 99 > _TWO_DIGIT_YEAR_PIVOT
    });
  });

  // --- Smart Query Types ---
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

  // --- Invalid Date Queries ---
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

    // Specific case to test if invalid day/month values are set to null
    test('should return null for invalid day/month in tokenized parsing', () {
      final PartialDate parsedDate = dateParseService.parse('32 Jan 2024');
      expect(parsedDate.day, isNull, reason: 'Day should be null for 32');
      expect(parsedDate.month, 1);
      expect(parsedDate.year, 2024);

      // "Jan 13 2024" - This is a valid date (Jan 13, 2024), should parse completely.
      final PartialDate parsedDate2 = dateParseService.parse('Jan 13 2024');
      expect(parsedDate2.day, 13);
      expect(parsedDate2.month, 1);
      expect(parsedDate2.year, 2024);

      // "Feb 0 2024" - Day 0 should be null, but month and year are valid.
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
