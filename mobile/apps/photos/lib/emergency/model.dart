import "package:photos/models/api/collection/user.dart";

enum ContactState {
  userInvitedContact,
  userRevokedContact,
  contactAccepted,
  contactLeft,
  contactDenied,
  unknown,
}

extension ContactStateExtension on ContactState {
  String get stringValue {
    switch (this) {
      case ContactState.userInvitedContact:
        return "INVITED";
      case ContactState.userRevokedContact:
        return "REVOKED";
      case ContactState.contactAccepted:
        return "ACCEPTED";
      case ContactState.contactLeft:
        return "CONTACT_LEFT";
      case ContactState.contactDenied:
        return "CONTACT_DENIED";
      default:
        return "UNKNOWN";
    }
  }

  static ContactState fromString(String value) {
    switch (value) {
      case "INVITED":
        return ContactState.userInvitedContact;
      case "REVOKED":
        return ContactState.userRevokedContact;
      case "ACCEPTED":
        return ContactState.contactAccepted;
      case "CONTACT_LEFT":
        return ContactState.contactLeft;
      case "CONTACT_DENIED":
        return ContactState.contactDenied;
      default:
        return ContactState.unknown;
    }
  }
}

class EmergencyContact {
  final User user;
  final User emergencyContact;
  final ContactState state;
  final int recoveryNoticeInDays;

  EmergencyContact(
    this.user,
    this.emergencyContact,
    this.state,
    this.recoveryNoticeInDays,
  );

  // copyWith
  EmergencyContact copyWith({
    User? user,
    User? emergencyContact,
    ContactState? state,
    int? recoveryNoticeInDays,
  }) {
    return EmergencyContact(
      user ?? this.user,
      emergencyContact ?? this.emergencyContact,
      state ?? this.state,
      recoveryNoticeInDays ?? this.recoveryNoticeInDays,
    );
  }

  // fromJson
  EmergencyContact.fromJson(Map<String, dynamic> json)
    : user = User.fromMap(json['user']),
      emergencyContact = User.fromMap(json['emergencyContact']),
      state = ContactStateExtension.fromString(json['state'] as String),
      recoveryNoticeInDays = json['recoveryNoticeInDays'];

  bool isCurrentUserContact(int userID) {
    return user.id == userID;
  }

  bool isPendingInvite() {
    return state == ContactState.userInvitedContact;
  }
}

class EmergencyInfo {
  // List of emergency contacts added by the user
  final List<EmergencyContact> contacts;

  // List of recovery sessions that are created to recover current user account
  final List<RecoverySessions> recoverSessions;

  // List of emergency contacts that have added current user as their emergency contact
  final List<EmergencyContact> othersEmergencyContact;

  // List of recovery sessions that are created to recover grantor's account
  final List<RecoverySessions> othersRecoverySession;

  EmergencyInfo(
    this.contacts,
    this.recoverSessions,
    this.othersEmergencyContact,
    this.othersRecoverySession,
  );

  // from json
  EmergencyInfo.fromJson(Map<String, dynamic> json)
    : contacts = (json['contacts'] as List)
          .map((contact) => EmergencyContact.fromJson(contact))
          .toList(),
      recoverSessions = (json['recoverSessions'] as List)
          .map((session) => RecoverySessions.fromJson(session))
          .toList(),
      othersEmergencyContact = (json['othersEmergencyContact'] as List)
          .map((grantor) => EmergencyContact.fromJson(grantor))
          .toList(),
      othersRecoverySession = (json['othersRecoverySession'] as List)
          .map((session) => RecoverySessions.fromJson(session))
          .toList();
}

class RecoverySessions {
  final String id;
  final User user;
  final User emergencyContact;
  final String status;
  final int waitTill;
  final int createdAt;

  RecoverySessions(
    this.id,
    this.user,
    this.emergencyContact,
    this.status,
    this.waitTill,
    this.createdAt,
  );

  // fromJson
  RecoverySessions.fromJson(Map<String, dynamic> json)
    : id = json['id'],
      user = User.fromMap(json['user']),
      emergencyContact = User.fromMap(json['emergencyContact']),
      status = json['status'],
      waitTill = json['waitTill'],
      createdAt = json['createdAt'];
}
