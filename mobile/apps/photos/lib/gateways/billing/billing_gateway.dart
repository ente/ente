import "package:dio/dio.dart";
import "package:photos/core/errors.dart";
import "package:photos/gateways/billing/models/billing_plan.dart";
import "package:photos/gateways/billing/models/subscription.dart";

/// Gateway for billing API endpoints.
///
/// Handles subscription management, billing plans, and Stripe integration.
class BillingGateway {
  final Dio _enteDio;

  BillingGateway(this._enteDio);

  /// Gets available billing plans for the user.
  ///
  /// Returns [BillingPlans] containing all available subscription plans.
  Future<BillingPlans> getUserPlans() async {
    final response = await _enteDio.get("/billing/user-plans");
    return BillingPlans.fromMap(response.data);
  }

  /// Verifies an in-app purchase subscription.
  ///
  /// [productID] - The product ID from the app store.
  /// [verificationData] - Server verification data from the purchase.
  /// [paymentProvider] - The payment provider ("playstore" or "appstore").
  ///
  /// Returns the verified [Subscription].
  /// Throws [SubscriptionAlreadyClaimedError] if the subscription was already
  /// claimed by another account.
  Future<Subscription> verifySubscription({
    required String productID,
    required String verificationData,
    required String paymentProvider,
  }) async {
    try {
      final response = await _enteDio.post(
        "/billing/verify-subscription",
        data: {
          "paymentProvider": paymentProvider,
          "productID": productID,
          "verificationData": verificationData,
        },
      );
      return Subscription.fromMap(response.data["subscription"]);
    } on DioException catch (e) {
      if (e.response != null && e.response!.statusCode == 409) {
        throw SubscriptionAlreadyClaimedError();
      }
      rethrow;
    }
  }

  /// Fetches the current subscription for the authenticated user.
  ///
  /// Returns the current [Subscription].
  Future<Subscription> getSubscription() async {
    final response = await _enteDio.get("/billing/subscription");
    return Subscription.fromMap(response.data["subscription"]);
  }

  /// Cancels the user's Stripe subscription.
  ///
  /// The subscription will remain active until the end of the current billing
  /// period but will not auto-renew.
  ///
  /// Returns the updated [Subscription].
  Future<Subscription> cancelStripeSubscription() async {
    final response = await _enteDio.post("/billing/stripe/cancel-subscription");
    return Subscription.fromMap(response.data["subscription"]);
  }

  /// Reactivates a canceled Stripe subscription.
  ///
  /// This must be called before the subscription period ends to prevent
  /// cancellation.
  ///
  /// Returns the reactivated [Subscription].
  Future<Subscription> activateStripeSubscription() async {
    final response = await _enteDio.post(
      "/billing/stripe/activate-subscription",
    );
    return Subscription.fromMap(response.data["subscription"]);
  }

  /// Gets the Stripe customer portal URL.
  ///
  /// [redirectURL] - The URL to redirect to after the user finishes in the
  /// portal.
  ///
  /// Returns the portal URL as a string.
  Future<String> getStripeCustomerPortalUrl({
    required String redirectURL,
  }) async {
    final response = await _enteDio.get(
      "/billing/stripe/customer-portal",
      queryParameters: {"redirectURL": redirectURL},
    );
    return response.data["url"] as String;
  }
}
