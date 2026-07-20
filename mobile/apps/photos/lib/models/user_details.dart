import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import "package:photos/gateways/billing/models/subscription.dart";
import "package:photos/gateways/storage_bonus/models/bonus.dart";

enum FamilyMemberStatus {
  self("SELF"),
  closed("CLOSED"),
  invited("INVITED"),
  accepted("ACCEPTED"),
  declined("DECLINED"),
  revoked("REVOKED"),
  removed("REMOVED"),
  left("LEFT");

  const FamilyMemberStatus(this.serverValue);

  final String serverValue;

  static FamilyMemberStatus fromServerValue(String? value) {
    return FamilyMemberStatus.values.firstWhereOrNull(
          (status) => status.serverValue == value,
        ) ??
        FamilyMemberStatus.accepted;
  }
}

class UserDetails {
  final String email;
  final int usage;
  final int fileCount;
  final int storageBonus;
  final int sharedCollectionsCount;
  final Subscription subscription;
  final FamilyData? familyData;
  final ProfileData? profileData;
  final BonusData? bonusData;

  const UserDetails(
    this.email,
    this.usage,
    this.fileCount,
    this.storageBonus,
    this.sharedCollectionsCount,
    this.subscription,
    this.familyData,
    this.profileData,
    this.bonusData,
  );

  bool isPartOfFamily() {
    return familyData?.members?.isNotEmpty ?? false;
  }

  bool hasPaidAddon() {
    return bonusData?.getAddOnBonuses().isNotEmpty ?? false;
  }

  FamilyMember? currentFamilyMember() {
    if (familyData?.members == null) {
      return null;
    }
    return familyData!.members!.firstWhereOrNull(
      (member) => member.email.trim() == email.trim(),
    );
  }

  bool isFamilyAdmin() {
    assert(isPartOfFamily(), "verify user is part of family before calling");
    final FamilyMember currentUserMember = currentFamilyMember()!;
    return currentUserMember.isAdmin;
  }

  bool hasConfiguredFamily() {
    final currentUserMember = currentFamilyMember();
    if (currentUserMember == null) {
      return false;
    }
    if (!currentUserMember.isAdmin) {
      return true;
    }
    return familyData!.members!.any(
      (member) => member.email.trim() != email.trim(),
    );
  }

  // getFamilyOrPersonalUsage will return total usage for family if user
  // belong to family group. Otherwise, it will return storage consumed by
  // current user
  int getFamilyOrPersonalUsage() {
    return isPartOfFamily() ? familyData!.getTotalUsage() : usage;
  }

  int getFreeStorage() {
    final int? memberLimit = familyMemberStorageLimit();
    if (memberLimit != null) {
      return max(memberLimit - usage, 0);
    }
    return max(getTotalStorage() - getFamilyOrPersonalUsage(), 0);
  }

  // getTotalStorage will return total storage available including the
  // storage bonus
  int getTotalStorage() {
    return (isPartOfFamily() ? familyData!.storage : subscription.storage) +
        storageBonus;
  }

  // return the member storage limit if user is part of family and the admin
  // has set the storage limit for the user.
  int? familyMemberStorageLimit() {
    if (isPartOfFamily()) {
      final FamilyMember? currentUserMember = currentFamilyMember();
      return currentUserMember?.storageLimit;
    }
    return null;
  }

  // This is the total storage for which user has paid for.
  int getPlanPlusAddonStorage() {
    return (isPartOfFamily() ? familyData!.storage : subscription.storage) +
        bonusData!.totalAddOnBonus();
  }

