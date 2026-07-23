import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/gateways/storage_bonus/storage_bonus_gateway.dart";
import "package:shared_preferences/shared_preferences.dart";

class StorageBonusService {
  final StorageBonusGateway gateway;
  final SharedPreferences prefs;

  final int minTapCountBeforeHidingBanner = 1;
  final String _showStorageBonusTapCount = "showStorageBonus.tap_count";

  StorageBonusService(this.prefs, Dio enteDio)
    : gateway = StorageBonusGateway(enteDio) {
    debugPrint("StorageBonusService constructor");
  }

  // returns true if _showStorageBonusTapCount value is less than minTapCountBeforeHidingBanner
  bool shouldShowStorageBonus() {
    final tapCount = prefs.getInt(_showStorageBonusTapCount) ?? 0;
    return tapCount <= minTapCountBeforeHidingBanner;
  }

  void markStorageBonusAsDone() {
    final tapCount = prefs.getInt(_showStorageBonusTapCount) ?? 0;
    prefs.setInt(_showStorageBonusTapCount, tapCount + 1).ignore();
  }

  Future<void> applyCode(String code) {
    return gateway.claimReferralCode(code.trim().toUpperCase());
  }

  Future<void> updateCode(String code) {
    return gateway.updateCode(code.trim().toUpperCase());
  }

  Future<ReferralView> getReferralView() {
    return gateway.getReferralView();
  }

  Future<BonusDetails> getBonusDetails() {
    return gateway.getBonusDetails();
  }
}
