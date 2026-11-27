import 'package:ente_auth/store/code_display_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tags are A to Z without a saved order', () {
    expect(orderTags({'Work', 'Bank', 'Mail'}, []), ['Bank', 'Mail', 'Work']);
  });

  test('saved tags come first, then the rest A to Z', () {
    expect(
      orderTags({'Bank', 'Work', 'Mail', 'Games'}, ['Work', 'Old', 'Mail']),
      ['Work', 'Mail', 'Bank', 'Games'],
    );
  });

  test('saving keeps the slot of tags that are not shown', () {
    expect(mergeTagOrder(['Bank', 'Hidden', 'Work'], ['Work', 'Bank', 'New']), [
      'Work',
      'Hidden',
      'Bank',
      'New',
    ]);
  });

  test('first save stores the shown order', () {
    expect(mergeTagOrder([], ['Work', 'Bank']), ['Work', 'Bank']);
  });
}
