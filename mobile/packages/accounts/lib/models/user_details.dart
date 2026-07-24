import 'dart:convert';
import 'dart:math';

import 'package:ente_accounts/models/bonus.dart';
import 'package:ente_accounts/models/subscription.dart';

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
  final LockerFamilyUsage? lockerFamilyUsage;

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
    this.lockerFamilyUsage,
  );

  // Locker-specific limits computed client-side based on subscription
  // Free tier: 100 files, 1GB storage
  // Paid tier: 1000 files, 10GB storage
  static const int _lockerFileLimitFree = 100;
  static const int _lockerFileLimitPaid = 1000;
  static const int _lockerStorageLimitFree = 1 * 1024 * 1024 * 1024; // 1GB
  static const int _lockerStorageLimitPaid = 10 * 1024 * 1024 * 1024; // 10GB

  /// Returns true if user has paid access (direct subscription, family plan,
  /// or paid add-ons)
  bool hasPaidSubscription() {
    // Direct paid subscription
    if (!subscription.isFreePlan() && subscription.isValid()) {
      return true;
    }
    // Family plan member
    if (isPartOfFamily()) {
      return true;
    }
    // Has paid add-ons
    if (hasPaidAddon()) {
      return true;
    }
    return false;
  }

  /// Returns the locker file limit based on subscription status
  int getLockerFileLimit() {
    return hasPaidSubscription() ? _lockerFileLimitPaid : _lockerFileLimitFree;
  }

  /// Returns the locker storage limit based on subscription status
  int getLockerStorageLimit() {
    return hasPaidSubscription()
        ? _lockerStorageLimitPaid
        : _lockerStorageLimitFree;
  }

  bool isPartOfFamily() {
    return familyData?.members?.isNotEmpty ?? false;
  }

  bool hasPaidAddon() {
    return bonusData?.getAddOnBonuses().isNotEmpty ?? false;
  }

  bool isFamilyAdmin() {
    assert(isPartOfFamily(), "verify user is part of family before calling");
    final FamilyMember currentUserMember = familyData!.members!.firstWhere(
      (element) => element.email.trim() == email.trim(),
    );
    return currentUserMember.isAdmin;
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
      try {
        final FamilyMember currentUserMember = familyData!.members!.firstWhere(
          (element) => element.email.trim() == email.trim(),
        );
        return currentUserMember.storageLimit;
      } catch (e) {
        return null;
      }
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
      LockerFamilyUsage.fromJson(map['lockerFamilyUsage']),
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
      'lockerFamilyUsage': lockerFamilyUsage?.toJson(),
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
  final int? storageLimit;

  FamilyMember(
    this.email,
    this.usage,
    this.id,
    this.userID,
    this.isAdmin,
    this.storageLimit,
  );

  factory FamilyMember.fromMap(Map<String, dynamic> map) {
    return FamilyMember(
      (map['email'] ?? '') as String,
      map['usage'] as int,
      map['id'] as String,
      map['userID'] as int?,
      map['isAdmin'] as bool,
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

  FamilyData(this.members, this.storage, this.expiryTime);

  int getTotalUsage() {
    return members!
        .map((e) => e.usage)
        .toList()
        .fold(0, (sum, usage) => sum + usage);
  }

  FamilyMember? getMemberByID(String id) {
    try {
      return members!.firstWhere((element) => element.id == id);
    } catch (e) {
      return null;
    }
  }

  static FamilyData fromMap(Map<String, dynamic> map) {
    assert(map['members'] != null && map['members'].length >= 0);
    final members = List<FamilyMember>.from(
      map['members'].map((x) => FamilyMember.fromMap(x)),
    );
    return FamilyData(members, map['storage'] as int, map['expiryTime'] as int);
  }

  Map<String, dynamic> toMap() {
    return {
      'members': members?.map((x) => x.toMap()).toList(),
      'storage': storage,
      'expiryTime': expiryTime,
    };
  }

  String toJson() => json.encode(toMap());

  factory FamilyData.fromJson(String source) =>
      FamilyData.fromMap(json.decode(source));
}

class LockerFamilyUsage {
  final int familyFileCount;

  const LockerFamilyUsage(this.familyFileCount);

  factory LockerFamilyUsage.fromJson(Map<String, dynamic>? json) {
    return LockerFamilyUsage((json?['familyFileCount'] ?? 0) as int);
  }

  Map<String, dynamic> toJson() {
    return {'familyFileCount': familyFileCount};
  }
}
