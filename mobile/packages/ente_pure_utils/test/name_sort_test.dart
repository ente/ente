import 'package:collection/collection.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareNames', () {
    test('sorts accented names with their base letter', () {
      final names = [
        'Zoé',
        'élise',
        'Emma',
        'Éric',
        'zebra',
        'eve',
        'Ålesund',
        'Ange',
      ];
      expect(names..sort(compareNames), [
        'Ålesund',
        'Ange',
        'élise',
        'Emma',
        'Éric',
        'eve',
        'zebra',
        'Zoé',
      ]);
    });

    test('keeps natural number order', () {
      final names = ['IMG_10', 'Été 10', 'IMG_9', 'Été 2'];
      expect(names..sort(compareNames), ['Été 2', 'Été 10', 'IMG_9', 'IMG_10']);
    });

    test('keeps the existing order for ASCII names', () {
      final names = ['b2', 'B10', 'a', 'A', 'img_1', 'IMG_01', 'Zed', 'zed'];
      expect(
        [...names]..sort(compareNames),
        [...names]..sort(compareAsciiLowerCaseNatural),
      );
    });

    test('orders names that differ only in accents or case', () {
      expect(compareNames('Eric', 'Éric'), lessThan(0));
      expect(compareNames('Éric', 'Eric'), greaterThan(0));
      expect(compareNames('Éric', 'Éric'), 0);
    });

    test('folds Vietnamese and Yoruba letters', () {
      final names = ['Zoe', 'Ọlá', 'Ẹlan', 'Ông', 'Ạnh', 'Nguyễn', 'Nguyen'];
      expect(names..sort(compareNames), [
        'Ạnh',
        'Ẹlan',
        'Nguyen',
        'Nguyễn',
        'Ọlá',
        'Ông',
        'Zoe',
      ]);
    });

    test('ignores case outside ASCII', () {
      expect(['Борис', 'анна']..sort(compareNames), ['анна', 'Борис']);
    });
  });

  group('nameSortKey', () {
    test('folds decomposed accents like precomposed ones', () {
      expect(nameSortKey('E\u0301lise'), nameSortKey('Élise'));
      expect(nameSortKey('Élise'), 'elise');
    });

    test('expands ligatures', () {
      expect(nameSortKey('Œuvre'), 'oeuvre');
      expect(nameSortKey('Straße'), 'strasse');
      expect(nameSortKey('Ærø'), 'aero');
    });
  });
}
