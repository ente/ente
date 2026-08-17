import "package:dio/dio.dart";
import "package:photos/core/errors.dart";
import "package:photos/gateways/billing/models/billing_plan.dart";
import "package:photos/gateways/billing/models/subscription.dart";

class BillingGateway {
  final Dio _enteDio;

  BillingGateway(this._enteDio);

  Future<BillingPlans> getUserPlans() async {
    final response = await _enteDio.get("/billing/user-plans");
    return BillingPlans.fromMap(response.data);
  }

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

  Future<Subscription> getSubscription() async {
    final response = await _enteDio.get("/billing/subscription");
    return Subscription.fromMap(response.data["subscription"]);
  }

  Future<Subscription> cancelStripeSubscription() async {
    final response = await _enteDio.post("/billing/stripe/cancel-subscription");
    return Subscription.fromMap(response.data["subscription"]);
  }

  Future<Subscription> activateStripeSubscription() async {
    final response = await _enteDio.post(
      "/billing/stripe/activate-subscription",
    );
    return Subscription.fromMap(response.data["subscription"]);
  }

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
