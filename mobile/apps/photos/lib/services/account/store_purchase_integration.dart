import "dart:io";

import "package:in_app_purchase/in_app_purchase.dart";
import "package:in_app_purchase_storekit/in_app_purchase_storekit.dart";

Future<void> initializeStorePurchases() async {
  if (!Platform.isIOS) {
    return;
  }

  // This must run during app initialization, before any code reads
  // InAppPurchase.instance.purchaseStream. Flutter registers StoreKit 2 before
  // main(), so switch to StoreKit 1 and re-register the Dart implementation
  // early enough for its transaction observer to be initialized.
  // TODO: Remove this fallback after the server supports StoreKit 2 JWS
  // verification.
  // ignore: deprecated_member_use
  await InAppPurchaseStoreKitPlatform.enableStoreKit1();
  InAppPurchaseStoreKitPlatform.registerPlatform();
}

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