  factory UserDetails.fromMap(Map<String, dynamic> map) {
    return UserDetails(
      map['email'] as String,
      map['usage'] as int,
      (map['fileCount'] ?? 0) as int,
      (map['storageBonus'] ?? 0) as int,
      (map['sharedCollectionsCount'] ?? 0) as int,
      Subscription.fromMap(map['subscription']),
      map['familyData'] != null ? FamilyData.fromMap(map['familyData']) : null,
      ProfileData.fromJson(map['profileData']),
      BonusData.fromJson(map['bonusData']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'usage': usage,
      'fileCount': fileCount,
      'storageBonus': storageBonus,
      'sharedCollectionsCount': sharedCollectionsCount,
      'subscription': subscription.toMap(),
      'familyData': familyData?.toMap(),
      'profileData': profileData?.toJson(),
      'bonusData': bonusData?.toJson(),
    };
  }

  String toJson() => json.encode(toMap());

  factory UserDetails.fromJson(String source) =>
      UserDetails.fromMap(json.decode(source));
}

class FamilyMember {
  final String email;
  final int usage;
  final String id;
  final int? userID;
  final bool isAdmin;
  final FamilyMemberStatus status;
  final int? storageLimit;

  FamilyMember(
    this.email,
    this.usage,
    this.id,
    this.userID,
    this.isAdmin,
    this.status,
    this.storageLimit,
  );

  bool get isPending => status == FamilyMemberStatus.invited;

  bool get isActive =>
      status == FamilyMemberStatus.accepted ||
      status == FamilyMemberStatus.self;

  factory FamilyMember.fromMap(Map<String, dynamic> map) {
    return FamilyMember(
      (map['email'] ?? '') as String,
      (map['usage'] ?? 0) as int,
      map['id'] as String,
      map['userID'] as int?,
      map['isAdmin'] as bool,
      FamilyMemberStatus.fromServerValue(map['status'] as String?),
      map['storageLimit'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'usage': usage,
      'id': id,
      'userID': userID,
      'isAdmin': isAdmin,
      'status': status.serverValue,
      'storageLimit': storageLimit,
    };
  }

  String toJson() => json.encode(toMap());

  factory FamilyMember.fromJson(String source) =>
      FamilyMember.fromMap(json.decode(source));
}

class ProfileData {
  bool canDisableEmailMFA;
  bool isEmailMFAEnabled;
  bool isTwoFactorEnabled;

  // Constructor with default values
  ProfileData({
    this.canDisableEmailMFA = false,
    this.isEmailMFAEnabled = false,
    this.isTwoFactorEnabled = false,
  });

  // Factory method to create ProfileData instance from JSON
  factory ProfileData.fromJson(Map<String, dynamic>? json) {
    return ProfileData(
      canDisableEmailMFA: json?['canDisableEmailMFA'] ?? false,
      isEmailMFAEnabled: json?['isEmailMFAEnabled'] ?? false,
      isTwoFactorEnabled: json?['isTwoFactorEnabled'] ?? false,
    );
  }

  // Method to convert ProfileData instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'canDisableEmailMFA': canDisableEmailMFA,
      'isEmailMFAEnabled': isEmailMFAEnabled,
      'isTwoFactorEnabled': isTwoFactorEnabled,
    };
  }

  String toJsonString() => json.encode(toJson());
}

class FamilyData {
  final List<FamilyMember>? members;

  // Storage available based on the family plan
  final int storage;
  final int expiryTime;
  final int adminBonus;

  FamilyData(this.members, this.storage, this.expiryTime, this.adminBonus);

  int getTotalUsage() {
    return members
            ?.where((member) => member.isActive)
            .map((e) => e.usage)
            .sum ??
        0;
  }

  FamilyMember? getMemberByID(String id) {
    return members!.firstWhereOrNull((element) => element.id == id);
  }

  static FamilyData fromMap(Map<String, dynamic> map) {
    assert(map['members'] != null && map['members'].length >= 0);
    final members = List<FamilyMember>.from(
      map['members'].map((x) => FamilyMember.fromMap(x)),
    );
    return FamilyData(
      members,
      map['storage'] as int,
      map['expiryTime'] as int,
      (map['adminBonus'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'members': members?.map((x) => x.toMap()).toList(),
      'storage': storage,
      'expiryTime': expiryTime,
      'adminBonus': adminBonus,
    };
  }

  String toJson() => json.encode(toMap());

  factory FamilyData.fromJson(String source) =>
      FamilyData.fromMap(json.decode(source));
}
