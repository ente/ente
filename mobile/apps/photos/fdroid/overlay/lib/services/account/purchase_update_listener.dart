void listenForPurchaseUpdates({
  required bool Function() isOnSubscriptionPage,
  required Future<void> Function(String productID, String verificationData)
  verifySubscription,
}) {}
