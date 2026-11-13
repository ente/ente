import "package:photos/gateways/storage_bonus/models/bonus.dart";

class ReferralView {
  PlanInfo planInfo;
  String code;
  bool enableApplyCode;
  bool isFamilyMember;
  bool hasAppliedCode;
  int claimedStorage;

  ReferralView({
    required this.planInfo,
    required this.code,
    required this.enableApplyCode,
    required this.isFamilyMember,
    required this.hasAppliedCode,
    required this.claimedStorage,
  });

  factory ReferralView.fromJson(Map<String, dynamic> json) => ReferralView(
    planInfo: PlanInfo.fromJson(json["planInfo"]),
    code: json["code"],
    enableApplyCode: json["enableApplyCode"],
    isFamilyMember: json["isFamilyMember"],
    hasAppliedCode: json["hasAppliedCode"],
    claimedStorage: json["claimedStorage"],
  );

  Map<String, dynamic> toJson() => {
    "planInfo": planInfo.toJson(),
    "code": code,
    "enableApplyCode": enableApplyCode,
    "isFamilyMember": isFamilyMember,
    "hasAppliedCode": hasAppliedCode,
    "claimedStorage": claimedStorage,
  };
}

class PlanInfo {
  bool isEnabled;
  String planType;
  int storageInGB;
  int maxClaimableStorageInGB;

  PlanInfo({
    required this.isEnabled,
    required this.planType,
    required this.storageInGB,
    required this.maxClaimableStorageInGB,
  });

  factory PlanInfo.fromJson(Map<String, dynamic> json) => PlanInfo(
    isEnabled: json["isEnabled"],
    planType: json["planType"],
    storageInGB: json["storageInGB"],
    maxClaimableStorageInGB: json["maxClaimableStorageInGB"],
  );

  Map<String, dynamic> toJson() => {
    "isEnabled": isEnabled,
    "planType": planType,
    "storageInGB": storageInGB,
    "maxClaimableStorageInGB": maxClaimableStorageInGB,
  };
}

class ReferralStat {
  String planType;
  int totalCount;
  int upgradedCount;

  ReferralStat(this.planType, this.totalCount, this.upgradedCount);

  factory ReferralStat.fromJson(Map<String, dynamic> json) {
    return ReferralStat(
      json['planType'],
      json['totalCount'],
      json['upgradedCount'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'planType': planType,
      'totalCount': totalCount,
      'upgradedCount': upgradedCount,
    };
  }
}

class BonusDetails {
  List<ReferralStat> referralStats;
  List<Bonus> bonuses;
  int refCount;
  int refUpgradeCount;
  bool hasAppliedCode;

  BonusDetails({
    required this.referralStats,
    required this.bonuses,
    required this.refCount,
    required this.refUpgradeCount,
    required this.hasAppliedCode,
  });

  factory BonusDetails.fromJson(Map<String, dynamic> json) => BonusDetails(
    referralStats: List<ReferralStat>.from(
      json["referralStats"].map((x) => ReferralStat.fromJson(x)),
    ),
    bonuses: List<Bonus>.from(json["bonuses"].map((x) => Bonus.fromJson(x))),
    refCount: json["refCount"],
    refUpgradeCount: json["refUpgradeCount"],
    hasAppliedCode: json["hasAppliedCode"],
  );

  Map<String, dynamic> toJson() => {
    "referralStats": List<dynamic>.from(referralStats.map((x) => x.toJson())),
    "bonuses": List<dynamic>.from(bonuses.map((x) => x.toJson())),
    "refCount": refCount,
    "refUpgradeCount": refUpgradeCount,
    "hasAppliedCode": hasAppliedCode,
  };
}
