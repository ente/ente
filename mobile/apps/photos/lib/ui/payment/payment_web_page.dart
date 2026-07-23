import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logging/logging.dart';
import "package:photos/core/constants.dart";
import 'package:photos/ente_theme_data.dart';
import 'package:photos/gateways/billing/models/subscription.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/account/billing_service.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/utils/dialog_util.dart';
import "package:photos/utils/email_util.dart";

class PaymentWebPage extends StatefulWidget {
  final String planId;
  final String? actionType;

  const PaymentWebPage({super.key, required this.planId, this.actionType});

  @override
  State<StatefulWidget> createState() => _PaymentWebPageState();
}

class _PaymentWebPageState extends State<PaymentWebPage> {
  final _logger = Logger("PaymentWebPageState");
  final UserService userService = UserService.instance;
  late final BillingService billService = billingService;
  final String basePaymentUrl = kWebPaymentBaseEndpoint;
  InAppWebViewController? webView;
  double progress = 0;
  WebUri? initPaymentUrl;

  @override
  void initState() {
    userService.getPaymentToken().then((token) {
      initPaymentUrl = _getPaymentUrl(token);
      setState(() {});
    });
    if (Platform.isAndroid && kDebugMode) {
      InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (initPaymentUrl == null) {
      return const EnteLoadingWidget();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _buildPageExitWidget(context);
        if (shouldPop) {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).subscription)),
        body: Column(
          children: <Widget>[
            (progress != 1.0)
                ? LinearProgressIndicator(value: progress)
                : const SizedBox.shrink(),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: initPaymentUrl),
                onProgressChanged:
                    (InAppWebViewController controller, int progress) {
                      setState(() {
                        this.progress = progress / 100;
                      });
                    },
                initialSettings: InAppWebViewSettings(
                  useShouldOverrideUrlLoading: true,
                ),
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final loadingUri = navigationAction.request.url;
                  _logger.info("Loading url $loadingUri");
                  // handle the payment response
                  if (_isPaymentActionComplete(loadingUri)) {
                    await _handlePaymentResponse(loadingUri!);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onConsoleMessage: (controller, consoleMessage) {
                  _logger.info("onConsoleMessage $consoleMessage");
                },
                onLoadStart: (controller, navigationAction) async {
                  _logger.info("onLoadStart $navigationAction");
                },
                onReceivedError: (controller, navigationAction, code) async {
                  _logger.severe("onLoadError $navigationAction $code");
                },
                onReceivedHttpError:
                    (controller, navigationAction, code) async {
                      _logger.info("onHttpError with $code");
                    },
                onLoadStop: (controller, navigationAction) async {
                  _logger.info("onLoadStop $navigationAction");
                },
              ),
            ),
          ].nonNulls.toList(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  WebUri _getPaymentUrl(String? paymentToken) {
    final queryParameters = {
      'productID': widget.planId,
      'paymentToken': paymentToken,
      'action': widget.actionType,
      'redirectURL': kWebPaymentRedirectUrl,
    };
    final tryParse = Uri.tryParse(kWebPaymentBaseEndpoint);
    if (kDebugMode && kWebPaymentBaseEndpoint.startsWith("http://")) {
      return WebUri.uri(
        Uri.http(tryParse!.authority, tryParse.path, queryParameters),
      );
    } else {
      return WebUri.uri(
        Uri.https(tryParse!.authority, tryParse.path, queryParameters),
      );
    }
  }

  // show dialog to handle accidental back press.
  Future<bool> _buildPageExitWidget(BuildContext context) async {
    final result = await showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).areYouSureYouWantToExit),
        actions: <Widget>[
          TextButton(
            child: Text(
              AppLocalizations.of(context).yes,
              style: const TextStyle(color: Colors.redAccent),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
          TextButton(
            child: Text(
              AppLocalizations.of(context).no,
              style: TextStyle(
                color: Theme.of(context).colorScheme.greenAlternative,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
    if (result != null) {
      return result;
    }
    return false;
  }

  bool _isPaymentActionComplete(Uri? loadingUri) {
    return loadingUri.toString().startsWith(kWebPaymentRedirectUrl);
  }

  Future<void> _handlePaymentResponse(Uri uri) async {
    final queryParams = uri.queryParameters;
    final paymentStatus = uri.queryParameters['status'] ?? '';
    _logger.info('handle payment response with status $paymentStatus');
    if (paymentStatus == 'success') {
      await _handlePaymentSuccess(queryParams);
    } else if (paymentStatus == 'fail') {
      final reason = queryParams['reason'] ?? '';
      await _handlePaymentFailure(reason);
    } else {
      // should never reach here
      _logger.severe("unexpected status", uri.toString());
      await showGenericErrorDialog(
        context: context,
        error: Exception("expected payment status $paymentStatus"),
      );
    }
  }

  Future<void> _handlePaymentFailure(String reason) async {
    final shouldContactSupport = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).paymentFailed),
        content: Text(AppLocalizations.of(context).paymentFailedMessage),
        actions: <Widget>[
          TextButton(
            child: Text(AppLocalizations.of(context).contactSupport),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (shouldContactSupport == true) {
      await sendEmail(context, to: supportEmail, subject: "Billing issue");
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // return true if verifySubscription didn't throw any exceptions
  Future<void> _handlePaymentSuccess(Map<String, String> queryParams) async {
    final checkoutSessionID = queryParams['session_id'] ?? '';
    try {
      // ignore: unused_local_variable
      final response = await billService.verifySubscription(
        widget.planId,
        checkoutSessionID,
        paymentProvider: stripe,
      );
      if (!mounted) return;
      final content = widget.actionType == 'buy'
          ? AppLocalizations.of(context).yourPurchaseWasSuccessful
          : AppLocalizations.of(context).yourSubscriptionWasUpdatedSuccessfully;
      if (!mounted) return;
      await _showExitPageDialog(
        title: AppLocalizations.of(context).thankYou,
        content: content,
      );
    } catch (error) {
      _logger.severe(error);
      if (!mounted) return;
      await _showExitPageDialog(
        title: AppLocalizations.of(context).failedToVerifyPaymentStatus,
        content: AppLocalizations.of(
          context,
        ).pleaseWaitForSometimeBeforeRetrying,
      );
    }
  }

  // warn the user to wait for sometime before trying another payment
  Future<dynamic> _showExitPageDialog({String? title, String? content}) async {
    if (!mounted) return null;
    await showDialog(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title!),
        content: Text(content!),
        actions: <Widget>[
          TextButton(
            child: Text(
              AppLocalizations.of(context).ok,
              style: TextStyle(
                color: Theme.of(context).colorScheme.greenAlternative,
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop('dialog');
            },
          ),
        ],
      ),
    );
    if (!mounted) return null;
    return Navigator.pop(context, true);
  }
}
