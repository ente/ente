import "dart:io";

import "package:in_app_purchase/in_app_purchase.dart";

void listenForPurchaseUpdates({
  required bool Function() isOnSubscriptionPage,
  required Future<void> Function(String productID, String verificationData)
  verifySubscription,
}) {
  InAppPurchase.instance.purchaseStream.listen((purchases) {
    if (isOnSubscriptionPage()) {
      return;
    }
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased) {
        verifySubscription(
          purchase.productID,
          purchase.verificationData.serverVerificationData,
        ).then((response) {
          InAppPurchase.instance.completePurchase(purchase);
        });
      } else if (Platform.isIOS && purchase.pendingCompletePurchase) {
        InAppPurchase.instance.completePurchase(purchase);
      }
    }
  });
}
