import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/core/errors.dart';
import 'package:ente_auth/models/billing_plan.dart';
import 'package:ente_network/network.dart';
import 'package:logging/logging.dart';

const kWebPaymentRedirectUrl = "https://payments.ente.com/frameRedirect";
const kWebPaymentBaseEndpoint = String.fromEnvironment(
  "web-payment",
  defaultValue: "https://payments.ente.com",
);

const kFamilyPlanManagementUrl = String.fromEnvironment(
  "web-family",
  defaultValue: "https://family.ente.io",
);

class BillingService {
  BillingService._privateConstructor();

  static final BillingService instance = BillingService._privateConstructor();

  final _logger = Logger("BillingService");
  final _dio = Network.instance.getDio();
  final _config = Configuration.instance;

  Subscription? _cachedSubscription;

  Future<BillingPlans>? _future;

  Future<void> init() async {}

  void clearCache() {
    _future = null;
  }

  Future<BillingPlans> getBillingPlans() {
    _future ??=
        (_config.getToken() == null
                ? _fetchPublicBillingPlans()
                : _fetchPrivateBillingPlans())
            .then((response) {
              return BillingPlans.fromMap(response.data);
            });
    return _future!;
  }

  Future<Response<dynamic>> _fetchPrivateBillingPlans() {
    return _dio.get(
      "${_config.getHttpEndpoint()}/billing/user-plans/",
      options: Options(headers: {"X-Auth-Token": _config.getToken()}),
    );
  }

  Future<Response<dynamic>> _fetchPublicBillingPlans() {
    return _dio.get("${_config.getHttpEndpoint()}/billing/plans/v2");
  }

  Future<Subscription> verifySubscription(
    final String productID,
    final String verificationData, {
    final String? paymentProvider,
  }) async {
    try {
      final response = await _dio.post(
        "${_config.getHttpEndpoint()}/billing/verify-subscription",
        data: {
          "paymentProvider":
              paymentProvider ??
              (Platform.isAndroid ? "playstore" : "appstore"),
          "productID": productID,
          "verificationData": verificationData,
        },
        options: Options(headers: {"X-Auth-Token": _config.getToken()}),
      );
      return Subscription.fromMap(response.data["subscription"]);
    } on DioException catch (e) {
      if (e.response != null && e.response!.statusCode == 409) {
        throw SubscriptionAlreadyClaimedError();
      } else {
        rethrow;
      }
    } catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }

  Future<Subscription> getSubscription() async {
    if (_cachedSubscription == null) {
      try {
        final response = await _dio.get(
          "${_config.getHttpEndpoint()}/billing/subscription",
          options: Options(headers: {"X-Auth-Token": _config.getToken()}),
        );
        _cachedSubscription = Subscription.fromMap(
          response.data["subscription"],
        );
      } on DioException catch (e, s) {
        _logger.severe(e, s);
        rethrow;
      }
    }
    return _cachedSubscription!;
  }

  Future<Subscription> cancelStripeSubscription() async {
    try {
      final response = await _dio.post(
        "${_config.getHttpEndpoint()}/billing/stripe/cancel-subscription",
        options: Options(headers: {"X-Auth-Token": _config.getToken()}),
      );
      final subscription = Subscription.fromMap(response.data["subscription"]);
      return subscription;
    } on DioException catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }

  Future<Subscription> activateStripeSubscription() async {
    try {
      final response = await _dio.post(
        "${_config.getHttpEndpoint()}/billing/stripe/activate-subscription",
        options: Options(headers: {"X-Auth-Token": _config.getToken()}),
      );
      final subscription = Subscription.fromMap(response.data["subscription"]);
      return subscription;
    } on DioException catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }

  Future<String> getStripeCustomerPortalUrl({
    String endpoint = kWebPaymentRedirectUrl,
  }) async {
    try {
      final response = await _dio.get(
        "${_config.getHttpEndpoint()}/billing/stripe/customer-portal",
        queryParameters: {"redirectURL": kWebPaymentRedirectUrl},
        options: Options(headers: {"X-Auth-Token": _config.getToken()}),
      );
      return response.data["url"];
    } on DioException catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }
}
