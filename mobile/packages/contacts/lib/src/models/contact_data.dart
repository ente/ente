import 'dart:convert';

class ContactData {
  final int contactUserId;
  final String name;

  const ContactData({required this.contactUserId, required this.name});

  Map<String, dynamic> toJson() => {
    'contactUserId': contactUserId,
    'name': name,
  };

  factory ContactData.fromJson(Map<String, dynamic> json) {
    return ContactData(
      contactUserId: json['contactUserId'] as int,
      name: json['name'] as String,
    );
  }

  String toEncodedJson() => jsonEncode(toJson());

  factory ContactData.fromEncodedJson(String jsonValue) =>
      ContactData.fromJson(jsonDecode(jsonValue) as Map<String, dynamic>);
}
