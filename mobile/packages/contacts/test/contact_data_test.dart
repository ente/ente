import 'package:ente_contacts/contacts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores legacy birth date', () {
    final data = ContactData.fromJson({
      'contactUserId': 2,
      'name': 'B',
      'birthDate': '2001-04-02',
    });

    expect(data.toJson(), {'contactUserId': 2, 'name': 'B'});
  });
}
