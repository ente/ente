import 'dart:convert';

// Enum for different information types
enum InfoType { note, physicalRecord, accountCredential, emergencyContact }

// Extension to convert enum to string and vice versa.
//
// Locker file metadata currently uses the enum's camelCase name on the wire.
// Keep parsing tolerant of the older hyphenated representation so any
// previously serialized JSON can still be read safely.
extension InfoTypeExtension on InfoType {
  String get value {
    switch (this) {
      case InfoType.note:
        return 'note';
      case InfoType.physicalRecord:
        return 'physicalRecord';
      case InfoType.accountCredential:
        return 'accountCredential';
      case InfoType.emergencyContact:
        return 'emergencyContact';
    }
  }

  static InfoType fromString(String value) {
    switch (value) {
      case 'note':
        return InfoType.note;
      case 'physicalRecord':
      case 'physical-record':
        return InfoType.physicalRecord;
      case 'accountCredential':
      case 'account-credential':
        return InfoType.accountCredential;
      case 'emergencyContact':
      case 'emergency-contact':
        return InfoType.emergencyContact;
      default:
        throw ArgumentError('Unknown InfoType: $value');
    }
  }
}

// Base class for all information data
abstract class InfoData {
  Map<String, dynamic> toJson();

  static InfoData fromJson(InfoType type, Map<String, dynamic> json) {
    switch (type) {
      case InfoType.note:
        return PersonalNoteData.fromJson(json);
      case InfoType.physicalRecord:
        return PhysicalRecordData.fromJson(json);
      case InfoType.accountCredential:
        return AccountCredentialData.fromJson(json);
      case InfoType.emergencyContact:
        return EmergencyContactData.fromJson(json);
    }
  }
}

// Personal Note Data Model
class PersonalNoteData extends InfoData {
  final String title;
  final String content;

  PersonalNoteData({required this.title, required this.content});

  factory PersonalNoteData.fromJson(Map<String, dynamic> json) {
    return PersonalNoteData(
      title: json['title'] ?? '',
      content: json['content'] ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'title': title, 'content': content};
  }
}

// Physical Record Data Model
class PhysicalRecordData extends InfoData {
  final String name;
  final String location;
  final String? notes;

  PhysicalRecordData({required this.name, required this.location, this.notes});

  factory PhysicalRecordData.fromJson(Map<String, dynamic> json) {
    return PhysicalRecordData(
      name: json['name'] ?? '',
      location: json['location'] ?? '',
      notes: json['notes'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'location': location,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}

// Account Credential Data Model
class AccountCredentialData extends InfoData {
  final String name;
  final String username;
  final String password;
  final String? notes;

  AccountCredentialData({
    required this.name,
    required this.username,
    required this.password,
    this.notes,
  });

  factory AccountCredentialData.fromJson(Map<String, dynamic> json) {
    return AccountCredentialData(
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      notes: json['notes'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'username': username,
      'password': password,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}

// Emergency Contact Data Model
class EmergencyContactData extends InfoData {
  final String name;
  final String contactDetails;
  final String? notes;

  EmergencyContactData({
    required this.name,
    required this.contactDetails,
    this.notes,
  });

  factory EmergencyContactData.fromJson(Map<String, dynamic> json) {
    return EmergencyContactData(
      name: json['name'] ?? '',
      contactDetails: json['contactDetails'] ?? '',
      notes: json['notes'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'contactDetails': contactDetails,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}

// Main Information Item wrapper
class InfoItem {
  final InfoType type;
  final InfoData data;
  final DateTime createdAt;
  final DateTime? updatedAt;

  InfoItem({
    required this.type,
    required this.data,
    required this.createdAt,
    this.updatedAt,
  });

  factory InfoItem.fromJson(Map<String, dynamic> json) {
    final type = InfoTypeExtension.fromString(json['type']);
    final data = InfoData.fromJson(type, json['data']);

    return InfoItem(
      type: type,
      data: data,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'data': data.toJson(),
      'createdAt': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static InfoItem fromJsonString(String jsonString) {
    return InfoItem.fromJson(jsonDecode(jsonString));
  }

  // Create a copy with updated data
  InfoItem copyWith({
    InfoType? type,
    InfoData? data,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InfoItem(
      type: type ?? this.type,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Update with new data and timestamp
  InfoItem update(InfoData newData) {
    return copyWith(data: newData, updatedAt: DateTime.now());
  }
}
